# Changelog

All notable changes to CrossDrop and its docs. Newest first. Loosely follows [Keep a Changelog](https://keepachangelog.com): group entries under Added, Changed, Fixed or Removed, under a heading of the date (`## YYYY-MM-DD`) or version once releases exist.

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
