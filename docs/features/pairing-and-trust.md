# Feature: Pairing and trust

- Phase: 4
- Status: Built, awaiting device tests
- Last updated: 2026-11-03

## Summary

Before any file moves, the sender pins the receiver's certificate and the receiver checks the sender's key. A QR code pins the receiver's full fingerprint. A device picked from the nearby list, or a typed address, is checked by a 6-digit code that both phones show. After a successful pairing either side can trust the other. A trusted sender skips the code but still needs Accept unless the receiver turned on auto-accept for it. A trusted name with a different key gets a clear warning.

## Scope

**In scope**

- Pinned TLS 1.3 on every connection; the Phase 1 "accept any certificate" client is gone.
- Sender authentication with a signed challenge (dart:io cannot do mutual TLS with unknown certificates, D-027).
- The QR fingerprint must match the TLS certificate.
- Pairing code for untrusted senders, shown on both phones.
- Trusted devices table, "Trust this device", auto-accept per device, lookalike warnings, a list in Settings with forget.
- Sessions belong to the sender fingerprint that offered them.

**Out of scope** (and which phase picks it up)

- Final design of the Accept prompt and transfer screens: Phase 6.
- Trusting a device without a transfer (pairing only): not planned for v1.
- Syncing trust between a user's own devices: out of scope (no accounts).

## Design

ARCHITECTURE.md, "Security model": connection security, where the fingerprint comes from, pairing code, trust. Decisions D-027, D-029, D-033. Flow of one send:

1. **Find the fingerprint** (`checkPeer`): from the QR, or from a handshake that sends no request (`probeFingerprint`), which must match the TXT hint for nearby devices. A wrong QR fingerprint stops here with `pin_mismatch`.
2. **`GET /v1/info`** over the pinned client; the device id must match if known.
3. **Trust lookup** by fingerprint. A trusted name or id with another fingerprint is a lookalike, so Nearby asks "Not the X you trusted. Stop / Continue anyway".
4. **Authenticate** (`UploadClient._authenticate`): commit, challenge, sign, token. The client derives the pairing code.
5. **Offer.** The receiver looks up trust and builds the `IncomingOffer` with the fingerprint, the code of this authentication and the trust. The reply says `trusted`; if false, the sender shows the code while waiting.
6. **Accept prompt.** For an untrusted sender it shows the code, "If the codes differ, tap Decline", and a "Trust this device" checkbox. A lookalike gets a red warning. Trusted senders get the plain prompt. Auto-accept skips the prompt only for the exact trusted fingerprint.
7. After a completed send to an untrusted receiver, the Send screen offers "Trust <name>".

Every later request carries the token. Requests for a session owned by another fingerprint get 404, as if it did not exist. A 401 `auth_required` (expired token, receiver restarted) makes the client authenticate again once.

## Code

| Path | Purpose |
| --- | --- |
| `lib/core/security/pinning.dart` | `pinnedHttpClient`, `probeFingerprint`, `PinMismatchException` |
| `lib/core/security/peer_auth.dart` | Nonces, commitment, signing input, `derivePairingCode` |
| `lib/core/protocol/auth_messages.dart` | `/v1/auth/challenge` and `/v1/auth` messages |
| `lib/core/server/sender_auth.dart` | Receiver side: challenges, proof check, tokens |
| `lib/core/server/receive_server.dart` | Auth middleware, session ownership, trust in offers, auto-accept |
| `lib/core/client/upload_client.dart` | Pinned client, authentication, token reuse and refresh, `pairingCode` |
| `lib/core/client/peer_check.dart` | `checkPeer`: pin source, hint check, trust lookup |
| `lib/core/storage/trust_repository.dart` | `TrustedDevice`, `PeerTrust`, `TrustRepository` |
| `lib/features/receive/accept_dialog.dart` | Code, lookalike warning, "Trust this device" |
| `lib/features/nearby/lookalike_dialog.dart` | Warning before sending to a lookalike |
| `lib/features/send/send_screen.dart` | Code while waiting, "Trust" button, warnings |
| `lib/features/settings/settings_screen.dart` | Trusted devices, auto-accept, forget |

## Protocol and API

- `POST /v1/auth/challenge` `{"commit"}` → `{"nonce"}`. The commitment covers the pinned receiver fingerprint, the sender's own fingerprint and its nonce (`crossdrop-commit-v2`, D-061).
- `POST /v1/auth` `{"certificate", "nonce", "senderNonce", "signature"}` → `{"token", "expiresIn"}`; 401 `auth_failed`.
- `Authorization: Bearer <token>` on every `/v1/sessions…` request, including the WebSocket upgrade; 401 `auth_required` without it.
- `POST /v1/sessions` reply adds `trusted`.
- Client error code `pin_mismatch`; sender reason `pin_mismatch` (never retried).

## Tests

**Unit tests (no phones)**

- `peer_auth_test.dart`:
  - Code derivation is the same on both sides, and differs for another peer, swapped roles or fresh nonces.
  - Known answer (cross-checked in Python) and spread across the range.
  - The signing input binds every field; message shape checks.
  - The commitment binds the nonce and both fingerprints, with a known answer (D-061).
- `pinning_test.dart`: right pin connects. A wrong certificate fails in the handshake and the server sees no request. The chain-substitution attack is refused. A malformed pin is refused. The probe sends nothing.
- `sender_auth_test.dart`:
  - An honest proof gives a token.
  - A challenge is single-use, even after a failure.
  - A commitment mismatch, a certificate other than the committed one (the review H1 man-in-the-middle), a commitment or signature made for another receiver, our own certificate and garbage certificates are refused.
  - Challenges and tokens expire, and memory is capped.
- `server_security_test.dart`:
  - Sessions need a token. Another key's signature and a relayed proof are refused.
  - An **unknown fingerprint** can offer, but waits for the prompt with the same code as the client.
  - A re-auth after a server restart works.
  - Another device cannot see, feed, cancel or listen to someone else's session.
  - Trusted without auto-accept still asks; auto-accept only for that fingerprint; a lookalike is flagged.
  - A client pinned to another key never reaches the server.
- `peer_check_test.dart`: first contact, hint mismatch, QR match, tampered QR (`pin_mismatch`), trust and lookalike passthrough.
- `send_session_test.dart`: the same code on both sides; a receiver with another key stops the send with no retry.
- `trust_repository_test.dart`: trust by fingerprint only, lookalike by name or id, re-trust keeps auto-accept, touch, forget.

**Device checks**

Listed in [DEVICE_TESTS.md](../DEVICE_TESTS.md), section "Phase 4": P4-1 to P4-6.

## Known limits and risks

- The code is only as good as the user's comparison. The prompt says to decline if it differs; Phase 6 may make that harder to skip.
- A device that reinstalls shows up as a lookalike of its old self until the old record is forgotten.
- Offers from a trusted device are allowed while the server drains after Receiving is switched off (D-031).
- The bearer token is a secret inside the pinned TLS stream; it is never logged or stored.

## Open questions

- None. Choices that differ from the brief (signed challenge instead of client certificates, nonces in the code) are recorded in D-027 and D-029.
