# Changelog

All notable changes to CrossDrop and its docs. Newest first. Loosely follows [Keep a Changelog](https://keepachangelog.com): group entries under Added, Changed, Fixed or Removed, under a heading of the date (`## YYYY-MM-DD`) or version once releases exist.

## 2026-11-02

### Added
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
