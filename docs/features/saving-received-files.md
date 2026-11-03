# Feature: Saving received files

- Phase: 5
- Status: Built, awaiting device tests
- Last updated: 2026-11-03

## Summary

Received photos and videos land where the user looks for them: the Photos library on iPhone, the gallery on Android. Other files go to Files (iPhone) or Download/CrossDrop (Android). Nothing is copied on the way: Android writes the arriving bytes straight into a pending MediaStore item, and iPhone moves the verified file into Photos. If the gallery refuses a format, the file goes to Files or Downloads and the Receive screen says so.

## Scope

**In scope**

- Android: Pictures/CrossDrop, Movies/CrossDrop, Download/CrossDrop via MediaStore; pending items; storage-full handling; cleanup.
- iOS: Photos with add-only access (moved), Documents (Files > On My iPhone > CrossDrop), fallback with a note.
- Creation dates (D-042).
- The Receive screen shows where each file went.

**Out of scope** (and which phase picks it up)

- Rebuilding a Live Photo from a still and a video on iPhone (iPhone-to-iPhone is out of v1).
- A history screen with "Open" and "Show in gallery": Phase 6.

## Design

ARCHITECTURE.md, "Platform modules": saving received media and other files. Decisions D-040, D-042, D-043.

- **Where a file goes** (`saveCollectionFor`):
  - Chosen from the sanitized name's extension. The declared MIME type is never used, and a declared kind only counts if it matches the extension: a "photo" called `.apk` is a file.
  - Each platform has its own list of formats its gallery takes. iOS: no WebM, Matroska, AVI or MPEG-TS.
- **Receive server:** it uses a `ReceivedFileStore` for every partial-file operation: open, append, sync, truncate, restore, delete, save. A file's location (in `tempPath`) is a path or a content URI and may change when the part is first created.
- **Android** (`MediaStoreFileStore`, `SaveChannel.kt`):
  - **First byte:** insert a pending item (`IS_PENDING=1`, `RELATIVE_PATH`, `DISPLAY_NAME`, MIME type from the extension, `DATE_TAKEN`) and open it read-write. The URI is stored at once.
  - **Writing:** goes through `FdWorker` (D-036). Checkpoints fsync the descriptor. After a crash the item is cut back to the checkpoint. If the item vanished, the file starts over in a new item.
  - **Verified:** the file time is set to the creation date, then the item is published. MediaStore resolves name clashes itself.
  - **Refused MIME type:** the item goes into Downloads, with the note "the gallery cannot open this format".
  - **Disk full** (ENOSPC on write, or a full database on insert): 507 `no_space`; the session pauses and keeps the item.
  - **Cleanup:** cancel, a failed file and the 24-hour cleanup delete the item. At launch, this app's pending items older than 24 hours that no session uses are deleted.
- **iOS** (`FolderStore` + `IosPhotosSaver`, `PhotosSaveChannel.swift`):
  - The partial file stays in `<app support>/crossdrop_incoming/<session>/`.
  - **Photos and videos:** when verified, `PHAssetCreationRequest` with `shouldMoveFile`, the original name and the creation date.
  - **Add-only access:** asked when the user taps Accept on an offer with media; a save waits for the answer.
  - **Photos refuses the file, or access is denied:** it goes to Documents, with a note.
  - **Other files:** go to Documents directly. Name clashes become "name (1).ext"; the name is claimed by creating the file exclusively before the move, so two saves at once never share one (review L1). The modification date is the creation date.
- **Receive screen:** "Photos go to … other files go to …" while waiting. Each saved file shows "Saved to Photos" or "Saved to Download/CrossDrop (the gallery cannot open this format)".
- **Database:** moved out of Documents to Application Support (D-034), so Files shows only received files.

## Code

| Path | Purpose |
| --- | --- |
| `lib/core/server/file_store.dart` | `ReceivedFileStore`, `PartFile`, `FolderStore`, `MediaSaver`, `SaveResult` |
| `lib/core/server/receive_server.dart` | Uses the store; `FileSaved.collection` and `fallback` |
| `lib/core/media/save_target.dart` | `saveCollectionFor` |
| `lib/platform/android_store.dart`, `android/.../SaveChannel.kt` | MediaStore store, channel `crossdrop/save` |
| `lib/platform/ios_photos.dart`, `ios/Runner/PhotosSaveChannel.swift` | Photos saver, channel `crossdrop/photos` |
| `lib/core/storage/partial_cleanup.dart` | `deletePart` for parts outside the session folder |
| `lib/core/storage/database_location.dart` | One-time database move (D-034) |
| `lib/features/receive/` | Where each file went |

## Protocol and API

No protocol change. `session_files.tempPath` can be a content URI. `finalLocation` is a path, a content URI or `photos:<localIdentifier>`; it is never shown or logged.

## Tests

**Unit tests (no phones)**

- `test/core/media/save_target_test.dart`: collections on both platforms; the declared MIME type is ignored; kind and extension must agree; iOS-only refusals.
- `test/core/server/file_store_test.dart`:
  - `FolderStore`: restore, clashes, dates, gallery saver taken, refused, full.
  - A store whose parts live outside the folder: the location is stored, cancel deletes it, restart restores from it.
- `test/platform/android_store_test.dart` (fake MediaStore over the real server): published item, collections, refused MIME type to Downloads, storage full at insert, cancel deletes, an item gone after restart starts over, orphan cleanup.
- `test/core/storage/transfer_repository_test.dart`: expired parts go through `deletePart`.
- `test/core/storage/database_location_test.dart`: the move, no overwrite, an interrupted move.
- `test/features/transfer/transfer_format_test.dart`: "Saved to …" wording.

**Device checks**

[DEVICE_TESTS.md](../DEVICE_TESTS.md), section "Phase 5": P5-2, P5-3, P5-7, P5-8, P5-10.

## Known limits and risks

- iOS Photos may need temporary space while it imports a moved file; a nearly full iPhone can refuse a video that fit when the offer was accepted. It then goes to Files.
- The Android "refused format" note is kept in memory: after an app restart mid-file, the file still lands in Downloads but without the note.
- Some galleries index `Movies/` and `Pictures/` items only after a moment; the item is published and scanned when the hash is verified.

## Open questions

- None.
