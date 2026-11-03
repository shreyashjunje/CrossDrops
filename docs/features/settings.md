# Feature: Settings

- Phase: 6
- Status: Built, awaiting device tests
- Last updated: 2026-11-03

## Summary

One screen for what the user can change: this phone's name, whether it is ready to receive, how photos are sent to Android (iPhone only), which devices are trusted. Help and About are reached from here.

## Scope

**In scope**

- Device name, Receiving, Convert HEIC to JPEG, Send Live Photo videos, Trusted devices (auto-accept, Forget), Can't find the other phone?, Show the introduction, About.

**Out of scope**

- Theme choice: the app follows the system light or dark setting.
- Save location choice: fixed by platform ([saving-received-files.md](saving-received-files.md)).
- Battery optimisation guidance for Android brands that kill apps: Phase 7, with the hotspot work.

## Design

| Section | Setting | Stored in | Notes |
| --- | --- | --- | --- |
| This phone | Device name | `identity.deviceName` | Sanitised, at most 63 UTF-8 bytes (TXT `n`). Receiving restarts with the new name if nothing is in flight; other phones see it the next time they search |
| Receiving | Ready to receive when CrossDrop is open | `settings.receivingEnabled` | The same setting as the Home switch, so it is also the default at the next launch (D-031, D-046) |
| Sending photos to Android (iPhone only) | Convert HEIC to JPEG; Send Live Photo videos | `settings.convertHeicToJpeg`, `sendLivePhotoVideo` | Both off: originals, still only (D-039) |
| Security | Trusted devices | `trusted_devices` | Own screen: name, platform, short key, "Accept without asking", Forget with confirmation |
| Help | Can't find the other phone?; Show the introduction; About CrossDrop | | About: what CrossDrop does, privacy, security, this phone's full key in groups of four, licenses, version |

The version shown in About is `lib/app/version.dart`. A test keeps it equal to `pubspec.yaml`, so no package is needed to read it.

## Code

| Path | Purpose |
| --- | --- |
| `lib/features/settings/settings_screen.dart` | Settings |
| `lib/features/settings/trusted_devices_screen.dart` | Trusted devices |
| `lib/features/settings/about_screen.dart` | About |
| `lib/app/version.dart` | Version for About |

## Protocol and API

None.

## Tests

**Unit and widget tests (no phones)**

- `test/features/settings/settings_screen_test.dart`: iPhone shows format options and saves them; Android does not; Receiving off is saved; trusted devices are listed and Forget removes one; About shows the version.
- `test/app/version_test.dart`.
- `test/a11y/app_screens_test.dart`: guidelines, small phone with 2× text.

**Device checks**

[DEVICE_TESTS.md](../DEVICE_TESTS.md), Phase 6, P6-9.

## Known limits and risks

- During a transfer a rename waits: the new name is advertised the next time receiving starts. Phones that already listed this phone show the old name until they search again.

## Open questions

None.
