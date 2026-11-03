# Changelog

All notable changes to CrossDrop and its docs. Newest first. Loosely follows [Keep a Changelog](https://keepachangelog.com): group entries under Added, Changed, Fixed or Removed, under a heading of the date (`## YYYY-MM-DD`) or version once releases exist.

## 2026-11-03

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
