# Feature: Abuse limits and server hygiene

- Phase: 4
- Status: Built, awaiting device tests
- Last updated: 2026-11-03

## Summary

While Receive is open, anyone on the same Wi-Fi can reach the phone's server. These limits keep a stranger from flooding it, filling its memory or spamming the Accept prompt. There is a global "Receiving" switch, rate limits per address, size limits on headers and bodies, and a server that runs only when needed, on a new random port each time.

## Scope

**In scope**

- "Receiving" switch on the Receive screen and in Settings (on by default).
- Rate limits per IP for offers and authentication.
- Header and body size limits; caps on every in-memory table the server keeps.
- Server lifetime: only while Receive is open and receiving is on; a new random port each start; TLS 1.3 minimum; 30 s idle timeout.

**Out of scope** (and which phase picks it up)

- Blocking a device by fingerprint: later, if device tests show a need.
- Showing refused attempts in a history list: Phase 6 (history).

## Design

ARCHITECTURE.md, "Abuse limits and server hygiene"; D-031, D-032.

- **Switch** (`settings.receivingEnabled`, watched by `ReceiveController`):
  - Off at start: the server does not start, nothing is advertised, and the screen says "Receiving is off".
  - Turned off while running: advertising stops and the QR code is hidden at once. The server answers untrusted offers with 403 `receiving_off`, and the receiver gets a notice. When no session is offered or running, the server closes.
  - Turned on: the server starts again on a new random port.
- **Rate limits** (`RateLimiter`, a token bucket per remote IP):
  - `POST /v1/sessions`: 3 at once, then 1 every 20 s.
  - `POST /v1/auth/challenge` and `/v1/auth`: 10 at once, then 1 every 3 s.
  - Over the limit: 429 `rate_limited`, `retryAfter` and `Retry-After`.
  - At most 1,024 addresses are tracked; the least recently seen is forgotten first.
- **Request limits:**
  - Headers over 16 KB: 431 `headers_too_large`. `dart:io` itself only stops at 1 MB and cannot be configured.
  - Bodies: 16 KB for auth and `complete`, 4 MB for offers (413 `body_too_large`). The declared length is checked first, then the bytes as they arrive.
- **Memory caps:** 64 open challenges (60 s each), 256 tokens (1 hour idle), oldest dropped first.
- **Sessions are freed** (review M1): an ended session is forgotten 5 minutes after it ended, or at once beyond 32 ended sessions (`ReceiveServer.prune`, every 30 s and at each offer). An offer that was never accepted is deleted from the database at that point, so a stranger cannot grow the database or History with offers. A paused session with no activity for 24 hours fails as `expired`. `ReceiveController` drops a never-accepted offer from its state as soon as it ends.
- **One hash isolate per session** (review M2): starting an upload stops the running hash of every other file in the session; such a file is hashed from disk at `complete`.
- **Offer slots are reserved before the first await** (review L3), so parallel offers from one sender get one session and 409 for the rest, and the 8-session cap counts offers still being stored. Their declared bytes count in the free-space check of the others.
- **Unchanged from Phase 3:**
  - One unfinished session per sender, now by proven fingerprint.
  - 8 open sessions.
  - Free-space checks.
  - More bytes than declared fails the file.
- **Order of checks for an offer:** token (401), rate limit (429), body size (413), JSON and version (400), trust and switch (403), sender busy (409), open sessions (503), free space (507). So an unauthenticated flood never parses JSON, and a refused offer never reaches the prompt.

## Code

| Path | Purpose |
| --- | --- |
| `lib/core/server/rate_limiter.dart` | `RateLimiter` |
| `lib/core/server/receive_server.dart` | `ServerLimits`, header middleware, body limits, 403 `receiving_off`, idle timeout |
| `lib/core/storage/settings_repository.dart` | The switch, stored |
| `lib/features/receive/receive_controller.dart` | Starts and stops the server with the switch |
| `lib/features/receive/receive_screen.dart`, `lib/features/settings/settings_screen.dart` | The switch in the UI |

## Protocol and API

New error codes: 403 `receiving_off`, 413 `body_too_large`, 429 `rate_limited` (with `retryAfter`), 431 `headers_too_large`. The sender shows "The other phone is not receiving from new devices" and "Too many attempts. Wait a minute".

## Tests

**Unit tests (no phones)**

- `sender_auth_test.dart` (RateLimiter group): burst then refill, separate buckets per address, no refill beyond the burst, bounded address table.
- `server_security_test.dart`:
  - The 4th offer from one address within a minute gets 429, even from different keys.
  - Auth is rate-limited.
  - 20 KB of headers gets 431.
  - An oversized auth body gets 413.
  - Receiving off: untrusted 403 with a notice, trusted 200.
- `send_session_test.dart`: with receiving off, the sender ends `rejected` / `receiving_off` and nothing is stored on the receiver.
- `trust_repository_test.dart`: the switch is on by default and can be stored.

**Device checks**

Listed in [DEVICE_TESTS.md](../DEVICE_TESTS.md), section "Phase 4": P4-3 (third phone), P4-7 (switch).

## Known limits and risks

- Phones behind the same address (a hotspot with NAT, a guest network) share a bucket. That is fine at home, but could slow down a second honest sender.
- A paused session keeps the server up after the switch goes off, until the Receive screen closes.
- The limits are first guesses; tune them after device tests.

## Open questions

- None.
