# Changelog

All notable changes to CrossDrop and its docs. Newest first. Loosely follows [Keep a Changelog](https://keepachangelog.com): group entries under Added, Changed, Fixed or Removed, under a heading of the date (`## YYYY-MM-DD`) or version once releases exist.

## 2026-11-02

### Added
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
