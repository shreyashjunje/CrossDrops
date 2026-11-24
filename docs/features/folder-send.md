# Feature: Send a folder, Select all

- Phase: 8 (after v1 scope)
- Status: Built, awaiting device tests
- Last updated: 2026-11-24

## Summary

Send > Folder sends every file in a folder and its subfolders; the other phone gets the same folder. In the photo picker, Select all picks a whole album. See D-075.

## Flow

```text
Send > Folder > system folder picker
  Android: tree grant, walk, read in place       iOS: security scope, clone into staging
                         \                      /
                  PickedFile(name, folder: "Trip/Day 1")
                                  |
            offer: FileOffer.folder per file (normal protocol)
                                  |
        receiver: sanitize each part, save under the folder
          Android: Download/CrossDrop/Trip/Day 1/   iOS: Files > CrossDrop > Trip > Day 1
```

## Code

| Path | Purpose |
| --- | --- |
| `lib/core/protocol/models.dart` | `FileOffer.folder`, validation. |
| `lib/core/storage/file_name_sanitizer.dart` | `sanitizeFolderPath`. |
| `lib/core/media/save_target.dart` | `folderOf`, `collectionForOffer`: folder files stay in files. |
| `lib/core/server/file_store.dart`, `lib/platform/android_store.dart` | Save under the folder. |
| `lib/core/storage/database.dart` | `session_files.folder`, schema 6. |
| `lib/platform/document_picker.dart` | `pickFolder`, `parseFolderPick`. |
| `android/.../SourceChannel.kt` | `pickFolder`: tree walk; tree grant release. |
| `android/.../SaveChannel.kt` | `create {folder}`: subfolder under Download/CrossDrop. |
| `ios/Runner/OpenFileChannel.swift` | `pickFolder`: folder picker, clone into staging. |
| `lib/features/send/send_screen.dart` | Folder source, "+N" tile, left-out note. |
| `lib/features/send/gallery_picker_screen.dart` | Select all / Deselect all. |

## Tests (no phones)

- `test/core/folder_send_test.dart`: a folder end to end, byte for byte; `../` cannot leave the save folder; a receiver restart keeps the folder.
- `test/platform/android_store_test.dart`: a folder photo goes to Downloads with its folder.
- `test/core/storage/file_name_sanitizer_test.dart`, `test/core/protocol/models_test.dart`, `test/core/storage/migration_test.dart`.
- `test/platform/document_picker_test.dart`, `test/features/send/send_controller_test.dart`, `test/features/send/send_screen_test.dart`.

Device checks: [DEVICE_TESTS.md](../DEVICE_TESTS.md), section "Folders and Select all (D-075)".

## Known limits

- Empty folders are not sent.
- A folder shows as its files on the Send screen; there is no single item to remove it in one tap (Clear removes everything).
- Photos sent inside a folder go to Files on the iPhone, not to Photos.
- iCloud files that are not on the iPhone are left out and counted.
- Sending the same folder again adds to the folder already there: files whose names are taken get " (1)" (`IMG_1.jpg` and `IMG_1 (1).jpg`). No new `Trip (1)` folder is made.
- A file whose folder path is longer than 1,024 characters is left out and counted, so the rest of the folder can still go.
- Removing one file of a folder from the selection keeps the folder's Android grant until the selection is sent or cleared.
