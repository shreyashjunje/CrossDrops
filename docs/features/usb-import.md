# Feature: Import from iPhone by cable

- Phase: 8 (after v1 scope)
- Status: Built, awaiting device tests
- Last updated: 2026-11-08

## Summary

An Android phone imports photos and videos from an iPhone plugged in with a cable (USB-C to USB-C, or Lightning to USB-C). Android's own file manager shows the iPhone as `DCIM/100APPLE`, `101APPLE`, ... with HEIC files, `.AAE` edit records and Live Photo videos mixed together and often no thumbnails, which makes choosing photos hard. CrossDrop reads the same files and shows them as one gallery, newest first, grouped by day, with Live Photos and edited photos shown as one tile. The chosen items are copied byte for byte into `Pictures/CrossDrop` and `Movies/CrossDrop`. The iPhone needs no app. See D-067.

## Scope

**In scope**

- iPhone → Android, photos and videos of the camera roll.
- Android phones with USB host mode (almost all).
- Choosing by tile, by day, "Select all shown"; filters All, Photos, Videos, Screenshots.
- Options: also copy Live Photo videos; also copy unedited originals.
- Progress, Stop (also in the middle of a file), and a summary. Items copied while the screen is open get a tick.

**Out of scope**

- Android → iPhone by cable, and files that are not in the camera roll (iOS gives a USB host only the camera roll, as a camera). Use Wi-Fi or hotspot mode.
- iPhone albums. The camera interface has no albums; the grid groups by day instead.
- Remembering what was copied after the screen closes ("only new since last time"). Later, with a database table.
- Copying with the screen off. The screen stays on while copying.

## Design

- **Transport:** the iPhone's camera interface (PTP) over USB, through `android.mtp.MtpDevice`. Android is the USB host. No network, no TLS: the cable is a direct link and the iPhone asks the user to allow access.
- **Finding the iPhone:** Apple vendor id `0x05AC` with a still-image interface (class 6). The manifest has a `USB_DEVICE_ATTACHED` filter, so Android offers to open CrossDrop when an iPhone is plugged in ("Always" also grants USB access). Inside the app, a home card appears while one is plugged in.
- **Opening:** USB permission, then `MtpDevice.open`. Errors map to screens: `permission_denied` (Try again), `busy` (another app, often Files, holds the interface), `locked` (no storage: the iPhone is locked or Allow was not tapped; tried again every 2 s).
- **Listing:** `UsbCameraChannel` walks the folders from the root, first in first out, each folder last to first, so the newest folder and files arrive first. Pages of 500 go to Dart, which rebuilds the roll after each page; the grid is usable while the rest loads.
- **Grouping** (`buildCameraRoll`): files are grouped by folder and name without extension, with the `E` of an edited copy removed (`IMG_E1234` → `IMG_1234`). In a group, the edited still (or the original still) is the tile; the matching video is its Live part; the unedited still is its original. A group without a still is a video. Anything that does not pair becomes its own tile, so no photo is hidden. `.AAE` and other non-media files are skipped and counted.
- **Thumbnails:** the iPhone's own JPEG preview (`GetThumb`), written to a cache file (`cache/usb_thumbs`, cleared on open and close), shown with `Image.file`. `ThumbnailQueue` asks two at a time, the newest request first, and drops requests of tiles that scrolled away. Previews and list pages are "quick" calls: they also run between the 1 MB parts of a copy, so they do not wait for a whole file.
- **Copy screen:** a large preview of the item being copied, the percentage, and a strip of every chosen item, ticked as each finishes (`ImportProgress.currentItem`, `copiedItems`).
- **Cable test:** Settings > About > Cable test (Android) runs `UsbTunnelProbe`: it lists the iPhone's USB interfaces, switches to the configuration with Apple's multiplexing interface (usbmux), does the usbmux handshake, and opens and resets TCP connections to the iPhone's built-in service (62078) and to CrossDrop's port. It checks whether Android → iPhone by cable can be built on usbmux (option (b) of D-067). Plain-text report, no file data.
- **Copying:** one file at a time (`ImportRunner`). For each file Kotlin creates a pending MediaStore item (the same path as received files, D-040), reads the object in 1 MB `GetPartialObject` parts into it, fsyncs and publishes. It never asks for more bytes than the iPhone declared, then asks for one byte past the end; if the iPhone has more, the item is deleted (`size_mismatch`). A device that refuses partial reads, and files of 4 GB or more (PTP's size field is 32 bits), are copied whole with `importFile` and checked against the declared size (or ≥ 4 GiB) afterwards. The free-space check covers the whole selection plus 200 MB before the first file (unknown sizes count as 4 GiB). A size mismatch or read error is tried once more, then counted as failed; unplugging, a full disk or a device error stops the import.
- **Dates:** `DATE_TAKEN` from the iPhone's date at insert; the media scanner reads EXIF and video metadata on publish.
- **Names:** sanitized in Dart (hard rule 5) before Kotlin uses them; never logged.

## Code

| Path | Purpose |
| --- | --- |
| `lib/core/usb_import/camera_roll.dart` | Objects to tiles, filters, day groups, copy plan. |
| `lib/core/usb_import/import_runner.dart` | Copy queue: space check, retry, stop reasons, progress. |
| `lib/core/usb_import/thumbnail_queue.dart` | Newest-first, cancellable preview loading. |
| `lib/platform/usb_camera.dart` | Dart interface and channel; `NoUsbCamera` elsewhere. |
| `lib/features/usb_import/` | Controller, screen, home card. |
| `android/.../UsbCameraChannel.kt` | MtpDevice access, listing, thumbnails, copies. |
| `android/.../SaveChannel.kt` | `insertPending`, `publish`, `deleteItem` shared with the cable import. |
| `android/app/src/main/res/xml/usb_device_filter.xml` | Apple + still-image filter for the attach intent. |

## Protocol and API

Channel `crossdrop/usb_camera`: `devices`, `open`, `nextPage`, `thumbnail`, `importFile`, `cancelCurrent`, `close`. Events on `crossdrop/usb_camera/events`: `attached`, `detached`, `progress`. Details in the header of `UsbCameraChannel.kt` and in `usb_camera.dart`.

## Tests

**Unit tests (no phones)**

- `test/core/usb_import/camera_roll_test.dart`: Live Photo and edited pairing, unpaired files kept, AAE skipped, sorting, filters, day groups, sanitized names, collections, unknown sizes.
- `test/core/usb_import/import_runner_test.dart`: order, free-space refusal, retry once, stop on unplug, full disk, cancel, per-item completion, progress.
- `test/core/usb_import/thumbnail_queue_test.dart`: newest first, cancel, cache, close.
- `test/platform/usb_camera_test.dart`: channel parsing and arguments.
- `test/features/usb_import/`: controller states (locked retry, busy, denied, unplug), selection, copy, space, Stop, progress; screen and home card.

**Device checks**

Listed in [DEVICE_TESTS.md](../DEVICE_TESTS.md), section "Cable import (D-067)".

## Known limits and risks

- **Not tested on a phone yet.** Whether an iPhone supports `GetPartialObject` through Android's MtpDevice is unknown; if not, the whole-file path is used (one-time log line `partial reads refused`).
- If the Android Files app or the system's MTP handler holds the iPhone, opening fails with `busy`; the user closes it and replugs.
- USB-C to USB-C: the Android phone must be the USB host. If the iPhone ends up as host, the user switches "USB controlled by" in the USB notification.
- iPhone setting *Transfer to Mac or PC*: "Automatic" makes the iPhone convert HEIC to JPEG and HEVC to H.264 while copying, so the files differ from the originals. The screen tells the user to choose "Keep Originals".
- The iPhone's date for an object is parsed by Android; time zone handling is to be checked on a device (U-4).
- Thumbnails wait behind a file being copied only on the whole-file path (no partial reads, or 4 GB and more).
- The cable test switches the iPhone's USB configuration; whether import still works afterwards without replugging is checked in U-11.
