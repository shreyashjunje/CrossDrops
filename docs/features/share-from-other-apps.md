# Feature: Share from other apps

- Phase: 5
- Status: Built, awaiting device tests
- Last updated: 2026-11-03

## Summary

CrossDrop appears in the share sheet of Photos, Gallery, Files and any app that shares files. Choosing it opens CrossDrop's Send flow with those files already selected; the user picks the phone to send to. On iPhone a small Share Extension hands the files over through an App Group; on Android the share intent's content URIs are read in place.

## Scope

**In scope**

- Android: `SEND` and `SEND_MULTIPLE` for any type; a share arriving while the app runs; cold start.
- iOS: a Share Extension for images, movies and files (up to 500 each per share), an App Group inbox, opening the app.
- Safety checks on what is shared; text-only shares; a send already running; more than 10,000 items.

**Out of scope**

- Sending straight from the share sheet without opening CrossDrop.
- Sharing text or links.

## Design

ARCHITECTURE.md, "Platform modules": Share from other apps. Decisions D-044 and D-045.

- **Android** (`ShareChannel.kt`, `AndroidShareInbox`):
  - `MainActivity` is `singleTask`, so a share reaches the running instance (`onNewIntent`) instead of starting a second engine and server in the sharing app's task.
  - URIs come from `EXTRA_STREAM` and `ClipData`. Only `content://` URIs of other apps are accepted. A `file://` URI, or one of CrossDrop's own providers, is counted as refused: otherwise another app could make CrossDrop send its private files.
  - An intent is handled once (not again after rotation or from Recents).
  - Dart describes the URIs (name, size, MIME type, date) and treats them like SAF picks: read in place through a descriptor. The intent's grant lasts while the process lives.
- **iOS** (`ShareViewController.swift`, `IosShareInbox`):
  - **Type:** for each item the extension takes a movie, an image in its own type (HEIC stays HEIC), else a file. Plain text and web links are skipped.
  - **Copy:** `loadFileRepresentation` gives a temporary file, which is cloned into `<group>/Inbox/<uuid>/<n>/<name>`; the clone is instant on APFS and uses no memory. Only small image-only items are loaded as data.
  - **Hand-off:** `manifest.json` is written last and atomically. The extension opens `crossdrop://share?id=…`; if that is not possible it says "N files are ready. Open CrossDrop…".
  - **App side:** the app takes the inbox at launch, when the URL opens it (`SceneDelegate` → `arrived`) and on every return to the foreground. Each manifest is checked (`parseShareManifest`): version 1, at most 10,000 items, paths relative and inside the share, regular files (no links). The share is then moved into staging and the files are selected for Send. Broken shares are deleted and counted; shares without a manifest for an hour are deleted.
  - **Setup:** the App Group id comes from the `APP_GROUP_ID` build setting, through Info.plist (`CrossDropAppGroup`) on both sides. Without a usable App Group, the extension says sharing is not available.
- **Both** (`ShareListener`):
  - The files are added to the Send selection and the Nearby screen opens on top of whatever is open, so a running receive keeps going. If Nearby or Send is already open, nothing new opens.
  - A snack bar says how many files are ready, how many were refused or left out, or that only text was shared.
  - While a send runs, the share is refused with a message.

## Code

| Path | Purpose |
| --- | --- |
| `android/.../ShareChannel.kt`, `MainActivity.kt`, `AndroidManifest.xml` | Intent filters, singleTask, URI checks |
| `ios/ShareExtension/` | Extension, its Info.plist (activation rule) and entitlements |
| `ios/Runner/ShareInboxChannel.swift`, `SceneDelegate.swift`, `Runner.entitlements` | Container path, URL arrival, App Group |
| `ios/Runner.xcodeproj/project.pbxproj` | ShareExtension target, embedded before Thin Binary |
| `lib/platform/share_inbox.dart` | `ShareInbox`, Android and iOS inboxes, manifest checks |
| `lib/features/send/share_listener.dart` | Opens the Send flow; route tracking |

## Protocol and API

Channel `crossdrop/share`. Android: `takePending`. iOS: `containerPath`. Both: `arrived` (native to Dart). URL scheme `crossdrop://share` (iOS). Other `crossdrop://` links only bring the app forward.

## Tests

**Unit tests (no phones)**

- `test/platform/share_inbox_test.dart`: merging and capping; Android shares described into picks; describe failing; nothing pending.
- `test/platform/ios_share_inbox_test.dart`:
  - A complete share is taken once and moved into staging.
  - A share in progress waits; an abandoned one is deleted.
  - Items the extension could not read are counted.
  - Manifests are refused for paths outside the share, absolute paths, `.`/`..`, missing files, folders, links, unknown versions, junk and too many items.
  - Stray files in the inbox are removed.

**Device checks**

[DEVICE_TESTS.md](../DEVICE_TESTS.md), section "Phase 5": P5-9.

## Known limits and risks

- **The iOS extension has never been built.** It and the project file changes only compile in the CI macOS job; the first Phase 5 build is the test.
- Free Apple ID sideloading (Sideloadly) must sign both the app and the extension with the App Group. If the tool cannot, sharing on iPhone is unavailable and says so; the in-app pickers still work.
- Opening the app from the extension uses the responder chain, which is not a public API. If a future iOS blocks it, the files wait until CrossDrop is opened.
- A share from Photos is what Photos hands over, which can be a rendered JPEG rather than the HEIC original. Use the in-app picker for exact originals (P5-10).
- Android: a send of shared files cannot resume after the app was killed (the grant is gone). It stops with "a file could not be read any more"; share again.

## Open questions

- None.
