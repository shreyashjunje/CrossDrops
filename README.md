# CrossDrops
CrossDrop is a Flutter app that sends photos, videos and files directly between an iPhone and an Android phone over local Wi-Fi or a hotspot. No cloud server, no accounts.

## Status

- **Phase 1, file transfer proof of concept:** built and tested on devices.
- **Phase 2, discovery and QR connect:** built and tested on devices.
- **Phase 3, transfer engine:** built and unit-tested. Device checks (`docs/DEVICE_TESTS.md`, Phase 3) are pending.

What works in the code today:

- The receiver runs an HTTPS server. The sender offers several files, the receiver taps Accept, and the files go one after another with SHA-256 verification.
- Transfers resume by themselves after Wi-Fi drops and after either app restarts. Unfinished transfers are offered at launch.
- Cancel from either side, with progress, speed and time left on both.
- The screen stays on during transfers. Android keeps going with the screen off (foreground service). iPhone saves and pauses in the background, then continues.
- Phones on the same Wi-Fi find each other through Bonjour while the receiver has Receive open. A QR code and a typed IP and port are the fallbacks.

Not yet built: pinned mutual TLS (the client currently accepts any certificate, see D-011), saving to Photos or the gallery, hotspot mode, and the final transfer UI.

## Build and test

```sh
flutter pub get
flutter analyze
flutter test                      # unit tests, no phones needed
flutter test --run-skipped --tags large  # 2 GB test, needs ~4 GB disk
flutter run --release -d <device> # Android from any PC; iPhone needs a Mac with Xcode
```

After changing database tables in `lib/core/storage/database.dart`, run `dart run build_runner build`.

**CI and builds without a Mac:** the GitHub Actions workflow **Build** runs analyze and tests on every push. When started manually (Actions > Build > Run workflow) it also produces an Android APK and an unsigned iPhone `.ipa`. Install the `.ipa` from Windows with Sideloadly and a free Apple ID; the steps are in [docs/DEVICE_TESTS.md](docs/DEVICE_TESTS.md#installing-the-ci-builds-no-mac-needed).

## Docs

Start with [docs/README.md](docs/README.md). The design is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md); the checks that need real phones are in [docs/DEVICE_TESTS.md](docs/DEVICE_TESTS.md).
