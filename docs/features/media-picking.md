# Feature: Media and file picking

- Phase: 5
- Status: Built, awaiting device tests
- Last updated: 2026-11-03

## Summary

The Send screen picks photos and videos from the library as originals (never a compressed copy) and any other file through the system document picker. Before anything is offered, the picks are prepared: iPhone library items are exported (downloaded from iCloud if needed), Android items are read in place. Items that cannot be prepared are left out with a clear reason.

## Scope

**In scope**

- "Photos & videos": our own grid on photo_manager, with albums, paging, Live and duration badges, and multi-select in tap order.
- "Files": SAF on Android (in place, persistable grant), the document picker on iOS (a copy moved into staging).
- Permissions:
  - iOS Full, Limited and denied access.
  - Android 13+ media permissions, Android 14 "selected photos", and `ACCESS_MEDIA_LOCATION`.
- Preparing: iCloud download with progress, cancel, and skipping with a reason.
- Staging folder and its cleanup.

**Out of scope** (and which phase picks it up)

- Sending while still exporting (big iCloud batches start only after all are ready): later, if device tests show it is needed.
- The system Photo Picker on Android 13+ (no permission needed). Only needed if the app goes to Google Play.

## Design

ARCHITECTURE.md, "Platform modules": picking, iCloud originals, reading for sending. Decisions D-036, D-037, D-038 and D-041.

- **Permissions** (`GalleryPickerScreen`):
  - Asked when the grid opens, never at launch, with `mediaLocation: true` (D-037).
  - Full access shows everything.
  - Limited access (iOS, Android 14) shows a banner: "CrossDrop can see only the photos you allowed", with **Select more** (system limited picker) and **Settings**. iOS's own automatic prompt is turned off (`PHPhotoLibraryPreventAutomaticLimitedAccessAlert`).
  - Denied shows how to allow access, with an **Open Settings** button, and points to "Files".
  - The grid reloads when the library or the limited selection changes, and when the app returns from Settings.
- **What the grid returns:** only ids, kinds, Live Photo flags and (Android) names. No bytes, and no file is read yet.
- **Preparing** (`Preparer`, on Send, after the receiver is checked, so its platform is known for the format rules):
  - **iOS** (`ExportChannel.swift`):
    - Reads the current version of the original resource with `PHAssetResourceManager`, network allowed, and writes it chunk by chunk to `<app support>/crossdrop_outgoing/<batch>/<n>/`.
    - Progress events drive "Preparing 2 of 5: downloading from iCloud 40%". 90 s without progress counts as an iCloud failure. Cancel stops the request and deletes the batch.
  - **Android:** the item's MediaStore content URI is opened as a descriptor (with `setRequireOriginal`) to check that it is readable and to get its exact size. Nothing is copied.
  - **Documents:** a path or content URI is opened the same way. A provider that cannot seek is streamed once into staging by Kotlin.
- **Skips:** iCloud failure, item gone (deleted, or no longer shared under Limited access), unreadable, no space. The Send screen lists up to five with the reason. No space skips the rest too. If nothing is left, nothing is offered.
- **Reading while sending:** `SendSession` opens each item through a `SourceOpener` once per file and closes it when that file ends. Before the offer it checks every source and closes it again, so 10,000 files never hold 10,000 descriptors.
- **Cleanup:**
  - Staged batches and SAF grants are released when a send ends for good. They are kept while it can still resume.
  - At launch, staging batches that no unfinished send uses are deleted.
  - A new selection releases the previous send's leftovers.

## Code

| Path | Purpose |
| --- | --- |
| `lib/features/send/gallery_picker_screen.dart` | Grid, albums, Limited and denied states |
| `lib/features/send/send_controller.dart` | Picks, prepare, send, cleanup |
| `lib/features/send/send_screen.dart` | Buttons, Preparing progress, skipped list |
| `lib/core/media/prepare.dart` | `Preparer`, `PickedItem`, `SkipReason`, staging cleanup |
| `lib/core/engine/source_opener.dart` | `SourceOpener`, `FileSourceOpener` |
| `lib/core/engine/chunked_reader.dart`, `fd_file.dart` | `ByteSource`, descriptor I/O (`FdFile`, `FdWorker`) |
| `lib/platform/ios_export.dart`, `ios/Runner/ExportChannel.swift` | iOS export channel `crossdrop/export` |
| `lib/platform/android_source.dart`, `android/.../SourceChannel.kt` | Android channel `crossdrop/source` |
| `lib/platform/document_picker.dart` | SAF and iOS document pickers |
| `lib/app/media_providers.dart` | Platform wiring |

## Protocol and API

No protocol change. `SendItem.path` is a file path or a `content://` URI. `SendItem.livePhotoGroup` is sent in the offer (already in the manifest).

## Tests

**Unit tests (no phones)**

- `test/core/media/prepare_test.dart`:
  - Names and kinds.
  - Edited items.
  - HEIC to JPEG and Live Photo video plans.
  - iCloud, deleted and no-space skips.
  - Cancel deletes the staged batch.
  - Progress.
  - Documents read in place.
  - Copy of providers that cannot seek.
  - Staging cleanup.
- `test/core/engine/send_session_test.dart`: content URIs through a `SourceOpener`, always closed, one at a time; a grant revoked mid-session.
- `test/core/engine/fd_file_test.dart`: real descriptors, the worker and the hash isolate (Linux CI and macOS).
- `test/platform/android_source_test.dart`: channel mapping.

**Device checks**

Listed in [DEVICE_TESTS.md](../DEVICE_TESTS.md), section "Phase 5": P5-1, P5-4, P5-5, P5-6, P5-9.

## Known limits and risks

- A big iPhone export needs its size again in free space until the send ends.
- Slow-motion videos arrive as the original high-frame-rate file, without the slow-motion ramp. Bursts send the chosen photo only.
- Samsung and Pixel Motion Photos are sent as the JPEG. The embedded video stays inside the file; iPhone Photos shows a still.
- Google Play would ask why CrossDrop needs `READ_MEDIA_*` rather than the Photo Picker. Not an issue for sideloaded builds.
- photo_manager still applies the Kotlin Gradle plugin; a future Flutter version will warn louder. Watch for an update.

## Open questions

- None.
