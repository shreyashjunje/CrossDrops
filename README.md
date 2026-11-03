# CrossDrops
CrossDrop is a Flutter app that sends photos, videos and files directly between an iPhone and an Android phone over local Wi-Fi or a hotspot. No cloud server, no accounts.

## Status

- **Phase 1, file transfer proof of concept:** built and tested on devices.
- **Phase 2, discovery and QR connect:** built and tested on devices.
- **Phase 3, transfer engine:** built and tested on devices.
- **Phase 4, security:** built and tested on devices.
- **Phase 5, media and sharing:** built and tested on devices.
- **Phase 6, UI and onboarding:** built and unit-tested. Device checks (`docs/DEVICE_TESTS.md`, Phase 6) are pending.

What works in the code today:

- The receiver runs an HTTPS server. The sender offers several files, the receiver taps Accept, and the files go one after another with SHA-256 verification.
- Transfers resume by themselves after Wi-Fi drops and after either app restarts. Unfinished transfers are offered at launch.
- Cancel from either side, with progress, speed and time left on both.
- The screen stays on during transfers. Android keeps going with the screen off (foreground service). iPhone saves and pauses in the background, then continues.
- Phones on the same Wi-Fi find each other through Bonjour while CrossDrop is open on the receiver (Home shows "Ready to receive"). A QR code and a typed IP and port are the fallbacks, and "Can't find the other phone?" walks through QR, then hotspot mode.
- Each phone has its own key; its certificate fingerprint is its identity. Every connection is TLS 1.3, pinned to the receiver, and the sender proves its key with a signed challenge (`dart:io` cannot do mutual TLS with unknown certificates, D-027).
- New devices are checked with a 6-digit code shown on both phones. Trusted devices skip the code, can be set to auto-accept, and a trusted name with another key is flagged.
- A Receiving switch, rate limits and request size limits keep strangers on the Wi-Fi out.
- Photos and videos are picked from the library as originals (iCloud originals are downloaded first), other files from Files or the Storage Access Framework.
- Received photos and videos go to Photos or the gallery, other files to Files or Download/CrossDrop, without an extra copy.
- HEIC and HEVC are sent as they are. Converting HEIC to JPEG and sending Live Photo videos are settings.
- Share from Photos, Gallery, Files or any app opens CrossDrop with the files selected.
- Screens: Home, Send (files first, then the phone), Incoming request, Progress with Pause, Done with Open, Failed with the reason and next step, History, Settings, a three-page introduction. Dark mode, large text and screen readers are supported.

Requirements: iOS 15 or later, Android 10 or later.

Not yet built: starting or joining a hotspot from the app (the screens and the iPhone Personal Hotspot guide exist), and Android network binding on a hotspot without internet (Phase 7).

## Build and test

```sh
flutter pub get
flutter analyze
flutter test                      # unit tests, no phones needed
flutter test --run-skipped --tags large  # 2 GB test, needs ~4 GB disk
dart run tool/crossdrop_cli.dart        # dev tool: send to / receive from a phone, fake-qr
flutter run --release -d <device> # Android from any PC; iPhone needs a Mac with Xcode
```

After changing database tables in `lib/core/storage/database.dart`, run `dart run build_runner build`.

**CI and builds without a Mac:** the GitHub Actions workflow **Build** runs analyze and tests on every push. When started manually (Actions > Build > Run workflow) it also produces an Android APK and an unsigned iPhone `.ipa`. Install the `.ipa` from Windows with Sideloadly and a free Apple ID; the steps are in [docs/DEVICE_TESTS.md](docs/DEVICE_TESTS.md#installing-the-ci-builds-no-mac-needed).

## Docs

Start with [docs/README.md](docs/README.md). The design is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md); the checks that need real phones are in [docs/DEVICE_TESTS.md](docs/DEVICE_TESTS.md).
