# CrossDrops
CrossDrop is a Flutter app that sends photos, videos and files directly between an iPhone and an Android phone over local Wi-Fi or a hotspot. No cloud server, no accounts.

## Status

- **Phases 1 to 7** (transfer engine, discovery and QR, security and pairing, media and sharing, UI, hotspot mode, benchmark builds): **built and unit-tested**. `flutter analyze` and `flutter test` run in CI on every push.
- **Not yet tested on devices.** The only device run so far is one 1.2 MB video from an Android phone to a PC ([docs/TODAY-2026-11-02.md](docs/TODAY-2026-11-02.md)). Every Results table in [docs/DEVICE_TESTS.md](docs/DEVICE_TESTS.md) and [docs/BENCHMARKS.md](docs/BENCHMARKS.md) is still empty, so no phase meets the Definition of done yet ([docs/STATUS.md](docs/STATUS.md)).
- The fixes from the code review of 2026-11-03 are in ([docs/CHANGELOG.md](docs/CHANGELOG.md)); the ones that need a phone are listed under "Code review fixes" in DEVICE_TESTS.md.

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

- Hotspot mode without Wi-Fi: the Android phone makes a network from the app and shows one QR code; the iPhone joins it (in-app with a paid Apple account build, otherwise guided through Settings). An iPhone Personal Hotspot guide checks that both phones are on the same network. On a Wi-Fi without internet, Android keeps CrossDrop's traffic on the Wi-Fi.
- Benchmark builds measure speed, CPU and memory for buffer sizes and network modes.

Requirements: iOS 15 or later, Android 10 or later.

The iPhone builds from CI are signed with a free Apple ID, which Apple does not allow to join a Wi-Fi network from an app; those builds guide the user through Settings > Wi-Fi instead.

## Build and test

```sh
flutter pub get
flutter analyze
flutter test                      # unit tests, no phones needed
flutter test --run-skipped --tags large  # 2 GB test, needs ~4 GB disk
dart run tool/crossdrop_cli.dart        # dev tool: send to / receive from a phone, fake-qr
flutter run --release -d <device> # Android from any PC; iPhone needs a Mac with Xcode
flutter build apk --release --dart-define=CROSSDROP_BENCH=true  # benchmark build, test phones only
```

After changing database tables in `lib/core/storage/database.dart`, run `dart run build_runner build`.

Android release builds need the release key in `android/key.properties`, or `CROSSDROP_ALLOW_DEBUG_SIGNING=true` for a test build signed with the debug key ([docs/RELEASE.md](docs/RELEASE.md)). The app id is `io.github.shreyashjunje.crossdrop` on both platforms.

**CI and builds without a Mac:** the GitHub Actions workflow **Build** runs analyze and tests on every push. When started manually (Actions > Build > Run workflow) it also produces an Android APK and an unsigned iPhone `.ipa`. Install the `.ipa` from Windows with Sideloadly and a free Apple ID; the steps are in [docs/DEVICE_TESTS.md](docs/DEVICE_TESTS.md#installing-the-ci-builds-no-mac-needed).

## Docs

Start with [docs/README.md](docs/README.md). Release signing and app ids: [docs/RELEASE.md](docs/RELEASE.md). Licence: [LICENSE](LICENSE) (all rights reserved). The design is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md); the checks that need real phones are in [docs/DEVICE_TESTS.md](docs/DEVICE_TESTS.md).
