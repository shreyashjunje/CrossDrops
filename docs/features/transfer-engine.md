# Feature: Transfer engine

- Phase: 3
- Status: Built, awaiting device tests
- Last updated: 2026-11-02

## Summary

The transfer engine moves a set of files from one phone to the other: the sender offers a manifest, the receiver's user taps Accept, and the files go one after another over one HTTPS connection with live events on a WebSocket. Either side can cancel. Every file is checked with SHA-256 before it is saved. This replaces the Phase 1 proof of concept, which auto-accepted a single file.

## Scope

**In scope**

- The full v1 session flow: `GET /v1/info` with version negotiation, `POST /v1/sessions` with a manifest, the events WebSocket, `PUT` and `GET` per file, `complete`, `DELETE` to cancel.
- The receiver's session state machine, stored in the database.
- A send queue: several files, one after another, one connection.
- A simple Accept prompt on the receiver (60 s timeout).
- Safety checks: sanitized names, free space before accepting, no more bytes than declared, one unfinished session per sender, at most 8 open sessions.
- Per-file and total progress, speed (3 s moving average) and time left, on both sides.

**Out of scope** (and which phase picks it up)

- Pinned mutual TLS and proving the sender's identity: Phase 4. Until then the client accepts any certificate (D-011), so the sender id in an offer is only a claim.
- Saving into Photos or the gallery and reading photo-library assets: Phase 5. Files are saved to the app folder, as in Phase 1.
- The full transfer UI, history and the final Accept prompt design: Phase 6.
- Resume and keep-alive details: [resume.md](resume.md) and [keep-alive.md](keep-alive.md).

## Design

The protocol, state machine and transfer rules are in [ARCHITECTURE.md](../ARCHITECTURE.md), sections "Transfer session", "Protocol spec" and "Session state machine". What is specific to this implementation:

**Receiver (`ReceiveServer`)**

1. `POST /v1/sessions` checks, in order: the manifest's format and limits (10,000 files, 1,024-character names), the protocol version, whether this sender already has an unfinished session (409 `sender_busy`), whether 8 sessions are already open (503), and free space (507 `no_space`). Free space must cover the offer, the bytes still expected by other open sessions, and a 64 MB reserve, on both the temp and save volumes. Only then is the session stored as `offered` and the prompt shown.
2. The prompt has 60 s. No answer means `rejected` with reason `timeout`. When the user accepts, free space is checked again (the prompt may have been open a while), then the session moves to `accepted` and the `accepted` event goes out.
3. Bytes sent before Accept get 403 `not_accepted`. Bytes sent to a closed session get 410 `session_closed` with the status and reason.
4. The events WebSocket first replays where the session stands (`accepted`, then `file_done` or `progress` per file), so a sender that connects late or reconnects misses nothing. At most 4 sockets per session; the oldest is closed.
5. A file with more bytes than declared (by Content-Length or by counting) **fails that file**: its partial file is deleted and the other files continue. A sender that sends too much is broken or hostile, and resuming would not help.
6. When every file is saved or failed, the session is `done` (at least one saved) or `failed` (none saved), the sockets close and the session folder is deleted.

**Sender (`SendSession`)**

1. `GET /v1/info`: picks the highest common version (`negotiateVersion`) and checks the device id when known (nearby list, QR code). Every file is checked to still exist with the same size before offering.
2. `POST /v1/sessions`. The offer is never retried automatically: a lost reply could otherwise leave a duplicate offer.
3. Waits for the decision on the events socket and also polls `GET /v1/sessions/{id}` every 2 s, so a broken WebSocket never hides the answer. It gives up after 75 s, which is longer than the receiver's 60 s.
4. Files go in manifest order. For each file: `GET` the status, `PUT` from `receivedBytes`, then `complete` with the SHA-256. Retry and resume rules are in [resume.md](resume.md).
5. A hash mismatch with `retry: true` sends the file again from zero. The receiver allows that once; the second mismatch fails the file and the session moves on to the next one.

**Cancel.** The sender sends `DELETE` and stops at once. The receiver stops a running upload after its current chunk, deletes the partial files, and sends `cancelled` with `by: sender|receiver`. Cancelling twice, or after the end, does nothing.

## Code

| Path | Purpose |
| --- | --- |
| `lib/core/protocol/models.dart` | Manifest (`kind`, `created`, `livePhotoGroup`), status enums, `SessionStatusReply`, version negotiation, error codes, reject reasons |
| `lib/core/protocol/events.dart` | The six event messages |
| `lib/core/protocol/file_type.dart` | MIME type and kind from the file extension |
| `lib/core/engine/session_state_machine.dart` | Legal state transitions (pure Dart) |
| `lib/core/engine/send_session.dart` | Sender: offer, accept, queue, retry, pause, cancel, progress |
| `lib/core/engine/progress_tracker.dart` | Per-file and total progress, speed and time left |
| `lib/core/server/receive_server.dart` | Receiver: all routes, checks, persistence, events |
| `lib/core/client/upload_client.dart` | HTTP client: offer, status, put, complete, cancel, event socket |
| `lib/core/storage/transfer_repository.dart` | `sessions` and `session_files` rows |
| `lib/features/receive/accept_dialog.dart` | The simple Accept prompt |
| `lib/features/send/`, `lib/features/receive/` | Controllers and screens |

## Protocol and API

New or changed against Phase 1 (full table in ARCHITECTURE.md):

| Change | Detail |
| --- | --- |
| `POST /v1/sessions` | Returns `status: "offered"`, not `accepted`. Errors: 400 `unsupported_version` (with `versions`), 409 `sender_busy`, 503 `busy`, 507 `no_space` (with `neededBytes`) |
| `GET /v1/sessions/{id}` | **New.** `{sessionId, status, reason?, files: [FileStatus]}` |
| `DELETE /v1/sessions/{id}` | Cancel; returns the session status. Idempotent |
| `WS /v1/sessions/{id}/events` | JSON text frames with a `type` field; unknown types are ignored |
| `PUT .../files/{fileId}` | 403 before Accept, 410 when closed or the file failed, 413 `too_many_bytes`, 507 `no_space` or `io_error` on a write failure |
| `POST .../complete` | 422 `hash_mismatch` with `retry: true` (file restarted), 422 `file_failed` with `retry: false` |
| `FileStatus.status` | `pending`, `receiving`, `verifying`, `saved`, `failed` |

## Tests

**Unit tests (no phones)**

- `test/core/protocol/`: manifest fields and limits, events, version negotiation, status reply, file types.
- `test/core/engine/session_state_machine_test.dart`: every legal and illegal move, cancel from every state.
- `test/core/server/receive_server_test.dart`: offer and Accept, decline, timeout, no space (before and at Accept), sender busy, open-session limit, bad versions, full flow, resume, wrong offset, too many bytes (declared and counted), hostile names, empty file, hash mismatch once and twice, cancel from both sides in every state, the late-socket replay.
- `test/core/engine/send_session_test.dart`: several files, 150 small files over a handful of connections, hash mismatch, changed source, decline, no space, cancel while waiting, sending, retrying and paused, receiver cancel, progress and time left.
- `test/core/transfer_test.dart`: 50 MB end to end with a memory check.

**Device checks**

Listed in [DEVICE_TESTS.md](../DEVICE_TESTS.md), section "Phase 3".

## Known limits and risks

- The sender id in an offer is not proven until Phase 4, so "one session per sender" stops mistakes, not attackers. A stranger can still send offers; the Accept prompt is the defence.
- The Accept prompt only appears while the Receive screen is open (D-016).
- If a source file can no longer be read mid-session, the whole session is cancelled: protocol v1 cannot skip a file.
- Files are saved into the app folder, not Photos or the gallery (Phase 5).
- The receiver hashes with the pure-Dart `crypto` package (D-007). This was not measured on phones; check it during the benchmarks.

## Open questions

- None blocking. Offer rate limiting per IP (ARCHITECTURE.md threats table) is left for Phase 4, together with sender identity.
