# Feature: Resume

- Phase: 3
- Status: Built, awaiting device tests
- Last updated: 2026-11-02

## Summary

A transfer survives Wi-Fi drops, the receiver's IP or port changing, and either app being killed. The receiver keeps every byte that safely reached its disk, and the sender continues from there. Nothing that already arrived is sent again, and the result is checked with SHA-256.

## Scope

**In scope**

- Automatic resume after a drop, with backoff (1, 2, 4, 8 s, then every 8 s, giving up after about 2 minutes without progress).
- Stall detection: no progress for 15 s counts as a drop, even when the link dies silently.
- Finding the receiver again by device id after its IP or port changed.
- Resume after an app restart on either side: the "Unfinished transfers" prompt at launch.
- Deleting partial files after 24 hours.

**Out of scope** (and which phase picks it up)

- Resume when an iPhone sender's photo export is gone after a restart: Phase 5 (photo library). Such files fail as "source no longer readable".
- Resume across a reinstall: the database and partial files are gone.

## Design

ARCHITECTURE.md transfer rules 2 and 3 and the "Failure handling" table describe the flow. The details:

**What the receiver saves (checkpoint).** Bytes go to `<app support>/crossdrop_incoming/<sessionId>/<fileId>.part`. Every 4 MB, and whenever an upload stops (drop, stall, pause, background), the file is fsynced and only then is `receivedBytes` written to the database. After a crash, the part file is cut back to the last checkpoint. Bytes written after it might not have reached the disk, and trusting them could corrupt the file silently (D-022). Partial files live in the app support folder, not the OS temp or cache folder, because those can be purged while the app is closed (D-025).

**What the sender does after a drop.**

1. `GET .../files/{fileId}` to get `receivedBytes` = N.
2. `PUT ...?offset=N` with the rest.
3. A failed attempt waits according to `Backoff` (D-019). Progress, meaning the receiver confirmed more bytes than before, resets the delay and the 2-minute deadline. Time spent in the iOS background does not count.
4. After the third failed attempt in a row, it looks up the receiver's current address by device id over mDNS (`locatePeer`). This is how a sender follows a receiver whose app restarted on a new random port.
5. After 2 minutes without progress it stops with "Lost the connection… tap Resume". The session stays `paused` in the database, so the next launch offers it too.

**Hashing without re-reading (D-021).** Resuming a 2 GB file must not mean hashing 1.5 GB again before the next byte moves. With pure-Dart SHA-256 on a phone that could take longer than the 15 s stall timeout, and the transfer would never finish.

- **Sender:** hashes each source file in its own background isolate, in parallel with sending and independent of drops. The digest is ready by the time the last byte goes out.
- **Receiver:** keeps the incremental hash of each file alive in memory across drops. It always matches the bytes on disk, because a buffer that fails to write invalidates it. After an app restart there is no hash in memory, so `complete` hashes the file from disk. The sender allows 2 minutes plus 1 s per 20 MB for that.

**App restart.**

- **Receiver:** at launch, partial files older than 24 hours are deleted and those sessions marked `failed` (`expired`). Open Receive and the restored sessions are `paused`; they continue when the sender reconnects. Offers still waiting for Accept at the time of the crash become `rejected` (`timeout`).
- **Sender:** stored sessions keep the source paths. Resume checks that every source still exists with the same size, finds the receiver by device id, and continues.

## Code

| Path | Purpose |
| --- | --- |
| `lib/core/engine/backoff.dart` | Retry delays and the 2-minute deadline |
| `lib/core/engine/send_session.dart` | Retry loop, relocation, `SendSession.resume` |
| `lib/core/engine/sha256_isolate.dart` | `BackgroundFileHash`; workers that stop between chunks and close their file |
| `lib/core/server/receive_server.dart` | Checkpoints, restore and truncate, live hashers |
| `lib/core/discovery/peer_locator.dart` | Find a device by id |
| `lib/core/storage/partial_cleanup.dart` | 24-hour cleanup |
| `lib/features/transfer/unfinished_transfers.dart` | Launch prompt: Resume or Discard |

## Protocol and API

No new endpoints beyond [transfer-engine.md](transfer-engine.md). Resume uses `GET .../files/{fileId}` and `PUT ...?offset=N` as in Phase 1, plus `GET /v1/sessions/{id}` to learn whether the session is still open.

## Tests

**Unit tests (no phones)**

- `test/core/engine/send_session_test.dart`, through `test/support/flaky_proxy.dart` (an in-process TCP proxy with random drops, latency, silent links and refused connections):
  - drops at random points, three seeds, each dropping 3 or more times during 40 MB;
  - a silent link (Wi-Fi gone, no reset) detected by the stall timeout;
  - giving up after the deadline, then resuming from the database in a new `SendSession`;
  - following the receiver to a new port after its app restarted.
- `test/core/server/receive_server_test.dart`: dropped upload keeps its bytes; checkpoints while bytes flow; restart cuts back to the checkpoint and the sender can finish; waiting offers rejected at restart; `checkpointAll`.
- `test/core/engine/backoff_test.dart`, `test/core/storage/transfer_repository_test.dart` (24-hour cleanup), `test/core/discovery/peer_locator_test.dart`.
- `test/core/large_transfer_test.dart` (tag `large`, skipped by default): 2 GB with a drop at 1.2 GB, checking hashes and memory. Last run on Windows loopback: 83 s, RSS growth 52 MB. Run it with `flutter test --run-skipped --tags large`.

**Device checks**

[DEVICE_TESTS.md](../DEVICE_TESTS.md), section "Phase 3": P3-3, P3-4, P3-5.

## Known limits and risks

- The receiver must have Receive open for a sender to find it again (D-016). If it does not, the sender keeps trying for 2 minutes, then offers Resume.
- After an app restart, a large receiver file costs one full hash from disk at `complete`. That was not measured on phones.
- One fsync every 4 MB may cost throughput on some Android storage. Measure it in the benchmarks; the interval is a constructor parameter.

## Open questions

- None.
