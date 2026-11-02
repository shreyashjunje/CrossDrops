# CrossDrops
CrossDrop is a Flutter app that sends photos, videos and files directly between an iPhone and an Android phone over local Wi-Fi or a hotspot. No cloud server, no accounts.

## Status

- **Phase 1, file transfer proof of concept:** built and unit-tested. Device checks are pending.
- **Phase 2, discovery and QR connect:** built and unit-tested. Device checks are pending.

What works in the code today:

- The receiver runs an HTTPS server; the sender streams files with resume and SHA-256 verification.
- Phones on the same Wi-Fi find each other through Bonjour while the receiver has Receive open.
- The receiver shows a QR code for networks that block discovery; a typed IP and port also works.
- On iPhone, the app detects when Local Network access is off and links to Settings.

Not yet built: the Accept prompt, pinned mutual TLS (the client currently accepts any certificate, see D-011), saving to Photos or the gallery, and hotspot mode.

## Build and test

```sh
flutter pub get
flutter analyze
flutter test                      # unit tests, no phones needed
flutter run --release -d <device> # Android from any PC; iPhone needs a Mac with Xcode
```

After changing database tables in `lib/core/storage/database.dart`, run `dart run build_runner build`.

**CI and builds without a Mac:** the GitHub Actions workflow **Build** runs analyze and tests on every push. When started manually (Actions > Build > Run workflow) it also produces an Android APK and an unsigned iPhone `.ipa`. Install the `.ipa` from Windows with Sideloadly and a free Apple ID; the steps are in [docs/DEVICE_TESTS.md](docs/DEVICE_TESTS.md#installing-the-ci-builds-no-mac-needed).

## Docs

Start with [docs/README.md](docs/README.md). The design is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md); the checks that need real phones are in [docs/DEVICE_TESTS.md](docs/DEVICE_TESTS.md).
