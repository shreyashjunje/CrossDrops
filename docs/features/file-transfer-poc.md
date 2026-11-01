# Feature: File transfer proof of concept

- Phase: 1
- Status: Built, awaiting device tests
- Last updated: 2026-11-02

## Summary

The smallest end-to-end transfer: one phone runs the HTTPS receive server, the other types its IP and port, picks a file and streams it. The receiver writes a `.part` file, verifies SHA-256 and moves it to its final name. An interrupted transfer resumes from the receiver's byte count. The goal is to prove the core protocol on real iPhone ↔ Android pairs and to measure real speeds for [BENCHMARKS.md](../BENCHMARKS.md).

## Scope

**In scope**

- HTTPS server on the receiver, random port, per-launch self-signed certificate.
- `POST /v1/sessions` (minimal, auto-accepted), `PUT`, `GET` and `POST .../complete` for one file per session.
- Streamed upload client with progress, 3-second moving-average speed, stop and resume.
- Minimal Receive and Send screens.

**Out of scope** (and which phase picks it up)

- Discovery (Bonjour), QR codes, pairing and the 6-digit code.
- Accept prompt, WebSocket events, free-space check before accepting (next phase with the session flow).
- Mutual TLS, persistent device identity and certificate pinning (Phase 4).
- Saving into Photos/MediaStore, fd streaming from the photo library, foreground service, Android network binding (platform module phases).
- Multiple files per session, history, database.

## Design

Follows [ARCHITECTURE.md](../ARCHITECTURE.md) "Transfer session", "Protocol spec" and "Transfer rules", with these Phase 1 simplifications:

- **Session offer** is accepted immediately; the reply has `status: "accepted"` instead of `pending` plus a WebSocket `accepted` event.
- **TLS**: the receiver uses a throwaway ECDSA P-256 certificate created at launch (`EphemeralIdentity`). The client accepts any server certificate and sends none. This gives encryption but no protection against a man in the middle. Marked `TODO(phase4)`; see D-011.
- **Received byte count** is the length of the `.part` file on disk. No database yet, so sessions are lost if the receiving app restarts (the `.part` stays in temp).

Details worth knowing:

- **Streaming:** the client reads a 1 MB chunk, adds it to the request and waits for `flush()` before reading the next, so at most one chunk sits in the socket buffer. The server collects incoming chunks into 1 MB writes. Nothing holds the whole file.
- **Stalls:** a client watchdog aborts the upload after 15 s without progress (code `stalled`); Stop uses the same path. Both force-close the socket, because `HttpClientRequest.abort()` alone does not unblock a write to a peer that has gone. Control requests time out after 15 s (`complete` after 2 min).
- **Hashing:** both sides hash in a worker isolate (`Sha256Isolate`), with at most 4 chunks in flight, so slow hashing slows the transfer instead of using memory. On resume each side first re-hashes bytes `[0, N)` from its own disk inside the worker. No bytes are re-sent.
- **Declared size is enforced:** a `Content-Length` beyond the declared size is rejected before reading; a chunked body that overflows is stopped and this upload's bytes are discarded.
- **Interruption:** if the body stream errors or stalls for 15 s, the server flushes what arrived and releases the file. The client retries briefly on `busy` while that happens.
- **Hash mismatch:** the receiver empties the `.part` and returns 422; the sender can resend from zero. Automatic single retry (transfer rule 6) is not built yet.
- **File names:** `sanitizeFileName` strips directories, control and reserved characters, leading dots, trailing dots/spaces, renames reserved device names and limits to 200 UTF-8 bytes; `availablePath` adds ` (1)`, ` (2)` instead of overwriting, and refuses paths outside the save folder.
- **Save location:** iOS `Documents/CrossDrop` (visible in the Files app); Android the app's external files folder `Android/data/com.example.crossdrop/files/CrossDrop`.

## Code

| Path | Purpose |
| --- | --- |
| `lib/core/protocol/models.dart` | v1 JSON models, validation, error codes |
| `lib/core/server/receive_server.dart` | shelf HTTPS server, routes, `.part` handling, events |
| `lib/core/client/upload_client.dart` | Streaming upload client, progress, resume, cancel |
| `lib/core/engine/sha256_isolate.dart` | Incremental SHA-256 in a worker isolate |
| `lib/core/engine/chunked_reader.dart` | 1 MB streamed reads of a byte range |
| `lib/core/engine/speed_meter.dart` | 3-second moving-average speed |
| `lib/core/security/ephemeral_identity.dart` | Per-launch key and self-signed certificate |
| `lib/core/storage/file_name_sanitizer.dart` | Name sanitizing and non-colliding paths |
| `lib/app/app_dirs.dart` | Temp and save folders per platform |
| `lib/features/receive/`, `send/`, `home/`, `transfer/` | Minimal screens and Riverpod notifiers |

## Protocol and API

| Method | Path | Success | Errors |
| --- | --- | --- | --- |
| POST | `/v1/sessions` | 200 `{sessionId, status: "accepted"}` | 400 `bad_request` |
| PUT | `/v1/sessions/{sid}/files/{fid}?offset=N` | 200 `FileStatus` | 400 `bad_request`, 404, 409 `offset_mismatch` (+`receivedBytes`), 409 `busy`, 409 `already_saved`, 413 `too_many_bytes` |
| GET | `/v1/sessions/{sid}/files/{fid}` | 200 `{fileId, size, receivedBytes, status}` | 404 |
| POST | `/v1/sessions/{sid}/files/{fid}/complete` | 200 `FileStatus` with `status: "saved"` | 409 `incomplete` (+`receivedBytes`), 409 `busy`, 409 `already_saved`, 422 `hash_mismatch`, 500 `io_error` |

Errors are JSON: `{"error": "<code>", "message": "...", ...}`. `fileId` must match `[A-Za-z0-9_-]{1,64}`.

## Tests

**Unit tests (no phones)**: `flutter test`

- `test/core/protocol/models_test.dart`: JSON round trips and validation.
- `test/core/storage/file_name_sanitizer_test.dart`: traversal, control chars, reserved names, length, collisions.
- `test/core/engine/sha256_isolate_test.dart`: digest equals one-shot hashing, prefix-then-chunks (resume), abort.
- `test/core/engine/speed_meter_test.dart`: steady rate, 3 s window, reset.
- `test/core/server/receive_server_test.dart`: full flow, two-part resume, wrong offset, oversize bodies, hash mismatch, incomplete, malicious name, empty file, events.
- `test/core/client/upload_client_test.dart`: a receiver that stops reading makes the upload fail as `stalled`; a silent peer makes a status request time out.
- `test/core/transfer_test.dart`: 50 MB client → server over loopback HTTPS with hash check; peak RSS growth under 40 MB (measured 17–20 MB on the dev PC); kill halfway, new client resumes from `offset=N`, only missing bytes sent.

**Device checks**

Listed in [DEVICE_TESTS.md](../DEVICE_TESTS.md), section "Phase 1".

## Known limits and risks

- `file_picker` copies the picked file into the app's cache/tmp on both platforms, so sending 1 GB briefly needs another 1 GB free, and picking a large file takes a while before Send is enabled.
- No Android network binding: on a Wi-Fi without internet (hotspot), Android may route traffic over mobile data and the connection fails. Turn mobile data off for hotspot runs in this phase.
- iOS pauses the app when the screen locks. The screen is kept awake on Receive and while sending; switching apps still interrupts the transfer (use Resume).
- Receiving sessions live in memory: if the receiving app is closed, the transfer cannot be resumed (start over).
- The memory test checks process RSS on a desktop VM, not on phones.

## Open questions

- Is the per-file SHA-256 cost visible on older phones (hash speed vs. Wi-Fi speed)? Check CPU/heat during the 1 GB runs.
- Is 1 MB the right buffer size on phones? Benchmark 256 KB and 4 MB later as the architecture suggests.
