# CrossDrop

CrossDrop is a Flutter app that sends photos, videos and files directly between an iPhone and an Android phone over local Wi-Fi or a hotspot. No cloud server, no accounts.

Full design: `docs/ARCHITECTURE.md`. Read it before doing any work. Follow it. If you think it is wrong or incomplete, say so and ask before deviating.

## Scope (v1)
- iPhone to Android and Android to iPhone only. Both phones nearby, app open in the foreground.
- Connection modes: same Wi-Fi (Bonjour/mDNS), QR code fallback, Android hotspot, iPhone Personal Hotspot (user enables it manually).
- Out of scope: accounts, cloud storage, chat, relay servers, receiving while the iPhone app is closed, iPhone-to-iPhone and Android-to-Android testing.

## Core design (summary of the architecture doc)
- The receiver runs an HTTPS server. The sender is the client. This holds in every network mode.
- Protocol: HTTPS + JSON for control, streamed PUT bodies for file bytes, one WebSocket per session for events. All endpoints under `/v1`.
- Resume: the receiver writes to a `.part` file and reports `receivedBytes`. The sender continues with `PUT ...?offset=N`.
- Integrity: SHA-256 computed incrementally while streaming, sent in `/complete`, verified before saving.
- Security: each device has its own key and self-signed certificate; the certificate's SHA-256 fingerprint is the device identity. Mutual TLS with pinning. The receiver must tap Accept for any untrusted sender.
- Discovery: `_crossdrop._tcp` with TXT records `v`, `id`, `n`, `p`, `fp` (fingerprint hint only).

## Tech stack
- Flutter (Dart), Riverpod for state, drift or sqflite for the local database.
- Dart `dart:io` HTTPS server (shelf) and client. No native networking unless the architecture doc says so.
- Native Swift (iOS) and Kotlin (Android) only for: photo library access and saving, hotspot, background and foreground-service behavior, Bonjour/NSD details, share extension and share intent.
- Suggested packages (verify before use): `shelf`, `shelf_web_socket`, `bonsoir`, `photo_manager`, `file_picker`, `wakelock_plus`, `flutter_foreground_task`, `qr_flutter`, `mobile_scanner`, `cryptography`, `drift`, `flutter_riverpod`, `receive_sharing_intent`.

## Repo structure
```
lib/app/            routing, theme, providers
lib/features/       home, nearby, send, receive, transfer, hotspot, history, settings
lib/core/protocol/  message models, versioning, JSON
lib/core/server/    HTTPS server, routes, session handlers
lib/core/client/    HTTPS client, upload streams, retry and backoff
lib/core/engine/    chunking, resume, hashing (isolate), queue
lib/core/discovery/ bonsoir wrapper, TXT parsing
lib/core/security/  identity, certificates, pinning, 6-digit code
lib/core/storage/   database, temp files, cleanup
lib/platform/       Dart side of platform channels
ios/ and android/   native modules listed in the architecture doc
test/               unit tests (no phones needed)
integration_test/   two-device tests
docs/               ARCHITECTURE.md, BENCHMARKS.md, DEVICE_TESTS.md
```

## Hard rules
1. Never load a whole file into memory. Always stream, with buffers around 1 MB.
2. Never pass file bytes through platform channels. Pass paths or file descriptors.
3. Hash in a background isolate so the UI never stutters.
4. Never fall back to an unpinned or unverified TLS connection once a fingerprint is known.
5. Sanitize every received file name: strip paths, control characters and reserved names; limit length; never write outside the app's temp or save folders.
6. Check free space before accepting an offer. Never trust declared sizes: stop if more bytes than declared arrive.
7. Never log file contents, full file names with personal data, certificates' private keys, or QR payloads.
8. Do not add a package without saying why. Do not add analytics or any network call to anything outside the local network.
9. Keep platform-specific code behind a Dart interface so the core stays testable.
10. Match the existing code style. Run `dart format .` before committing.

## Workflow (every task)
1. Read this file and `docs/ARCHITECTURE.md`. Read the code you will change.
2. For anything bigger than a small fix: write a short plan first (files to touch, packages, risks) and wait for my OK.
3. Build in small steps. After each step run `flutter analyze` and `flutter test`. Fix everything before moving on.
4. Write unit tests for protocol, resume, hashing, file-name sanitizing and state machines. They must run on my computer with no phones.
5. Commit after each working step with a clear message. One concern per commit.
6. When something needs a real device, stop. Give me exact steps to test, what to expect, and what logs or screenshots to paste back. Do not claim a device feature works until I confirm it.
7. At the end of a task, summarize: what changed, what is tested, what is not yet tested on devices, and any open questions.

## Definition of done (per phase)
- `flutter analyze` has no warnings. `flutter test` passes.
- The phase's acceptance checks in `docs/DEVICE_TESTS.md` are written, and I have run them on one iPhone and one Android phone.
- `docs/ARCHITECTURE.md` is updated if the design changed.

## Known risks to keep in mind
- iOS asks for Local Network permission on first discovery. If denied, discovery fails silently: detect it and explain.
- iOS apps are paused when the screen locks. Keep the screen awake during transfers, save progress often, resume on return.
- Android may route traffic over mobile data when the Wi-Fi has no internet (hotspot). Bind sockets to the Wi-Fi network.
- Some Android brands kill background apps. Use a foreground service and guide the user to battery settings if needed.
- Some Wi-Fi networks block device-to-device traffic. QR and hotspot mode are the fallbacks.
- `dart:io` TLS support for self-signed client certificates may have limits. If it does, say so and propose an alternative (for example an application-layer signed challenge) before building it.

## Communication
- Be concise. Say what you did and what you did not verify.
- If instructions conflict with the architecture doc, ask.
- Never say something works on iPhone or Android unless a test or I confirmed it.