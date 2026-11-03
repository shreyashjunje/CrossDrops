# Feature: Format handling between iPhone and Android

- Phase: 5
- Status: Built, awaiting device tests
- Last updated: 2026-11-03

## Summary

CrossDrop sends originals: the bytes in the library, not a re-encoded copy. HEIC stays HEIC and HEVC video stays HEVC. Two optional settings cover older Android galleries: convert HEIC to JPEG before sending, and send a Live Photo's video next to its still. Nothing else is transcoded in v1. Names and creation dates go with the file.

## Scope

**In scope**

- iPhone → Android:
  - HEIC original by default; JPEG on request.
  - Live Photo: the still by default; the still plus its video on request.
  - HEVC and HDR video unchanged.
- Edited items: the current version, named after the original.
- MIME type and kind detection for the offer; the receiver's own rules for where a file goes.
- Creation date.

**Out of scope**

- Transcoding video, or Dolby Vision to SDR.
- Rebuilding Live Photos on the receiver.
- Converting Android Motion Photos.

## Design

ARCHITECTURE.md, "Platform modules": HEIC photos, Live Photos, HEVC / HDR video, Android → iPhone formats. Decisions D-039 and D-042.

- **Plan** (`planExport`): for each library item, the settings and the receiver's platform give `convertToJpeg` and `includePairedVideo`.
  - The settings apply only when the receiver is not an iPhone; an unknown receiver counts as Android.
  - JPEG, PNG and videos are never converted.
- **Export** (iOS, `ExportChannel.swift`):
  - The current version of the original resource: `fullSizePhoto`/`fullSizeVideo` when edited, else `photo`/`video`.
  - The paired video is `fullSizePairedVideo` or `pairedVideo`.
  - JPEG: ImageIO re-encodes at quality 0.92 and copies metadata and the colour profile. The HDR gain map is lost.
- **Names** (`exportedFileName`, `pairedVideoName`): the original base with the exported extension, in the original's letter case:
  - `IMG_1234.HEIC` → `IMG_1234.JPG` when converted.
  - An edited `FullSizeRender.jpg` → `IMG_1234.JPG`.
  - A Live Photo video → `IMG_1234.MOV`.
  - Folders are dropped.
- **Kind and MIME type** (`detectFileType`): the library's kind first, then the OS MIME type (`application/octet-stream`, wildcards and malformed types ignored), then the extension. Audio, SVG, icons and PSD are files.
- **Settings:** Settings > "Sending photos to Android" (iPhone only), stored in `settings` (schema 4).
- **Android → iPhone:**
  - JPEG, PNG, HEIC, WebP, MP4 and MOV go to Photos.
  - WebM, Matroska and AVI go to Files directly.
  - Anything Photos refuses at save time also goes to Files, with a note.

## Code

| Path | Purpose |
| --- | --- |
| `lib/core/media/format_plan.dart` | `FormatSettings`, `LibraryAsset`, `planExport`, naming |
| `lib/core/protocol/file_type.dart` | `detectFileType`, `mimeForName`, `kindForMime` |
| `lib/core/media/save_target.dart` | Receiver collection rules |
| `ios/Runner/ExportChannel.swift` | Resource choice, JPEG conversion |
| `lib/core/storage/settings_repository.dart`, `lib/features/settings/settings_screen.dart` | The two settings |

## Protocol and API

None new. `livePhotoGroup` is filled for a still and its video when both are sent.

## Tests

**Unit tests (no phones)**

- `test/core/media/format_plan_test.dart`: defaults, each setting, iPhone receiver, unknown receiver, names of edited, converted and paired files.
- `test/core/protocol/file_type_test.dart`: extensions, precedence, junk MIME types, audio, SVG, `.ts`.
- `test/core/storage/settings_repository_test.dart`, `migration_test.dart`: defaults, setters, the 3 → 4 migration.

**Device checks**

[DEVICE_TESTS.md](../DEVICE_TESTS.md), section "Phase 5": P5-1, P5-2, P5-3, P5-10.

## Known limits and risks

- Dolby Vision HEVC from recent iPhones may look washed out in some Android players; the file is unchanged.
- Older Android galleries may not open HEIC; the setting is the answer. No automatic detection.
- A slow-motion video plays at normal speed (its high frame rate is kept).

## Open questions

- None.
