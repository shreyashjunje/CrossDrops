# CrossDrop Architecture: iPhone ↔ Android File Sharing

Nov 1, 2026 · updated Nov 3, 2026 (Phase 7) · @yash

CrossDrop v1 is a Flutter app in which each phone runs a small encrypted HTTPS server. The phones find each other over the local network (or connect through a hotspot) and send files straight to each other, with no cloud server. This document covers only iPhone ↔ Android, in both directions.

## Scope and assumptions

**In scope**

- iPhone → Android and Android → iPhone transfers of photos, videos and any other file.
- Both phones nearby with the CrossDrop app open in the foreground.
- Three connection modes: same Wi-Fi, an Android hotspot, or an iPhone Personal Hotspot.
- Original quality, end-to-end encryption, resume after interruption.

**Out of scope for v1**

- iPhone ↔ iPhone and Android ↔ Android. The protocol is symmetric, so these work later with little change, but they are not tested in v1.
- Phones on different networks or far apart (needs an internet relay).
- Receiving while the app is closed or in the background on iPhone (iOS does not allow it).
- Accounts, cloud storage, chat.

**Design principles**

1. **Receiver is the server.** The phone that receives runs an HTTPS server; the sender is the client. This works the same in every network mode.
2. **One shared core in Dart.** Protocol, transfer engine, security and UI are shared. Native Swift and Kotlin only where the OS requires it (photo library, hotspot, background, Bonjour).
3. **Never trust the network.** Every connection uses TLS 1.3 pinned to the receiver's certificate, the sender proves its own key, and the receiver always approves unknown senders.
4. **Every byte is resumable.** Files are written to a partial file and resumed from the last confirmed byte.
5. **Stream, never buffer.** No file is ever fully loaded into memory.
6. **Fail loudly and suggest the next mode.** If one connection mode fails, the app tells the user which mode to try next.

## System overview

```mermaid
flowchart TB
  subgraph Dart["Shared Dart core (same code on both phones)"]
    UI["UI: features<br/>home, nearby, send, receive, transfer, hotspot, history, settings"]
    State["State: Riverpod providers"]
    Engine["Transfer engine<br/>chunking, resume, hashing isolate, queue"]
    Net["HTTPS server and client<br/>protocol, versioning, retry and backoff"]
    Sec["Security<br/>identity, certificates, pinning, 6-digit code"]
    Disc["Discovery<br/>bonsoir wrapper, TXT parsing"]
    Store["Storage<br/>database, temp files, cleanup"]
    UI --> State --> Engine
    Engine --> Net
    Engine --> Store
    Net --> Sec
    UI --> Disc
  end
  Dart --> PC["Platform channels (paths and file descriptors only, never file bytes)"]
  PC --> IOS["iOS module (Swift)<br/>PhotoKit export and save, hotspot join, background task, Bonjour, Share Extension"]
  PC --> AND["Android module (Kotlin)<br/>MediaStore save, fd streaming, LocalOnlyHotspot, foreground service, NSD, multicast lock, network binding, share intents"]
```

> Diagram drafted from the prose and the Platform modules and Code structure sections. Please review.

Everything above the platform channels is shared Dart code that runs the same on both phones. The two native modules only handle what the OS requires: photo library, hotspot, background behavior, Bonjour/NSD and sharing from other apps.

## Connectivity scenarios

Three scenarios are supported in v1: shared Wi-Fi, an Android hotspot, and an iPhone hotspot. Everything else is detected and gets a clear message.

| # | Situation | v1 support | How CrossDrop handles it |
| --- | --- | --- | --- |
| 1 | Both on the same home or office Wi-Fi | Yes (primary) | Bonjour/mDNS discovery, direct HTTPS over the router |
| 2 | Same Wi-Fi, but mDNS is blocked or filtered (some mesh routers, office networks) | Yes | Discovery fails, so the receiver shows a QR code with its IP, port and certificate fingerprint; the sender scans it |
| 3 | Guest or public Wi-Fi with client isolation (cafe, hotel, airport) | No direct path | When the nearby search found nobody and a QR code or typed address did not answer, Nearby shows a card explaining guest and public Wi-Fi, with Use hotspot mode |
| 4 | No Wi-Fi; Android creates a hotspot, iPhone joins | Yes (recommended offline mode) | Android starts a LocalOnlyHotspot and shows one QR with Wi-Fi name, password and connection info, plus a standard Wi-Fi QR for the iPhone Camera. The iPhone joins in-app via NEHotspotConfiguration when the build has the Hotspot Configuration capability (paid Apple account); otherwise it guides the user through Settings > Wi-Fi and goes on once the Android answers (D-054, D-055) |
| 5 | No Wi-Fi; iPhone Personal Hotspot, Android joins | Yes (manual) | User turns on Personal Hotspot in iOS Settings (apps can't); Android joins in its Settings; a three-step guide shows whether the hotspot is on, the Android has joined and the other phone is on the same subnet; then discovery or QR as usual (D-057) |
| 6 | Same Wi-Fi but one phone has a VPN on | Sometimes | Some VPNs route or block local traffic; if connect fails and a VPN is detected, ask the user to pause it |
| 7 | Android joined a Wi-Fi with no internet (hotspot) | Yes | Android keeps mobile data as the default; when Wi-Fi is connected, not validated and not the default, the app binds its process to the Wi-Fi network (D-056) |
| 8 | Router splits 2.4 GHz and 5 GHz, or mesh nodes | Usually yes | Same subnet works; separate VLANs act like scenario 3 |
| 9 | Phones on different networks or mobile data only | No (future) | Needs a relay (WebRTC + TURN); message: "Get on the same Wi-Fi or use hotspot mode" |
| 10 | No Wi-Fi and no hotspot possible, direct radio link | No (future) | Wi-Fi Aware on iOS 26+ newer iPhones and supporting Androids; research later |

**Which mode is fastest?** Usually the hotspot modes. On a router, data goes phone → router → phone, sharing airtime twice. In hotspot mode one phone is the access point, so the data crosses the air once. Measure this on your devices before stating it in the app: benchmark builds do that (Performance design, [features/benchmark-mode.md](features/benchmark-mode.md)).

Hotspot details: [features/android-hotspot.md](features/android-hotspot.md), [features/iphone-join-hotspot.md](features/iphone-join-hotspot.md), [features/iphone-personal-hotspot-guide.md](features/iphone-personal-hotspot-guide.md), [features/android-network-binding.md](features/android-network-binding.md).

## Connection flow

```mermaid
flowchart TD
  Start([User opens CrossDrop]) --> Wifi["Mode 1: same Wi-Fi<br/>Bonjour/mDNS discovery"]
  Wifi --> D1{"Device found<br/>within about 5 s?"}
  D1 -- Yes --> Code["Tap device in nearby list<br/>6-digit code check if untrusted"]
  D1 -- No --> QR["Mode 2: QR code<br/>receiver shows IP, port, fingerprint; sender scans"]
  QR --> D2{"Connect succeeds<br/>within 5-10 s?"}
  D2 -- Yes --> TLS
  D2 -- No --> Hot["Mode 3: hotspot<br/>Android LocalOnlyHotspot with Wi-Fi QR,<br/>or iPhone Personal Hotspot enabled manually"]
  Hot --> TLS
  Code --> TLS["Pinned TLS 1.3 session<br/>sender proves its key"]
  TLS --> Engine([Transfer session])
```

> Diagram drafted from the Connectivity scenarios and Failure handling sections. Please review.

The app tries the easiest mode first and moves to the next only when one fails. Every path ends in the same pinned, authenticated TLS session, so the transfer engine never cares how the phones are connected.

## Transfer session

```mermaid
sequenceDiagram
  participant S as Sender (client)
  participant R as Receiver (server)
  S->>R: GET /v1/info
  R-->>S: id, name, platform, versions
  S->>R: POST /v1/sessions (manifest)
  Note over R: Version, sender limit, free-space check
  R-->>S: sessionId, status offered
  S->>R: WS /v1/sessions/{id}/events
  Note over R: User taps Accept (60 s), space checked again
  R-->>S: event accepted (or rejected)
  S->>R: PUT /files/{fileId}?offset=0 (streamed body)
  R-->>S: event progress
  Note over S,R: Connection interrupted
  S->>R: GET /files/{fileId}
  R-->>S: receivedBytes = N
  S->>R: PUT /files/{fileId}?offset=N
  S->>R: POST /files/{fileId}/complete (SHA-256)
  Note over R: Verify hash, save, remove .part
  R-->>S: event file_done
```

> Diagram drafted from the Protocol spec and Transfer rules sections. Please review.

Solid arrows are sender requests; dashed arrows are receiver replies and events. After an interruption, the sender asks how much arrived and continues from that byte, so nothing is sent twice.

## Protocol spec (v1)

The protocol is plain HTTPS with JSON for control and streamed request bodies for file data, plus one WebSocket per session for live events. All endpoints are on the receiver.

**Discovery advertisement (Bonjour/mDNS)**

- Service type: `_crossdrop._tcp`, port = the receiver's random listening port.
- Instance name: `CrossDrop-<first 8 characters of the device UUID>`. It carries no personal data and rarely clashes; the device name is only in TXT `n`.
- TXT record: `v=1` (protocol version), `id=<device UUID>`, `n=<device name, at most 63 UTF-8 bytes>`, `p=ios|android`, `fp=<first 16 hex chars of certificate SHA-256>`. Keys are case-insensitive. A record with a newer `v` needs only `v`, `id` and `n` and is listed as "needs update".
- The TXT fingerprint is a hint only. The full fingerprint is checked in the TLS handshake.
- Browsers ignore records with a bad TXT, their own id, or no IPv4 address in a local range (10/8, 172.16/12, 192.168/16, 169.254/16, 100.64/10), so an advertisement can never point the app outside the local network.
- A phone advertises while CrossDrop is open and Receiving is on, on any screen (D-046; until Phase 5 only on the Receive screen, D-016). It stops 30 s after the app is hidden with nothing in flight. It re-advertises when the Wi-Fi or IP changes, when the app returns to the foreground and when the device is renamed.

**QR code payload**

`crossdrop://connect?v=1&ip=192.168.1.23&port=53317&fp=<full SHA-256 fingerprint>&id=<device UUID>&n=<name>`

In offline hotspot mode the Android QR also carries the Wi-Fi network, so one scan joins the network and connects:

`...&ws=<Wi-Fi name>&wp=<password>&wsec=wpa2|wpa3t|wpa3`

`ws` and `wp` come together or not at all; `wsec` defaults to `wpa2`.

Parsing is strict. Every listed parameter must appear exactly once, and unknown parameters are ignored, so later versions can add fields. Each field is checked:

- `ip`: a dotted IPv4 literal in one of the local ranges above. Hostnames are never resolved.
- `port`: 1–65535.
- `fp`: 64 hex characters.
- `id`: a UUID.
- `n`: sanitized.
- `ws`: 1–32 bytes of UTF-8 without control characters; `wp`: 8–63 printable ASCII characters; `wsec`: one of the three values.

Payloads over 1024 characters, or with control characters or stray `%` escapes, are refused. QR payloads are never logged. A typed IP and port follows the same address rules.

**Endpoints**

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/v1/info` | `{"id", "name", "platform", "versions": [1]}`. The sender calls it before every connect to check the protocol version and, from the list or a QR code, the device id. No token needed |
| POST | `/v1/auth/challenge` | `{"commit"}` → `{"nonce"}`. Step 1 of sender authentication (see Security model). 429 `rate_limited` |
| POST | `/v1/auth` | `{"certificate", "nonce", "senderNonce", "signature"}` (certificate and signature base64 DER) → `{"token", "expiresIn"}`. 401 `auth_failed`, 429 `rate_limited` |
| POST | `/v1/sessions` | Sender offers a session with a file manifest; returns `sessionId`, status `offered` (D-018) and `trusted` (the receiver trusts this sender, so it shows no code). Refusals: 400 `unsupported_version` (with `versions`), 403 `receiving_off`, 409 `sender_busy`, 413 `body_too_large`, 429 `rate_limited`, 503 `busy` (8 sessions open), 507 `no_space` (with `neededBytes`) |
| GET | `/v1/sessions/{id}` | `{"sessionId", "status", "reason"?, "files": [file status]}`, so a sender that reconnects knows where the session stands |
| WS | `/v1/sessions/{id}/events` | Live events: `accepted`, `rejected`, `progress`, `file_done`, `cancelled`, `error`. A new socket first gets the current state replayed |
| PUT | `/v1/sessions/{id}/files/{fileId}?offset=N` | Streams file bytes starting at byte N. 403 `not_accepted` before Accept, 409 `offset_mismatch` (with `receivedBytes`), 410 `session_closed` or `file_failed`, 413 `too_many_bytes`, 507 on a write failure |
| GET | `/v1/sessions/{id}/files/{fileId}` | `{"fileId", "size", "receivedBytes", "status"}`, status `pending`, `receiving`, `verifying`, `saved` or `failed`, so the sender knows where to resume |
| POST | `/v1/sessions/{id}/files/{fileId}/complete` | Sender sends the SHA-256; receiver verifies and saves. 422 `hash_mismatch` with `retry: true` (file restarted from zero) or `file_failed` with `retry: false` |
| DELETE | `/v1/sessions/{id}` | Cancel from the sender's side; idempotent. The receiver's own cancel reaches the sender as the `cancelled` event or a 410 |

Every `/v1/sessions…` request, including the WebSocket upgrade, needs `Authorization: Bearer <token>`; without a valid one: 401 `auth_required` (authenticate again and retry once). A session that belongs to another sender answers 404. Any request with more than 16 KB of headers gets 431 `headers_too_large`.

Errors are JSON: `{"error": code, "message": text, ...details}`.

**Events (WebSocket, receiver to sender)**

One JSON text frame per event, with a `type` field. Unknown types are ignored, so later versions can add some.

| Type | Fields | When |
| --- | --- | --- |
| `accepted` | none | The user tapped Accept |
| `rejected` | `reason` (`declined`, `timeout`, `no_space`), `neededBytes`? | The offer was refused |
| `progress` | `fileId`, `receivedBytes` | At each 4 MB checkpoint, so these bytes are on disk |
| `file_done` | `fileId` | The file was verified and saved |
| `cancelled` | `by` (`sender` or `receiver`) | Either side cancelled |
| `error` | `code`, `fileId`? | A file failed (`too_many_bytes`, `hash_mismatch`, `file_failed`), or the disk filled up (`no_space`) |

The events are a convenience. Every fact they carry is also in the HTTP replies, so a lost socket never stops a transfer.

**Limits on an offer:** at most 10,000 files, names at most 1,024 characters before sanitizing, one unfinished session per sender fingerprint, 8 open sessions in total (D-023), 3 offers at once per IP address then one every 20 s (D-032).

**Offer manifest (POST /v1/sessions)**

```json
{
  "protocol": 1,
  "sender": {"id": "uuid", "name": "Shreyash's iPhone", "platform": "ios"},
  "files": [
    {"fileId": "f1", "name": "IMG_4021.MOV", "size": 1288490188, "mime": "video/quicktime",
     "kind": "video", "created": "2026-10-30T18:22:00Z", "livePhotoGroup": null}
  ]
}
```

`sender.id` and `sender.name` are what the sender claims; the receiver uses them only as labels. The proven sender is the fingerprint behind the token.

The SHA-256 is not in the offer, so the sender can start sending before hashing finishes. It hashes in a background isolate alongside the upload and sends the hash in `complete`. `kind` is `photo`, `video` or `file`; an unknown kind from a newer peer reads as `file`. `created` and `livePhotoGroup` are optional.

**Transfer rules**

1. The receiver checks free space before accepting. The free space must cover the offer, the bytes other open sessions still expect, and a 64 MB reserve, on both the temp and the save volume. It checks again when the user taps Accept.
2. Data is written to a partial file through a `ReceivedFileStore`: on iPhone `<app support>/crossdrop_incoming/<sessionId>/<fileId>.part` (D-025), on Android straight into a pending MediaStore item, created at the first byte (D-040). Every 4 MB, and whenever an upload stops, the partial file is fsynced and then the received byte count is saved. After a crash it is cut back to that count (D-022).
3. On reconnect, the sender calls GET on the file, then PUT with `offset = receivedBytes`. Retries wait 1, 2, 4, 8 s, then 8 s, and stop after about 2 minutes without progress (D-019).
4. Files go one at a time on one connection in v1. Parallel streams (2–4) are added only if benchmarks show a gain.
5. Read and write buffers start at 1 MB; tune after benchmarks.
6. On `complete`, the receiver compares SHA-256 (computed incrementally while writing, kept across drops; hashed from disk after an app restart, D-021). On mismatch, the file restarts from zero once, then fails.
7. After verification the file is saved without a copy: Android publishes the pending item; iPhone moves the file into Photos or the Documents folder (see Platform modules). Where it goes is decided from the sanitized name's extension, never the declared MIME type.
8. More bytes than declared, by Content-Length or by count, fails that file and deletes its partial file. The other files continue.
9. A session ends `done` when every file is saved or failed and at least one was saved, and `failed` when none was.

**Versioning:** `GET /v1/info` lists the versions the receiver supports, and the sender picks the highest common one. If there is none, the app says "Update CrossDrop on the other phone". The offer carries the chosen version in `protocol`; the receiver refuses others with 400 `unsupported_version` and its own list.

## Session state machine

The receiver's state for one session (`SessionStatus`, `lib/core/engine/session_state_machine.dart`). The wire `status` is the state name.

```mermaid
stateDiagram-v2
  [*] --> offered: POST /v1/sessions
  offered --> accepted: user taps Accept
  offered --> rejected: Decline, 60 s timeout, or no space at Accept
  accepted --> transferring: first PUT
  transferring --> paused: drop, stall, app backgrounded, disk full
  paused --> transferring: sender resumes (PUT)
  transferring --> verifying: POST complete
  paused --> verifying: POST complete
  verifying --> transferring: more files left, or hash mismatch restart
  verifying --> done: last file ended, at least one saved
  verifying --> failed: last file ended, none saved
  offered --> cancelled: DELETE or receiver cancels
  accepted --> cancelled
  transferring --> cancelled
  paused --> cancelled
  verifying --> cancelled
  paused --> failed: expired after 24 h
  done --> [*]
  rejected --> [*]
  cancelled --> [*]
  failed --> [*]
```

- After an app restart, a stored session in any non-final state comes back as `paused`, except `offered`, which becomes `rejected` (`timeout`).
- Every state can move to `failed` for an unrecoverable error. The diagram shows the common causes only.
- Each file has its own status: `pending → receiving → verifying → saved`, or `failed`.

The sender has its own view (`SendPhase`): `connecting → waitingForAccept → sending ⇄ retrying / paused → done`, or `rejected`, `cancelled`, `failed`. A `failed` caused by the network or a full disk on the receiver stays resumable.

## Security model

Each phone has its own key and certificate. The sender pins the receiver's certificate in TLS 1.3, the receiver checks the sender's key with a signed challenge, and a stranger can never push a file without the receiver tapping Accept. Feature details: [device-identity.md](features/device-identity.md), [pairing-and-trust.md](features/pairing-and-trust.md), [abuse-limits.md](features/abuse-limits.md).

**Device identity**

- On first launch the app creates a random device UUID and an ECDSA P-256 key pair with a self-signed certificate (`basic_utils`, D-028). The certificate holds no personal data (subject `CN=CrossDrop`).
- The private key lives in the iOS Keychain (this device only, readable after first unlock) or in Android Keystore-protected storage (`flutter_secure_storage`, D-030). The certificate is in the `identity` row. The key is in the app's memory while it runs, because Dart's TLS stack needs it as bytes.
- The certificate's SHA-256 fingerprint (lowercase hex of the DER) is the device's identity. The device name and UUID are labels and can be faked; no decision is ever based on them.
- A reinstall gives a new identity: the database is gone, so a key left in the iOS Keychain is replaced, and Android backup is off. A lost or broken key also gives a new identity. Either way, peers must pair again.

**Connection security**

What `dart:io` can and cannot do was tested on Dart 3.13 before building (D-027):

| Need | dart:io | What CrossDrop does |
| --- | --- | --- |
| Server presents a self-signed certificate | Yes | Each phone's own certificate, TLS 1.3 minimum (`minimumTlsProtocolVersion`) |
| Client pins the server certificate | Yes: the callback sees the leaf; a chain with the pinned certificate appended after an attacker's leaf is refused | `pinnedHttpClient` checks the leaf in the handshake and again before any request byte is sent |
| Server accepts an unknown self-signed **client** certificate | **No.** There is no server-side callback; an untrusted client certificate fails the handshake even in "request" mode | Application-layer sender authentication (below) |
| Configurable header size limit | No (fixed 1 MB) | Own 16 KB limit in a middleware (431) |

Sender authentication, inside the pinned TLS connection:

1. The sender picks a random 32-byte `senderNonce` and sends `commit = SHA-256("crossdrop-commit-v1\n" + senderNonce)` to `POST /v1/auth/challenge`. The receiver answers with a random `nonce` (single use, 60 s).
2. The sender sends its certificate, `senderNonce`, and an ECDSA P-256 / SHA-256 signature over `"crossdrop-auth-v1\n" + receiverFp + "\n" + senderFp + "\n" + nonce + "\n" + senderNonce` to `POST /v1/auth`.
3. The receiver checks the commitment, that the certificate holds a P-256 key, and the signature, using its **own** fingerprint as `receiverFp`. It returns a 32-byte bearer token (memory only; expires after 1 hour unused; lost when the server restarts).
4. Every `/v1/sessions` request carries `Authorization: Bearer <token>`. A session belongs to the fingerprint that offered it; for anyone else it does not exist (404).

Because the signature covers the receiver's fingerprint, a proof made for one receiver is useless at another, so a malicious receiver cannot relay it. The token only travels inside the pinned TLS connection. Nothing ever falls back to an unpinned connection once a fingerprint is known (hard rule 4).

**Where the receiver's fingerprint comes from**

| Path | Pin | Then |
| --- | --- | --- |
| QR code | The full fingerprint in the QR. A mismatch fails at once ("This isn't the device you scanned") | Strong: no code check needed for the sender |
| Trusted device | The fingerprint in the trusted record | A different key under a trusted name or id is a **lookalike**: clear warning, and the user may only go on as untrusted, with the code check |
| Nearby list or typed address (first contact) | Read from a handshake that sends no request (`probeFingerprint`); from the nearby list it must start with the TXT `fp` hint | The 6-digit code check covers it |

**Pairing code**

When the receiver does not trust the sender, both phones show the same 6-digit code, like Bluetooth numeric comparison, and the receiver confirms it matches before accepting.

```text
code = SHA-256("crossdrop-code-v1\n" + senderFp + "\n" + receiverFp + "\n"
               + senderNonce + "\n" + receiverNonce)
       first 6 bytes as a big-endian integer, mod 1,000,000, zero-padded
```

The nonces are the ones from sender authentication. A code made from the two fingerprints alone could be forced by a man in the middle: it would generate keys until both of its connections showed the same code (about a million tries, minutes of work). Here the sender commits to its nonce before it sees the receiver's, so each attempt has one chance in a million (D-029). A new code is made for every authentication; the offer shows the code of the authentication that made it. Known answer for tests: senderFp `aa00…00`, receiverFp `bb00…00`, nonces `A`×43 and `B`×43 give `828838`.

**Trust**

1. **QR scan (strong).** The TLS pin proves the sender reached the phone in front of it.
2. **Tap from the nearby list (needs a check).** The receiver compares the code with the sender's screen before the first transfer from an untrusted device.

After a successful pairing the receiver can tick "Trust this device" in the Accept prompt, and the sender can tap "Trust" after a completed send. Trusted devices are stored by fingerprint, with name, platform, auto-accept, first and last seen. A trusted sender gets no code check, but still gets the Accept prompt unless the user turns on auto-accept for that device in Settings. Auto-accept applies only to that exact fingerprint. If a sender uses a trusted device's name or id with another fingerprint, both screens warn: "This is not the X you trusted."

**Abuse limits and server hygiene** (D-031, D-032)

- **Receiving switch** (Home and Settings, on by default). Off: the phone stops advertising and its QR code, offers from untrusted senders get 403 `receiving_off`, and the server stops as soon as no transfer is running. While the server is still running, offers from trusted devices are allowed. With the switch off, the server does not start at all.
- **Rate limits per IP address:** `POST /v1/sessions` 3 at once, then one every 20 s; `/v1/auth/challenge` and `/v1/auth` 10 at once, then one every 3 s. Over the limit: 429 `rate_limited` with `retryAfter` and a `Retry-After` header. At most 1,024 addresses, 64 open challenges and 256 tokens are remembered.
- **Request limits:** 16 KB of headers (431), 16 KB for auth and `complete` bodies, 4 MB for an offer (413); file bodies are limited by the declared size as before.
- **Server lifetime:** runs while the app is open, after the first-launch introduction (D-050), and the switch is on (D-046). It stops 30 s after the app is hidden with no offer waiting and no bytes moving (on Android a running transfer keeps going in the foreground service), and starts again when the app is shown. A new random port at every start. Idle keep-alive connections close after 30 s.

**Threats and defenses**

| Threat | Defense |
| --- | --- |
| Stranger on the same Wi-Fi sends unwanted files | Accept prompt with pairing code for every untrusted sender; rate limit per IP; Receiving switch |
| Someone fakes a device name in the nearby list | Identity is the fingerprint; code check for untrusted devices; lookalike warning for a trusted name with another key |
| Eavesdropping on the Wi-Fi | TLS 1.3 on all traffic |
| Man-in-the-middle | Pin from QR or trusted record; code from committed nonces on first contact; proofs bound to the receiver's fingerprint |
| Another sender hijacks a running session | Sessions belong to the authenticated fingerprint; others get 404 |
| Malicious file name such as `../../evil` | Sanitize names: strip paths, control characters and reserved names; limit length |
| Huge offer to fill the disk | Free-space check before accepting; reject if the file is larger than declared |
| Flood of requests | Rate limits; header and body limits; capped challenge, token and address tables |
| Corrupted or tampered file | SHA-256 verified before saving |
| Server left open in public | Server runs only while the app is open and the switch is on, stops when hidden and idle; new random port each start |
| Identity copied to another phone | Key in this-device-only Keychain or Keystore storage; Android backup and device transfer off |
| Old protocol version with a known bug | Minimum supported version in the app; reject below it |

**Privacy:** no accounts, no analytics on file names or contents, nothing leaves the local network. Logs carry at most the first 8 characters of a fingerprint.

## Platform modules

Most platform risk sits in four areas: how files are read, how they are saved, what happens when the screen locks, and how photo formats translate between the two systems. Each row below is a native module behind a Flutter platform channel or an existing plugin. Check exact API and permission names against current Apple and Android docs when you build.

| Area | iPhone (Swift) | Android (Kotlin) |
| --- | --- | --- |
| Discovery | Bonjour through the `bonsoir` plugin (NWBrowser and DNSServiceRegister). Avoid raw multicast sockets: they need a special Apple entitlement. Requires `NSBonjourServices` and `NSLocalNetworkUsageDescription`. | NsdManager (same plugin). A Wi-Fi multicast lock is held while browsing or advertising: bonsoir takes it on start and releases it on stop, and the app stops browsing in the background. Permissions: `CHANGE_WIFI_MULTICAST_STATE`, `ACCESS_WIFI_STATE`, `ACCESS_NETWORK_STATE`; no location. |
| Local network permission | System prompt on first discovery. If denied, nothing is found and connections fail. Detection (D-015): after 5 s with no peers, a Swift probe advertises and browses a short-lived Bonjour service; still `PolicyDenied` at 8 s means denied. The app then explains why and links to Settings. | No prompt on same Wi-Fi. Hotspot mode asks for `NEARBY_WIFI_DEVICES` (`neverForLocation`) on Android 13+, or `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` (max SDK 32) on Android 10–12, when the user taps Start. |
| QR scanning | `mobile_scanner` (AVFoundation); needs `NSCameraUsageDescription`. | `mobile_scanner` (ML Kit); `CAMERA` asked at runtime. |
| Picking photos and videos | Our own grid on `photo_manager` (permission, Limited access with "Select more", albums, thumbnails). It returns ids only; the file is exported when sending (D-038). The automatic Limited prompt is off. | Same grid. `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_VISUAL_USER_SELECTED` (Android 14 partial access) and `ACCESS_MEDIA_LOCATION`, so the original keeps its GPS (`setRequireOriginal`, D-037). |
| iCloud-only originals | Downloaded while preparing, before the offer, with progress ("Preparing 2 of 5: downloading from iCloud 40%") and Cancel. A failure or 90 s without progress leaves that item out with a message (D-038). | Not applicable. |
| Picking other files | Document picker (`file_picker`, import mode): iOS hands over a copy, downloading iCloud Drive files first; it is moved into the staging folder (D-041). | Our own `ACTION_OPEN_DOCUMENT`; content URIs read in place, with a persistable read grant released when the send ends. |
| Reading for sending | `PHAssetResourceManager` exports the current version of the original resource (edits applied, named after the original) chunk by chunk to `<app support>/crossdrop_outgoing/<batch>/`, then Dart streams it. A large video briefly needs equal free space. Staging is deleted when the send ends for good (D-038). | Kotlin opens the content URI and hands over the descriptor number; Dart reads it with `pread` through `dart:ffi` in a background isolate, without copying (D-036). Providers that cannot seek are streamed once into staging. |
| Saving received media | `PHAssetCreationRequest` with `shouldMoveFile`, the original name and creation date. Add-only access, asked when the user accepts media (D-043). | The pending MediaStore item in `Pictures/CrossDrop` or `Movies/CrossDrop` *is* the partial file; it is published once verified (D-040). No extra copy, no permission. |
| Saving other files | The Documents folder itself, shown in Files as On My iPhone > CrossDrop (`UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`). The database is not there (D-034). | Pending item in the MediaStore Downloads collection, `Download/CrossDrop`. |
| HEIC photos (iPhone → Android) | Default: send the original HEIC. Setting "Convert HEIC to JPEG": ImageIO at quality 0.92 with metadata and colour profile kept, HDR gain map lost (D-039). | Most modern Android galleries open HEIC; older ones may not. The setting's description says so. |
| Live Photos (iPhone → Android) | Default: send the still. Setting "Send Live Photo videos": also the MOV, named after the still, sharing `livePhotoGroup` (D-039). | Saved as a photo, plus a video if both were sent. No Live Photo playback. |
| HEVC / HDR video (iPhone → Android) | Send the original. | Most phones play HEVC. Dolby Vision HDR may look washed out on some Androids; note it in help, don't transcode in v1. |
| Android → iPhone formats | JPEG, PNG, HEIC, WebP, MP4 and MOV go to Photos. WebM, Matroska, AVI and anything Photos refuses go to Files, with a note on the Done screen. Motion Photos arrive as stills. | Not applicable. |
| Screen lock during transfer | Keep the screen on during a transfer (`wakelock_plus`). Use a short background task to finish the current chunk and save progress; resume when the app returns. | Foreground service of type data sync with a progress notification; transfer continues with the screen off. Needs `POST_NOTIFICATIONS`. |
| Battery and OEM killers | Not applicable. | Some brands (Xiaomi, Oppo, Vivo, OnePlus) kill background apps aggressively. Ask the user to exempt CrossDrop from battery optimization if transfers stop. |
| Hotspot | Can't create one from an app; the user turns on Personal Hotspot (guide with a live check, D-057). Joins an Android hotspot in-app with `NEHotspotConfigurationManager.apply`, `joinOnce` off and the network removed after use. Needs the Hotspot Configuration capability, which Apple gives to paid Developer Program accounts only; `RunnerHotspot.entitlements` holds it, and builds without it guide the user through Settings (D-055). | `WifiManager.startLocalOnlyHotspot` with a random name and password, read from `getSoftApConfiguration()` (API 30+) or `getWifiConfiguration()` (API 29); no internet sharing. Stops with the hotspot screen or 60 s after the last transfer (D-054). |
| Creation dates | Photos: `creationDate`. Files: modification date only (D-042). | `DATE_TAKEN` and the file time; Downloads keep only the file time. Files without EXIF (PNG) may show the receive time. |
| Network binding | Local subnet traffic goes over Wi-Fi even without internet. | `ConnectivityManager.bindProcessToNetwork` when Wi-Fi is connected, not validated and not the default; cleared otherwise and when the Wi-Fi is lost. Whole process, because `dart:io` makes its own sockets (D-056). |
| Share from other apps | Share Extension target: clones the files into an App Group inbox (no file in memory), writes a manifest, opens `crossdrop://share`. The app checks the manifest, moves the files into staging and opens Send with them selected (D-045). | Intent filters for `SEND` and `SEND_MULTIPLE` on a `singleTask` activity; only content URIs of other apps; read in place (D-044). |

## Screens

Home is also the receive screen: while CrossDrop is open and Receiving is on, the phone can be found, and an offer opens the Incoming request on top of any screen (D-046). Sending goes files first, then the phone (D-052). The same Progress, Done and Failed screens serve both directions (D-048). A first-launch introduction comes before any network use (D-050). Screen flow and details: [features/ui-navigation.md](features/ui-navigation.md), [features/onboarding.md](features/onboarding.md), [features/settings.md](features/settings.md).

## Failure handling

Every failure ends in one of three outcomes: an automatic resume, a clear message with the next step, or a clean cancel that leaves no half-saved files. The words the app shows for each row, and the button for the next step, are in one table (`lib/features/transfer/failure_messages.dart`, D-049).

| Failure | How it's detected | Recovery |
| --- | --- | --- |
| No devices found | Discovery shows nothing after about 5 s | Check Local Network permission (iOS) and Wi-Fi; offer QR scan; then offer hotspot mode |
| Local Network permission denied (iOS) | Nothing found within 5 s, then the Bonjour self-probe (D-015) stays in `PolicyDenied` | Explain why it's needed; button to open Settings; probe again on return |
| Receiver's Wi-Fi or IP changes | Connectivity event or a changed address list (3 s poll) | Re-advertise and redraw the QR code; the sender's nearby list restarts browsing |
| Stale entry in the nearby list | `GET /v1/info` fails, or another device id answers | Remove the entry and tell the user; pull to refresh |
| QR connect times out | TCP connect fails within 5–10 s | Likely client isolation or different networks; suggest hotspot mode |
| Certificate fingerprint mismatch | TLS handshake fails pinning check (`pin_mismatch`) | Stop; warn "This isn't the device you scanned"; never retry and never fall back to unpinned |
| Trusted name, different key | Trusted record matches the name or id, not the fingerprint | Warn "Not the X you trusted"; the user may go on only as untrusted, with the code check |
| Receiving is off | 403 `receiving_off` | Sender: "The other phone is not receiving." Receiver: a notice that a transfer was refused |
| Too many requests | 429 `rate_limited` with `retryAfter` | Sender waits and retries; repeated offers stay refused |
| Token unknown (receiver restarted) | 401 `auth_required` | Authenticate again and retry once, then continue |
| Receiver rejects or doesn't answer | `rejected` event, or no answer within 60 s | Tell the sender; nothing is sent |
| Not enough space on receiver | Free-space check before the prompt and again at Accept, and write errors during transfer | Reject the offer with the needed size; if it runs out mid-transfer, pause and keep the partial file; the sender stops with "free some space, then Resume" |
| Wi-Fi drops mid-transfer | Socket error or no progress for 15 s | Retry with backoff (1, 2, 4, 8 s, then 8 s, up to about 2 min without progress, D-019); resume from `receivedBytes`. After that, the Send screen offers Resume |
| iPhone screen locks or app backgrounded | App lifecycle events (hidden) | Inside a background task: the sender finishes the current chunk and pauses, the receiver saves progress. On return the sender continues; time in the background does not use up the retry deadline |
| Android app killed by battery saver | Session lost; partial file remains | On next launch, show "Resume unfinished transfer?"; resume if the sender reconnects |
| App crash or phone restart | Partial files and session rows in the database | Part files cut back to the last checkpoint; same resume prompt; delete partial files older than 24 hours |
| Receiver app restarts | The server listens on a new random port | The sender finds it again by device id over mDNS after 3 failed tries, once CrossDrop is open again |
| Hash mismatch | `complete` verification fails | Restart that file from zero once; then mark it failed; the other files continue |
| More bytes than declared | Content-Length or counting on the receiver | That file fails and its partial file is deleted; the other files continue |
| Peer IP changes (DHCP, reconnect) | Connection refused at the old address | Rediscover by device id via mDNS and continue |
| Source file gone or changed | Size check before offering and before each file | Cancel the session (v1 cannot skip a file) and say which problem it was |
| VPN blocks local traffic | Connect fails while a VPN is active | Suggest pausing the VPN |
| iCloud original won't download | Export fails, or no progress for 90 s, while preparing | That item is left out before the offer, with "only in iCloud and could not be downloaded"; the others are sent (D-038) |
| Picked item gone before sending | Export or open fails while preparing (deleted, or no longer shared under Limited access) | Left out before the offer, with the reason |
| Sender out of space while preparing | Export write fails with no space | That item and the rest are left out; "not enough free space on this phone" |
| Unsupported format on the receiver | Extension not in the gallery list, MediaStore refuses the MIME type, or Photos refuses the file | Save to Files or Downloads instead; the Done screen says why |
| No Photos access on the receiver (iPhone) | Add-only access denied | Save to Files; "CrossDrop may not add to Photos" |
| Shared file no longer readable (Android) | The share intent's grant ended with the process | The send stops with "a file could not be read any more"; share again |
| Protocol version mismatch | `/v1/info` versions don't overlap | "Update CrossDrop on the other phone" |
| User cancels | Cancel tap on either side | DELETE the session; receiver deletes partial files; both show "Cancelled" |

## Data model, code structure and performance

**Local database (drift or sqflite)**

| Table | Key fields |
| --- | --- |
| `identity` | deviceId, deviceName, certificate (private key stays in Keychain/Keystore) |
| `trusted_devices` | fingerprint (key), deviceId, name, platform, autoAccept, firstSeen, lastSeen |
| `sessions` | sessionId + direction (unique), peerDeviceId, peerName, peerPlatform, peerFingerprint, peerHost and peerPort (send), status, reason, totalBytes, createdAt, updatedAt, finishedAt |
| `session_files` | session row + fileId, position, name, size, mime, kind, created, livePhotoGroup, sha256, transferredBytes, tempPath, sourcePath (send), finalLocation, status, hashAttempts, errorCode |
| `settings` | receivingEnabled (Phase 4); convertHeicToJpeg, sendLivePhotoVideo (Phase 5); onboardingDone (Phase 6) |

Schema version 5. The database file is in Application Support, not Documents (D-034). `session_files.tempPath` is a path or an Android MediaStore content URI; `sourcePath` is a path or a content URI; `finalLocation` is a path, a content URI or `photos:<id>`, never shown. Session status: see [Session state machine](#session-state-machine). Both directions are stored. Sessions stored before Phase 4 have no peerFingerprint and cannot resume: a received one is marked failed at start, a sent one asks the user to send again. A sent session that gave up on the network stays `paused`, so the launch prompt can offer to resume it.

**Code structure**

```text
crossdrop/
  lib/
    app/            # routing, theme, Riverpod providers
    features/
      home/         # "Ready to receive" + switch + send button
      onboarding/   # first-launch introduction
      nearby/       # discovered devices list, QR scanner, find help
      send/         # file picking, offer screen
      receive/      # receiving host, incoming request, my QR code
      transfer/     # progress, speed, pause, cancel, done, failed
      hotspot/      # Android hotspot, iPhone join, Personal Hotspot guide
      bench/        # benchmark screen (benchmark builds only)
      history/      # past transfers
      settings/
    core/
      protocol/     # message models, versioning, JSON
      server/       # HTTPS server, routes, session handlers
      client/       # HTTPS client, upload streams, retry/backoff
      engine/       # chunking, resume, hashing (isolate), queue
      discovery/    # bonsoir wrapper, TXT parsing
      security/     # identity, certs, pinning, 6-digit code
      storage/      # database, temp files, cleanup
      media/        # prepare before offer, format plan, save collection
      bench/        # benchmark runner, stats, CSV (benchmark builds only)
    platform/       # Dart side of platform channels
  ios/
    Runner/         # PhotoKit export/save, hotspot join, background task
    ShareExtension/ # Share Extension: App Group inbox hand-off
  android/
    app/src/main/kotlin/  # MediaStore save, fd streaming, LocalOnlyHotspot,
                          # foreground service, multicast lock, network binding
  test/             # protocol, engine, resume unit tests
  integration_test/ # two-device transfer tests
```

**Performance design**

- One TLS connection per session, reused for every file.
- Stream reads and writes with 1 MB buffers to start; benchmark 256 KB, 1 MB and 4 MB.
- Hash with SHA-256 incrementally in a background isolate, so the UI never stutters.
- Don't pass file bytes through platform channels: Dart reads files directly (temp file on iPhone, file descriptor on Android).
- Save progress every 4 MB, not every write, to keep database writes low.
- Calculate speed as a moving average over the last 3 seconds.
- Benchmark matrix: 10 MB, 100 MB, 1 GB, 2 GB files × router 2.4 GHz, router 5 GHz, Android hotspot, iPhone hotspot × both directions. Compare with LocalSend on the same phones.
- Benchmark builds (`--dart-define=CROSSDROP_BENCH=true`, release mode) run that matrix through the real engine and write CSV ([features/benchmark-mode.md](features/benchmark-mode.md), D-058). One stream per transfer until the measurements show a clear gain from more (D-059).

## Open decisions

- [ ] Custom protocol (this document) or LocalSend-compatible protocol? Compatibility would let CrossDrop talk to LocalSend users; check its protocol and license first.
- [x] HEIC default: send the original; JPEG is a setting (Phase 5, D-039).
- [x] Live Photos default: the still only; the video is a setting (Phase 5, D-039).
- [x] iPhone Personal Hotspot: an in-app guide in v1, next to Android hotspot mode (Phase 6).
- [x] Trusted devices: allow auto-accept, or always show the Accept prompt? Auto-accept is allowed, off by default, per trusted device (Phase 4).
- [x] Minimum OS versions: iOS 15, Android 10 (SDK 29), for MediaStore pending items and the Downloads collection (Phase 5, D-035).
- [ ] What speed target counts as success, decided after the Phase 1 proof of concept measures real numbers?
