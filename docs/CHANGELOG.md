# Changelog

All notable changes to CrossDrop and its docs. Newest first. Loosely follows [Keep a Changelog](https://keepachangelog.com): group entries under Added, Changed, Fixed or Removed, under a heading of the date (`## YYYY-MM-DD`) or version once releases exist.

## 2026-11-03

### Fixed (code review 2026-11-03)
- **Security (H1):** the sender's auth commitment now covers both fingerprints as well as its nonce, so a man in the middle can no longer choose a certificate that makes both pairing codes match. Protocol version 2; version 1 is refused (D-061).
- **Security (H2):** declared file sizes are capped at 1 TiB and an offer at 4 TiB, so sizes can no longer wrap the 64-bit total and slip past the free-space check.
- **Hotspot (H3):** leaving the hotspot screen, or tapping Stop, while the hotspot is still starting no longer leaves it running with no screen.
- **Sharing (H4):** on an iPhone cold start, files shared from another app could be deleted by the launch cleanup before Send used them. The share is now taken after the cleanup, and the cleanup keeps staging folders younger than 10 minutes.
- **Receiver resources (M1, M2, L3):** ended sessions are forgotten after 5 minutes (at most 32 kept), offers never accepted are removed from the database, paused sessions expire after 24 h, at most one hash isolate runs per session, and parallel offers can no longer slip past the one-per-sender and 8-open-sessions limits.
- **Receiver keep-alive (M3, L6):** a paused received session no longer keeps the screen on, the Android notification up and the server running for good; it lets go 150 s after the pause, also with Receiving off (D-062).
- **iPhone receiver after the lock screen (M6):** when CrossDrop comes back on screen it checks that its server still answers and restarts it on a new port if iOS took the socket back while suspended. Needs a device check.
- **Pause (M4):** a pause asked between two uploads, while connecting or while authenticating, was dropped and the whole file was sent; on iPhone the background task always waited its full 10 s and could be suspended mid-upload. The pause is now kept until an upload sees it, and backgrounding waits only until the upload has stopped.
- **Cancel (M5):** cancelling while connecting showed "network" failure; cancelling while the offer was on its way could leave the offer on the receiver. Both now end as cancelled, and an offer that arrived is withdrawn.
- **Saving (L1):** two files with the same name saved at the same moment could end up at one path, the second replacing the first. The save now claims its name by creating the file exclusively first.
- **Complete (L2):** `/complete` checks the session and file again after reading its body, so two completes of an empty file no longer save it twice and a cancel during the body read no longer leaves a part and folder behind.
- **Cancel (L4):** Cancel while a typed address is being checked now stops the send; it used to do nothing and the send went on.
- **Resume (L5):** picking new files after a send failed but could still resume deleted that send's staged files but left it marked resumable, so the next launch offered a Resume that could only fail, and the receiver kept the old session (the next send to it got "busy"). The old send is now discarded properly: marked cancelled and withdrawn from the receiver.
- **Android network binding (L7):** a Wi-Fi loss reported while a bind was running could leave the binder thinking it was bound, so the next Wi-Fi without internet was not bound. Changes are now applied one at a time.
- **Names (L8):** received file names lose bidi controls and zero-width characters (`photo<RLO>gpj.exe` showed as `photoexe.jpg`), C1 control characters become `_`, and the receiver sanitizes offered file names and the sender's name on arrival, so every screen shows the name that is saved.

### Changed (speed, code review 2026-11-03)
- The receiver reads the socket up to 8 MB ahead of the disk, so writing, hashing and checkpoints no longer stall the sender (D-064).
- Checkpoints (fsync and a database write) every 2 s or 64 MB instead of every 4 MB (D-065).
- The sender reads the next 1 MB while the current one is being sent, so disk reads and the network overlap.
- Android descriptor reads and writes reuse one native buffer in the I/O worker and copy once, straight into transferable memory, instead of allocating, zero-filling and copying twice per megabyte.
- Benchmark builds: Settings > Benchmark > **Measure this phone** times SHA-256, pinned TLS on loopback and writes with both checkpoint paces, so each cost is known before the next change (BENCHMARKS.md Step 0, D-066). The larger speed items wait for those numbers.

### Changed (release preparation, code review 2026-11-03)
- **App id** `io.github.shreyashjunje.crossdrop` on Android and iOS (extension `.ShareExtension`, App Group `group.io.github.shreyashjunje.crossdrop`) instead of `com.example.crossdrop` (D-063). Test phones get it as a new app; uninstall the old one.
- **Android release signing:** a real key from `android/key.properties` or CI secrets; a release build without one fails unless `CROSSDROP_ALLOW_DEBUG_SIGNING=true` marks it as a test build. CI names such APKs `*-debugsigned` ([RELEASE.md](RELEASE.md)).
- LICENSE (all rights reserved), pubspec description, and README status that matches the device-test records (built and unit-tested; not yet tested on devices).

### Added (Phase 7)
- Android hotspot from the app ([features/android-hotspot.md](features/android-hotspot.md)): LocalOnlyHotspot with one QR code holding the Wi-Fi name, password and connection info, plus a Wi-Fi code for the iPhone Camera. Asks for Nearby devices (Android 13+) or Location (10–12) at Start, explains every refusal, stops when the screen closes or 60 s after the last transfer, with Keep on.
- iPhone joins that network ([features/iphone-join-hotspot.md](features/iphone-join-hotspot.md)): in-app with NEHotspotConfiguration when the build has the Hotspot Configuration capability (paid Apple account), otherwise guided through Settings with Copy password; handles Cancel, an iPhone already on the network, and removes the network afterwards (D-055).
- Android network binding ([features/android-network-binding.md](features/android-network-binding.md)): on a Wi-Fi without internet, CrossDrop's traffic stays on the Wi-Fi instead of mobile data (D-056).
- iPhone Personal Hotspot guide in three steps with a live check of the hotspot, the join and the same subnet ([features/iphone-personal-hotspot-guide.md](features/iphone-personal-hotspot-guide.md)).
- Nearby suggests hotspot mode, with an explanation of guest and public Wi-Fi, when nothing was found and a QR code or address did not answer.
- Benchmark builds (`--dart-define=CROSSDROP_BENCH=true`, CI input `bench`): Settings > Benchmark runs sizes × buffers × repeats through the real engine and writes CSV with MB/s, peak, CPU and memory from both phones ([features/benchmark-mode.md](features/benchmark-mode.md), D-058). Benchmark protocol and LocalSend comparison in [BENCHMARKS.md](BENCHMARKS.md).
- QR payload: optional `ws`, `wp`, `wsec` fields.
- Docs: decisions D-054 to D-059, Phase 7 device checks.

### Changed (Phase 7)
- The upload buffer size is a parameter (default still 1 MB) so it can be benchmarked.
- `fake_async` is a declared dev dependency (already pulled in by `flutter_test`), for timer tests.

### Added (Phase 6)
- Screens ([features/ui-navigation.md](features/ui-navigation.md)):
  - Home: "Ready to receive" with the device name, the Receiving switch, Show my QR code, transfers in progress and one large Send button.
  - Send: pick files first, see the count and size, then choose the phone.
  - Nearby: platform and connection hint per phone, Scan QR code, Enter IP, and "Can't find the other phone?" (basics, then QR, then hotspot mode).
  - Incoming request: full screen over any screen, with sender, platform, trusted or first-time warning, files, size, names, code, Trust this device and a countdown.
  - Progress for both directions: per-file and total progress, speed, time left, Pause and Resume on the sender, Cancel, and "Keep CrossDrop open and the screen on" on iPhone.
  - Done and Failed: where files were saved, Open, the reason in plain words and the next step with a button.
  - Hotspot mode: UI and the iPhone Personal Hotspot guide. Starting a hotspot from the app is Phase 7.
  - History, Settings (sections, Trusted devices screen, About).
- Onboarding ([features/onboarding.md](features/onboarding.md)): three pages on first launch. Receiving, and so the iOS Local Network prompt, starts after them.
- Dark mode following the system; WCAG AA contrast, 48 dp touch targets, screen-reader labels; accessibility guideline tests on every new screen, including 2× text on a small phone.
- Open received files through a small `crossdrop/open` channel (D-051).
- Database schema 5: `settings.onboardingDone`, with a migration test.
- Docs: [features/settings.md](features/settings.md), decisions D-046 to D-053, Phase 6 device checks and a screen review checklist.

### Changed (Phase 6)
- **Receiving runs whenever CrossDrop is open** (D-046). The Receive screen is gone; its QR code is under "Show my QR code". The server stops after 30 s in the background with nothing in flight, and no longer keeps the screen on by itself.
- Sending starts from Home > Send with files; shares from other apps open the Send screen (D-052).
- Failure wording comes from one table that follows ARCHITECTURE.md's failure table (D-049).
- A rename restarts receiving, so other phones see the new name.

### Fixed (Phase 6)
- With receiving running from launch, the server now waits for the launch cleanup of expired partial files before it restores sessions. Discarding a received transfer goes through the running server.

### Added (Phase 5)
- Picking ([features/media-picking.md](features/media-picking.md)):
  - "Photos & videos": a gallery grid on photo_manager with albums, Live and duration badges, Limited access ("Select more", Settings) and a denied screen.
  - "Files": Storage Access Framework on Android (read in place) and the document picker on iOS.
  - Picks are prepared before the offer:
    - iPhone exports the original (edits applied, named after the original), downloads iCloud originals with progress and Cancel.
    - Items that cannot be prepared are left out with the reason.
    - Android reads content URIs in place through file descriptors (`dart:ffi`), with the GPS location kept.
- Saving ([features/saving-received-files.md](features/saving-received-files.md)):
  - Android writes straight into a pending MediaStore item: Pictures/CrossDrop, Movies/CrossDrop or Download/CrossDrop, published when the hash matches.
  - iPhone moves photos and videos into Photos (add-only access) and other files into Files > On My iPhone > CrossDrop.
  - Formats the gallery refuses, or no Photos access, fall back to Files or Downloads with a note.
  - The Receive screen shows where each file went.
- Formats ([features/format-handling.md](features/format-handling.md)):
  - Originals by default.
  - iPhone settings "Convert HEIC to JPEG" and "Send Live Photo videos" (to Android only).
  - HEVC sent unchanged.
  - Creation dates kept where the platform allows (D-042).
- Share from other apps ([features/share-from-other-apps.md](features/share-from-other-apps.md)):
  - An iOS Share Extension with an App Group inbox.
  - Android `SEND`/`SEND_MULTIPLE`.
  - Both open Send with the files selected.
- Database schema 4 (format settings), with a tested migration.
- Tests without phones:
  - MIME type and kind detection, save collections, format plan and names.
  - Preparing and skipping, staging cleanup.
  - Descriptor I/O (Linux CI).
  - The folder and MediaStore stores over the real server (fake MediaStore).
  - Share inbox and manifest attacks, settings.
- Docs: decisions D-034 to D-045, Phase 5 device checks, ARCHITECTURE.md platform modules, transfer rules, failures and data model.
- Packages: `photo_manager` (gallery grid and permissions, D-038), `ffi` (descriptor I/O, D-036).

### Changed (Phase 5)
- **Android 10 is now the minimum** (D-035).
- The database moved from Documents to Application Support; an existing one is moved at first launch (D-034).
- iPhone received files go to the Documents folder itself instead of `Documents/CrossDrop`. Files from earlier phases stay where they were.
- Android `MainActivity` is `singleTask`, so a share reaches the running app.
- The app is named "CrossDrop" on the home screen and in Files.
- The receive server stores partial and saved files through `ReceivedFileStore`.

### Added (Phase 4)
- Device identity ([features/device-identity.md](features/device-identity.md)):
  - An ECDSA P-256 key and self-signed certificate are made on first launch. The certificate's SHA-256 is the device identity.
  - The key is in the iOS Keychain (this device only) or Android Keystore-protected storage. A reinstall or a lost key gives a new identity.
  - Settings shows the first 16 characters ("Security key").
- Pairing and trust ([features/pairing-and-trust.md](features/pairing-and-trust.md)):
  - Every connection uses TLS 1.3, pinned to the receiver's fingerprint (from the QR, the trusted record, or the first contact checked against the TXT hint).
  - The sender proves its key with a signed challenge (`/v1/auth/challenge`, `/v1/auth`) and gets a token. Sessions belong to that fingerprint.
  - A 6-digit pairing code from both fingerprints and committed nonces, shown on both phones for untrusted senders.
  - "Trust this device" in the Accept prompt and after a send. Trusted devices in Settings, with auto-accept per device and forget.
  - A clear warning when a trusted name or id comes with another key.
- Abuse limits ([features/abuse-limits.md](features/abuse-limits.md)):
  - A Receiving switch (Receive screen and Settings).
  - Rate limits per IP for offers and auth (429).
  - Header (431) and body (413) limits.
  - Capped auth tables, and a 30 s idle timeout.
- Database schema 3: `trusted_devices`, `settings`, `sessions.peerFingerprint`. The v2 → v3 migration is tested.
- Dev CLI: prints the pairing code; `fake-qr` writes a QR with a wrong fingerprint for the tampered-QR check.
- Tests without phones:
  - Fingerprint and code derivation (same on both sides, different per peer, known answer).
  - Pinning failure, including a chain-substitution attack.
  - Forged, relayed and replayed authentication.
  - Session isolation between senders, and an unknown fingerprint trying to send.
  - The Receiving switch, auto-accept, rate and size limits.
  - Reinstall and lost-key identity changes.
- Docs: Security model rewritten in ARCHITECTURE.md (with what dart:io can and cannot do), decisions D-027 to D-033, Phase 4 device checks.
- Packages: `flutter_secure_storage` (key storage, D-030); `qr` as a dev dependency for the CLI.

### Changed (Phase 4)
- "One unfinished session per sender" now uses the proven fingerprint, not the claimed id.
- `POST /v1/sessions` replies with `trusted`. Offers refused because receiving is off end as "rejected" on the sender.
- Unfinished transfers stored before Phase 4 cannot be resumed (they have no fingerprint to pin): received ones are marked failed, and sent ones ask to send again.
- Android app backup and device-to-device transfer are off.

### Removed (Phase 4)
- The Phase 1 client that accepted any server certificate (D-011), and the per-launch certificate.

### Fixed
- The dev CLI compiles again under plain `dart`: the core database no longer imports Flutter.

## 2026-11-02

### Added (Phase 3)
- Transfer engine (see `docs/features/transfer-engine.md`):
  - **Full v1 session flow:** `GET /v1/info` with version negotiation, `POST /v1/sessions` with a manifest (`kind`, `created`, `livePhotoGroup`), a new `GET /v1/sessions/{id}`, the events WebSocket (`accepted`, `rejected`, `progress`, `file_done`, `cancelled`, `error`, replayed to late sockets), and `DELETE` to cancel from either side.
  - **Accept prompt** on the receiver, with a 60 s timeout.
  - **Session state machine** (`offered → accepted → transferring ⇄ paused → verifying → done`, or `rejected`, `cancelled`, `failed`), stored with every file in the database (schema version 2).
  - **Send queue:** several files one after another over one connection, with per-file and total progress, moving-average speed and time left on both sides.
  - **Safety:**
    - Free space is checked before the prompt and again at Accept.
    - More bytes than declared fails that file.
    - One unfinished session per sender, and at most 8 open sessions.
    - Offer size limits.
    - Hash mismatch restarts a file once, then fails it.
- Resume (see `docs/features/resume.md`):
  - Retry with backoff 1, 2, 4, 8 s, then 8 s, for about 2 minutes without progress.
  - The receiver checkpoints every 4 MB (fsync, then the database) and cuts a part file back to its checkpoint after a crash.
  - The sender finds the receiver again by device id when its address changes.
  - An "Unfinished transfers" prompt at launch, and cleanup of partial files older than 24 hours.
- Keep-alive (see `docs/features/keep-alive.md`):
  - The screen stays on during transfers.
  - Android: a `dataSync` foreground service with a progress notification, and the `POST_NOTIFICATIONS` request.
  - iOS: a background task in which transfers save progress and pause; they resume on return.
- Platform channels `crossdrop/storage` (free space) and `crossdrop/background` (iOS background task).
- Tests without phones:
  - An in-process flaky TCP proxy (drops, latency, silent links, refused connections).
  - Resume at random drop points, receiver restart on a new port, give-up then resume from the database.
  - 150 small files, hostile names, wrong sizes, hash mismatch, cancel in every state, keep-alive logic.
  - A 2 GB test with a memory check, tagged `large`.
- Docs: decisions D-018 to D-026, Phase 3 device checks, a session state diagram and protocol details in ARCHITECTURE.md.
- Packages: `shelf_web_socket` and `flutter_foreground_task`.

### Changed (Phase 3)
- `POST /v1/sessions` now returns `offered`, and bytes are refused until the user accepts.
- Partial files moved from the OS temp folder to the app support folder (D-025).
- The sender hashes the source in a parallel isolate. The receiver keeps its hash across drops (D-021), so resuming a large file never re-reads what was sent.
- Send picks several files. The send controller lives for the whole app, so leaving the Send screen does not stop a transfer.

### Fixed (Phase 3)
- Aborting a hash isolate mid-read no longer leaves its file open.
- A socket closing between two chunks, or a failed TLS handshake on reconnect, is now a retryable network error instead of an unhandled one.

### Added (Phase 2)
- Phase 2 discovery and QR connect (see `docs/features/discovery.md` and `docs/features/qr-connect.md`):
  - **Device identity:** a persistent UUID and an editable device name (Settings), stored in a drift database.
  - **Discovery:** Bonjour/mDNS advertising of `_crossdrop._tcp` while Receive is open, with TXT `v`, `id`, `n`, `p`, `fp`. Browsing with add, update and remove events keyed by device id (bonsoir).
  - **Nearby screen:** found devices with name and platform icon, pull to refresh. Tapping one checks it with `GET /v1/info` and opens Send pre-filled. Devices that do not answer are removed.
  - **QR code on Receive** (`crossdrop://connect?...`) and a QR scanner on Nearby, with strict parsing of hostile codes. Manual IP and port entry as the last fallback.
  - **iOS:**
    - `NSBonjourServices`, plus a camera usage text.
    - A Local Network probe: after 5 s with nobody found it detects "denied" and shows an explanation with a link to Settings.
  - **Android:** multicast, Wi-Fi state, network state and camera permissions. The Wi-Fi multicast lock is held only while browsing or advertising.
  - **Network changes:** advertising and browsing restart on a Wi-Fi or IP change and on app resume, and the QR code is redrawn.
  - `GET /v1/info` on the receive server. Offers now carry the real device id and name.
  - Unit tests for TXT parsing, QR parsing (malformed and hostile input), the peer list state machine, the network monitor, the peer check and the Nearby controller.
- Docs: decisions D-012 to D-016, Phase 2 device checks, architecture updates for discovery and QR.

- CI: GitHub Actions workflow `Build`. Analyze, format check and tests run on every push. When started manually it also builds an Android APK and an unsigned iPhone `.ipa` for sideloading (D-017). Install steps are in `docs/DEVICE_TESTS.md`.

### Changed
- Send on Home now opens the Nearby screen. The Send screen keeps editable IP and port fields.

### Added (Phase 1)
- Phase 1 proof of concept for file transfer (see `docs/features/file-transfer-poc.md`):
  - HTTPS receive server (shelf) with a per-launch self-signed certificate: `POST /v1/sessions`, resumable `PUT .../files/{fileId}?offset=N` into a `.part` file, `GET` for `receivedBytes`, `POST .../complete` with SHA-256 verification and move to a sanitized name.
  - Streaming upload client with progress, 3-second moving-average speed, Stop/Resume and a 15 s stall watchdog. Accepts any server certificate until Phase 4 (D-011).
  - SHA-256 in a background isolate, file-name sanitizer, chunked 1 MB reader.
  - Minimal Home, Receive and Send screens.
  - Unit tests that run without phones, including a 50 MB loopback transfer, a flat-memory check and kill-and-resume.
  - Android `INTERNET` permission in the main manifest; iOS local network usage description and Files app access to Documents.
- Docs: feature template and PoC feature doc in `docs/features/`, Phase 1 device checks, benchmark table, decisions D-006 to D-011.
- Project start: Flutter app skeleton, `CLAUDE.md` project instructions.
- Documentation set in `docs/`: architecture with Mermaid diagrams, decision log, changelog, device test and benchmark logs, docs index.
- No app code yet. v1 scope is iPhone ↔ Android file transfer over local Wi-Fi or hotspot, with no cloud server.
