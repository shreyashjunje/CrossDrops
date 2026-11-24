# Status (2026-11-25)

Everything below is on `main`. `flutter analyze` is clean and `flutter test` passes, on the PC and in CI on every push.

## What is built

All v1 features in CLAUDE.md are in the code: transfer engine with resume, discovery, QR, pinned TLS and pairing, media saving, sharing from other apps, the Night Signal UI, Android hotspot, the iPhone Personal Hotspot guide and benchmark builds. Built since, each unit-tested on the PC:

| Decision | What | Device checks |
| --- | --- | --- |
| D-068 | Real file names, previews, faster picking, original quality | N-1 to N-8 |
| D-069 | Redesign (Night Signal) | "Redesign" |
| D-070 | Security audit follow-up (S2, S7 to S10, S13) | "Audit follow-up" |
| D-071 | Data lanes, upload workers, stripes, tree hash (large files) | F-1 to F-6 |
| D-072 | Many files: export during the send, six lanes, grouped Photos saves | M-1 to M-6 |
| D-073, D-074 | Send by cable, both directions (usbmux); camera import removed | C-1 onward |
| D-075 | Send a whole folder; Select all in an album | D-1 to D-6 |
| D-076 | An offer is kept inside the 4 MB a receiver reads | (unit test) |
| D-077 | iPhone: a folder on another drive is checked for space before copying | D-7 |
| D-078 | Android: an empty folder pick gives its grant back | (none visible) |
| D-079 | Send a photo album as a folder | D-8 |

The Swift parts of D-068, D-072, D-075 and D-077 compile only in CI (no Mac here).

## What has run on phones

Only U-11, the cable test (iPhone 17 Pro and Samsung S20 FE, 2026-11-24): it passed. Nothing else has a result in [DEVICE_TESTS.md](DEVICE_TESTS.md), and [BENCHMARKS.md](BENCHMARKS.md) has PC loopback numbers only. **No phase is done** under the Definition of done.

## What is left

### 1. Device testing (blocks everything else)
- About 150 checks. Start with the smoke tests below, then the sections of the decisions above.
- The Phase 1 and 2 steps are out of date (typing an IP on the Send screen, files in the app's own folder). Bring them up to date before the full pass, or false failures follow.
- P7-5 (in-app hotspot join) needs a paid Apple Developer account; v1 uses the Settings route (P7-4).

### 2. Speed numbers
- M-1 (600 photos, iPhone to Android, same Wi-Fi) with the Android `log.txt`: the owner's "slow" report waits on it (D-072).
- BENCHMARKS.md on phones: router at 2.4 and 5 GHz, Android hotspot, iPhone hotspot, cable, both directions.
- Then decide the speed target, the buffer size and the number of lanes.

### 3. Deferred until device tests show a need
- Guiding users to OEM battery settings on Xiaomi, Oppo, Vivo and OnePlus ([keep-alive.md](features/keep-alive.md)).
- Keeping small files' TLS off the UI isolate (D-072, "Not done").
- Fixes for whatever the device tests turn up.

### 4. Before giving it to anyone
- App icon and an iPhone distribution route (TestFlight needs a paid account).
- Privacy text (no data leaves the local network) and a store listing, if it goes to the stores.
- Release signing is set up; create the key and add the CI secrets ([RELEASE.md](RELEASE.md)).

## What to do next, in order

1. **Build:** github.com > Actions > Build > Run workflow on `main` (and again with **bench** ticked). Download the APK and the IPA ([Installing the CI builds](DEVICE_TESTS.md#installing-the-ci-builds-no-mac-needed)). A failed iOS build means a Swift error: paste the log.
2. **Install** the APK with `adb install -r` and the IPA with Sideloadly.
3. **Smoke test:** P6-3 (iPhone to Android), P6-4 (Android to iPhone), P4-1 (pairing both ways), M-1 (many photos), C-1 (cable), D-1 (a folder). If one fails, stop and paste back screenshots and `adb logcat -s flutter`.
4. **Full device pass**, writing each result in its table with the date, OS versions and commit.
5. **Benchmarks** on the bench build, then the open speed decisions.
6. **Release prep** (section 4).
