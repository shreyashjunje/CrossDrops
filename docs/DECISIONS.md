# Decisions

A log of design decisions that are hard to reverse or easy to forget the reason for. Newest entries go at the bottom. Do not edit an accepted entry to change its meaning: add a new entry that supersedes it and set the old status to `Superseded by D-NNN`.

## Format

```markdown
## D-NNN: Short title
- Date: YYYY-MM-DD
- Status: Proposed | Accepted | Superseded by D-NNN
- Context: what forced a choice
- Decision: what we chose
- Consequences: what gets easier, what gets harder, what we accepted
```

Details of each decision live in [ARCHITECTURE.md](ARCHITECTURE.md). This file records the why.

## D-001: The receiver runs the HTTPS server
- Date: 2026-11-01
- Status: Accepted
- Context: Two phones need a client/server split. Hotspot and router modes differ in who is the access point, and iOS cannot create a hotspot.
- Decision: The phone that receives runs the HTTPS server; the sender is the client. This holds in every network mode.
- Consequences: One code path for every connection mode, so the transfer engine does not care how phones are connected. Both phones must be able to run a server. The server runs only while the app is open.

## D-002: Plain HTTPS with streamed PUT for file bytes
- Date: 2026-11-01
- Status: Accepted
- Context: Files can be gigabytes and must be resumable without loading them into memory.
- Decision: Control uses HTTPS + JSON, file bytes use streamed PUT bodies with `?offset=N`, and one WebSocket per session carries events. No custom binary protocol.
- Consequences: Works with `dart:io` and shelf, easy to test without phones, and resume is a GET plus a PUT. HTTP framing adds a little overhead; parallel streams are added only if benchmarks show a gain.

## D-003: Mutual TLS with pinned self-signed certificates
- Date: 2026-11-01
- Status: Superseded in part by D-027 (the sender proves its key inside TLS instead of with a client certificate)
- Context: There is no server or account to vouch for identity, and the local network cannot be trusted.
- Decision: Each device creates its own ECDSA P-256 key and self-signed certificate. The certificate's SHA-256 fingerprint is the device identity. Both sides present certificates and pin fingerprints (from QR or trusted record). Untrusted senders need an Accept tap, and tapped-from-list devices also get a 6-digit code check.
- Consequences: No accounts or CA needed, and encryption plus identity come from one mechanism. We never fall back to unpinned TLS once a fingerprint is known. `dart:io` support for self-signed client certificates may have limits; if so, propose an alternative before building it.

## D-004: Flutter, with native code only where the OS requires it
- Date: 2026-11-01
- Status: Accepted
- Context: One team needs iPhone and Android apps with the same protocol and behavior.
- Decision: Protocol, engine, security and UI are shared Dart. Swift and Kotlin are used only for photo library access and saving, hotspot, background and foreground-service behavior, Bonjour/NSD details, and share extension or intents. Platform code sits behind Dart interfaces.
- Consequences: Most code is testable on a computer. Native modules stay small, but platform channels must carry paths or file descriptors, never file bytes.

## D-005: No cloud server in v1
- Date: 2026-11-01
- Status: Accepted
- Context: A relay would allow transfers across networks but adds cost, accounts and privacy exposure.
- Decision: v1 has no cloud server, relay, accounts or analytics. Phones connect directly over the local network or a hotspot.
- Consequences: Nothing leaves the local network. Phones on different networks are unsupported and the app says so; a relay (WebRTC + TURN) is a possible future addition.

## D-006: shelf and shelf_router for the receive server
- Date: 2026-11-02
- Status: Accepted
- Context: The receiver needs an HTTPS server with path parameters and streamed request bodies, on top of `dart:io` (D-002, D-004).
- Decision: Use `shelf` with `shelf_io.serve(..., securityContext:)` and `shelf_router` for routes such as `/v1/sessions/<sid>/files/<fid>`. Both are maintained by the Dart team.
- Consequences: Handlers are plain functions that are easy to test over loopback. `Request.read()` streams the body, so nothing is buffered. Two small dependencies instead of hand-written routing. WebSocket events will need `shelf_web_socket` later.

## D-007: `crypto` for SHA-256 instead of `cryptography`
- Date: 2026-11-02
- Status: Accepted
- Context: Transfers hash files of several GB incrementally in a worker isolate. CLAUDE.md suggests `cryptography`.
- Decision: Use the Dart team's `crypto` package (`sha256.startChunkedConversion`) for file hashing. It is synchronous, pure Dart, and fits a chunk-by-chunk isolate loop.
- Consequences: Simple, well-tested hashing with no platform code. `cryptography` may still be added later for signatures or key agreement (6-digit code, Phase 4) if `basic_utils`/pointycastle are not enough; that will be its own decision.

## D-008: `basic_utils` to create the self-signed certificate
- Date: 2026-11-02
- Status: Accepted
- Context: Each receiver needs an ECDSA P-256 key and a self-signed X.509 certificate that `dart:io`'s `SecurityContext` accepts. `dart:io` cannot create certificates.
- Decision: Use `basic_utils` (built on pointycastle) to generate the key pair, CSR and self-signed certificate as PEM, in a background isolate. Verified on the dev PC: generation takes about 170 ms and a `dart:io` HTTPS server accepts the result.
- Consequences: Pure Dart, no OpenSSL or native code. In Phase 1 the identity is thrown away at each launch. Phase 4 must store the key in the Keychain/Keystore and check that a client certificate made the same way works for mutual TLS on both platforms.

## D-009: `file_picker` for picking files in Phase 1
- Date: 2026-11-02
- Status: Accepted (Phase 1 only; revisit with the platform modules)
- Context: The PoC needs to pick any file on both platforms without native code.
- Decision: Use `file_picker`. It returns a local path: Android copies the content URI into the app cache, iOS copies into tmp.
- Consequences: Works with the file-based reader. Sending a large file briefly needs equal free space, and the copy takes time before Send. The architecture's fd streaming (Android) and PhotoKit export (iOS) replace this for photos and videos later.

## D-010: Supporting packages for Phase 1
- Date: 2026-11-02
- Status: Accepted
- Context: The PoC app needs state management, app folders, a screen-awake lock and path handling.
- Decision: `flutter_riverpod` (state, per CLAUDE.md), `path_provider` (temp, documents and Android external files folders), `wakelock_plus` (keep the screen on while receiving and sending; iOS pauses apps on lock), `path` (path joins and containment checks; was already a transitive dependency).
- Consequences: All are widely used Flutter-team or Flutter Community packages. No network calls outside the local network.

## D-011: Phase 1 client accepts any server certificate, and offers are auto-accepted
- Date: 2026-11-02
- Status: Superseded by D-027 and D-033 (Phase 4)
- Context: The PoC has no discovery, QR or pairing, so there is no fingerprint to pin and no Accept prompt.
- Decision: The upload client accepts any server certificate and sends no client certificate (`TODO(phase4)` in `upload_client.dart`); `POST /v1/sessions` is accepted immediately. Traffic is still TLS-encrypted.
- Consequences: Not safe against a man in the middle or unwanted senders on the same network; acceptable only for development builds on a trusted Wi-Fi. Phase 4 removes the bypass with no fallback (CLAUDE.md hard rule 4), and the session-flow phase adds the Accept prompt and free-space check.

## D-012: bonsoir for Bonjour/mDNS discovery
- Date: 2026-11-02
- Status: Accepted
- Context: Phase 2 needs to advertise and browse `_crossdrop._tcp` with TXT records on iOS and Android, without raw multicast sockets (which need an Apple entitlement).
- Decision: Use `bonsoir` 7.1. Checked in its source: on iOS it uses `NWBrowser` (with TXT) and `DNSServiceRegister`; on Android it uses `NsdManager`. Each `start()` takes a reference-counted Wi-Fi multicast lock and the matching `stop()` releases it, so we do not add our own Kotlin lock. Its logs are turned off because they contain device names. The alternative, `nsd` 5.0, is less active and offered nothing extra.
- Consequences: No native discovery code of ours. Discovery sits behind `MdnsBackend`, so it is tested with a fake. bonsoir ignores `NWBrowser`'s `.waiting(PolicyDenied)` state, so iOS permission detection needs its own probe (D-015). Browsing must be stopped in the background to release the lock.

## D-013: drift for the local database
- Date: 2026-11-02
- Status: Accepted
- Context: The device identity must persist now. ARCHITECTURE.md lists five tables for later phases. CLAUDE.md allows drift or sqflite.
- Decision: Use `drift` and `drift_flutter`, with `drift_dev` and `build_runner` as dev dependencies. The generated `database.g.dart` is committed so builds do not need code generation.
- Consequences: Typed tables and queries, and migrations through `schemaVersion`. Unit tests use `NativeDatabase.memory()`, which runs on the dev PC (sqlite is bundled by `sqlite3` 3.x). The cost is a code-generation step when the schema changes (`dart run build_runner build`).

## D-014: Packages for QR codes and network changes
- Date: 2026-11-02
- Status: Accepted
- Context: The QR fallback needs to draw and scan codes. Discovery must react when the Wi-Fi or IP changes.
- Decision:
  - `qr_flutter` draws the code. It is pure Dart; its last release was 2023, but it is stable.
  - `mobile_scanner` scans: ML Kit on Android, AVFoundation on iOS. It handles the camera permission.
  - `connectivity_plus` gives OS network events, combined with polling `NetworkInterface.list` every 3 s.
  - Not added: `network_info_plus` (reading the Wi-Fi name needs location permission on Android), `uuid` (16 bytes from `Random.secure` is enough), `app_settings` (our channel opens Settings), `device_info_plus` (the default name is "iPhone" or "Android XXXX" and the user can edit it).
- Consequences: The camera permission is added on both platforms. None of these packages makes network calls.

## D-015: Detect iOS Local Network denial with a Bonjour self-probe
- Date: 2026-11-02
- Status: Accepted
- Context: iOS has no API to read the Local Network permission. When it is denied, discovery returns nothing and connections fail, and bonsoir does not report it (D-012).
- Decision: After 5 s with no peers, the Nearby screen calls a Swift probe over the `crossdrop/local_network` channel. The probe advertises a short-lived `_crossdrop._tcp` service with `NWListener` and browses for it with `NWBrowser`:
  - seeing its own service means `granted`
  - still waiting with `PolicyDenied` at the 8 s timeout means `denied`
  - anything else means `unknown`

  Only `denied` shows the explanation screen. A peer appearing later clears it, and returning from Settings probes again. Android answers `granted`.
- Consequences: The answer is reliable without private APIs. The code lives in `AppDelegate.swift`, so the Xcode project file does not change. The probe service is briefly visible to other phones, which ignore it because it has no TXT record. While the first-run prompt is open longer than the timeout, the result can be a false `denied`; Try again fixes it.

## D-016: Phase 2 advertises only while Receive is open, with the per-launch fingerprint
- Date: 2026-11-02
- Status: Superseded in part by D-028 (persistent fingerprint) and D-031 (Receiving switch)
- Context: Offers are still accepted automatically (D-011), so advertising whenever the app is open would let anyone on the Wi-Fi push files. Phase 4 brings the persistent certificate. Until then the server creates a certificate at each launch.
- Decision: The server and the advertisement run only while the Receive screen is open. TXT `fp` and the QR `fp` use the real fingerprint of the current per-launch certificate, not a placeholder. Nothing checks it yet.
- Consequences: The formats are final, and Phase 4 only has to start checking the fingerprint. Receiving requires opening Receive first. The fingerprint, port and QR code change at each launch.

## D-017: GitHub Actions builds; iPhone installed by sideloading with a free Apple ID
- Date: 2026-11-02
- Status: Accepted
- Context: There is no Mac, so iPhone builds cannot be made locally. Expo Go-style "scan and run" does not work for apps with custom native code, in Flutter or React Native. Ad hoc and TestFlight installs need the paid Apple Developer Program.
- Decision: `.github/workflows/build.yml` runs analyze, format check and tests on every push and pull request (Linux). When started manually, it also builds a release APK (Linux) and an unsigned iPhone `.ipa` (`flutter build ios --no-codesign` on a GitHub macOS runner, packaged as `Payload/Runner.app`). The `.ipa` is installed from Windows with Sideloadly, which signs it with a free Apple ID. The builds are started manually after each phase.
- Consequences:
  - No Mac and no paid account needed for device testing. The Swift code is now compiled in CI.
  - The free-account app expires after 7 days, and only a few sideloaded apps can be active at once.
  - Capabilities that need a paid account, such as Hotspot Configuration for joining a hotspot in-app, will not work in these builds. The hotspot phase must plan for that, for example by joining the hotspot manually in iOS Settings.
  - On a private repository, macOS minutes count 10×, which is why the device builds are manual only.

## D-018: Sessions start as "offered"; status endpoint and event replay
- Date: 2026-11-02
- Status: Accepted
- Context: ARCHITECTURE.md had `POST /v1/sessions` return `pending`, while the state machine starts at `offered`. A sender whose event socket connects after the user tapped Accept, or that reconnects after a drop, would miss the answer.
- Decision: The wire status is the state name, so `POST` returns `offered`. A new `GET /v1/sessions/{id}` returns the session status, reason and per-file status. A newly connected event socket first replays the current state. The sender also polls the status every 2 s while it waits for Accept.
- Consequences: One status vocabulary everywhere. The answer is never lost to a late or broken socket. One extra endpoint.

## D-019: Retry backoff 1, 2, 4, 8 s, then 8 s, for about 2 minutes
- Date: 2026-11-02
- Status: Accepted
- Context: "Retry with backoff (1, 2, 4, 8 s, up to about 2 minutes)" can mean capping at 8 s or doubling on.
- Decision: The delays are 1, 2, 4 and 8 s, then 8 s repeating, each ±20 % jitter. The sender gives up after 2 minutes without progress. Progress, meaning the receiver confirmed more bytes, resets both the delay and the deadline. Time in the iOS background does not count. After 3 failures in a row, the sender looks the receiver up again by device id.
- Consequences: A phone that comes back within 2 minutes resumes within at most about 10 s. Doubling to 32 or 64 s would leave users waiting with nothing visibly happening. After giving up, the session stays resumable from the Send screen and from the launch prompt.

## D-020: Free space through a small platform channel, not a package
- Date: 2026-11-02
- Status: Accepted
- Context: Dart has no free-space API, and the receiver must check space before accepting.
- Decision: The `crossdrop/storage` channel has one method, `freeBytes(path)`. Android uses StatFs. iOS uses `volumeAvailableCapacityForImportantUsage`, which counts purgeable space, like Files and Photos do. It sits behind the `FreeSpace` interface.
- Consequences: About 30 lines of native code, no new dependency, and the iOS figure is the right one. Unknown free space (desktop, tests) does not block an offer.

## D-021: Resume without re-hashing what was already sent
- Date: 2026-11-02
- Status: Accepted
- Context: Phase 1 rebuilt the hash of the bytes already transferred before every resumed PUT, on both sides. With pure-Dart SHA-256 on a phone, a 2 GB prefix can take longer than the 15 s stall timeout, so a large resume could never finish.
- Decision: The sender hashes each source file in its own isolate, in parallel with sending and independent of drops. The receiver keeps each file's incremental hash alive across drops, in step with the bytes on disk. After a receiver restart there is no hash in memory, so `complete` hashes the file from disk, and the sender allows 2 minutes plus 1 s per 20 MB for that.
- Consequences: A drop costs nothing extra. The sender reads each file twice, which is cheap next to Wi-Fi. Only the rare receiver-restart case pays for a full hash, at the end, where no stall timer runs.

## D-022: Checkpoint = fsync, then store receivedBytes; restore cuts back
- Date: 2026-11-02
- Status: Accepted
- Context: After a crash, a part file may be longer than what really reached the disk, and the tail may hold garbage.
- Decision: Every 4 MB, and whenever an upload stops, the receiver fsyncs the part file and then stores `receivedBytes`. On restart the part file is truncated to that value.
- Consequences: A crash never turns into a silently corrupt resume; the hash check would catch it, but only at the very end. At most 4 MB is sent again. Some fsync cost, to be measured in benchmarks.

## D-023: Receiver limits and what "too many bytes" does
- Date: 2026-11-02
- Status: Accepted
- Context: The receiver must not trust offers or bodies. Phase 1 discarded an oversized upload but kept the file resumable.
- Decision:
  - More bytes than declared **fails that file**: its partial file is deleted and the other files continue.
  - One unfinished session per sender id (409 `sender_busy`) and at most 8 open sessions in total (503).
  - At most 10,000 files and 1,024-character names per offer.
  - Free space must cover the offer, the bytes still expected by other open sessions, and 64 MB, and is checked again at Accept.
- Consequences: A misbehaving sender cannot loop on the same file or fill the disk. Until Phase 4 proves sender identity, the per-sender limit only stops honest mistakes.

## D-024: Keep-alive with flutter_foreground_task and an iOS background task
- Date: 2026-11-02
- Status: Accepted
- Context: Android needs a foreground service of type data sync for a transfer to continue with the screen off. iOS suspends apps shortly after they are hidden.
- Decision:
  - **Android:** `flutter_foreground_task` runs the service, shows the notification and takes the Wi-Fi and wake locks. The transfer itself stays in the app's isolate; the service has no task of its own.
  - **iOS:** a small Swift channel calls `beginBackgroundTask`, inside which every transfer saves its progress and pauses. Transfers resume on return.
  - **Both:** the screen stays on during transfers (`wakelock_plus`). The send controller is app-wide, so leaving the Send screen does not stop a transfer.
- Consequences: A maintained plugin instead of hand-written Kotlin service code. Behaviour is not verified on devices yet. Android 15 caps `dataSync` at 6 hours a day.

## D-025: Partial files in the app support folder
- Date: 2026-11-02
- Status: Accepted
- Context: Phase 1 kept `.part` files in the OS temp folder. iOS and Android may purge temp and cache folders while the app is closed, which breaks resume after a restart.
- Decision: Partial files go to `<application support>/crossdrop_incoming/<sessionId>/`. They are deleted when a session ends, and by the 24-hour cleanup at launch.
- Consequences: Resume after restart works. Leftovers are our job to clean, which the cleanup does.

## D-026: Multi-gigabyte tests are tagged and skipped by default
- Date: 2026-11-02
- Status: Accepted
- Context: The 2 GB test needs about 4 GB of disk and two to three minutes. Running it on every `flutter test` and CI push would be slow.
- Decision: The test is tagged `large` and skipped in `dart_test.yaml`. Run it with `flutter test --run-skipped --tags large` before a phase is called done. A 50 MB memory test stays in the default run.
- Consequences: Fast default runs. The 2 GB check only happens when someone runs it.

## D-027: Sender authentication by signed challenge, because dart:io cannot do mutual TLS with unknown certificates
- Date: 2026-11-03
- Status: Accepted
- Context: The design asked for mutual TLS with self-signed certificates (D-003). Tested on Dart 3.13 (Windows; the TLS code is BoringSSL on all platforms): a `SecureServerSocket` with `requestClientCertificate` or `requireClientCertificate` drops the connection when the client presents a self-signed certificate it does not already trust. There is no server-side callback to accept it. It works only when the server's `SecurityContext` already trusts that exact certificate, which is never true on first contact. The client side works: `onBadCertificate` gets the leaf, and a chain with the pinned certificate appended after an attacker's leaf is refused.
- Decision:
  - TLS 1.3 authenticates only the server. The sender pins the receiver's fingerprint with a custom `connectionFactory`, checks the leaf in the handshake and again before any request byte, and never retries unpinned.
  - The sender proves its own key inside that connection: commit to a nonce (`/v1/auth/challenge`), then sign receiver fingerprint, sender fingerprint and both nonces with ECDSA P-256 / SHA-256 (`/v1/auth`). It gets a bearer token (memory only, 1 hour idle) for `/v1/sessions…`. Sessions belong to the authenticated fingerprint.
  - Considered: native TLS on each platform (a lot of native code, against "no native networking"); pre-loading every trusted certificate into the server context (does not help first contact, needs a restart per change); TLS exporter channel binding (not exposed by dart:io).
- Consequences: Same security goal as mutual TLS: the receiver learns a proven sender fingerprint, a proof cannot be relayed to another receiver, and the token only travels in pinned TLS. Two extra round trips per connection setup. The token is a bearer secret: anyone who could read the TLS stream could reuse it, which pinning prevents. Revisit if dart:io gains a server-side certificate callback.

## D-028: basic_utils for the persistent device identity
- Date: 2026-11-03
- Status: Accepted
- Context: Phase 4 needs a persistent ECDSA P-256 key, a self-signed certificate that `dart:io` accepts, and ECDSA signing and verification for D-027. D-008 picked `basic_utils` for the per-launch certificate.
- Decision: Keep `basic_utils` (pure Dart, on pointycastle): key pair, CSR and self-signed certificate (subject `CN=CrossDrop`, 20-year validity, ECDSA with SHA-256), and signing with `SHA-256/DET-ECDSA` (RFC 6979, no random nonce). Peer certificates are parsed, limited to 4 KB and must hold a P-256 key. Considered: `cryptography` (no X.509), raw pointycastle (we would rewrite the ASN.1 code that basic_utils already has), a non-exportable Keystore or Secure Enclave key (cannot be handed to Dart's TLS stack).
- Consequences: No new package and no native crypto. Pitfall: `CryptoUtils.ecSign` and `ecVerify` default to SHA-1; our code always passes the algorithm, and a test checks the certificate's signature algorithm. Generation takes about 30 ms. Certificate dates are never checked, because identity is the pinned fingerprint.

## D-029: The pairing code includes committed nonces, not only the two fingerprints
- Date: 2026-11-03
- Status: Accepted
- Context: The design said "a 6-digit code derived from both fingerprints". A man in the middle on a first contact chooses its own keys. With a code made only from fingerprints, it can generate keys until its two connections show the same code: about 10^6 tries, minutes on a laptop.
- Decision: `code = SHA-256("crossdrop-code-v1\n" + senderFp + "\n" + receiverFp + "\n" + senderNonce + "\n" + receiverNonce)`, first 6 bytes as a big-endian number, mod 10^6. The nonces come from sender authentication (D-027). The sender commits to its nonce before it sees the receiver's, as in Bluetooth numeric comparison. A known-answer test pins the formula.
- Consequences: Each attempt by an attacker has one chance in a million, and failures show up as codes that differ. The code changes at every authentication, so it is shown per offer, not per device. It is still derived from both fingerprints, as the brief asked.

## D-030: flutter_secure_storage for the private key; app backup off
- Date: 2026-11-03
- Status: Accepted
- Context: The private key must be in the iOS Keychain or Keystore-backed storage, never in a plain file or the database. A reinstall must give a new identity, and the key must not move to another phone.
- Decision: Add `flutter_secure_storage` 11.2. iOS: Keychain, `first_unlock_this_device` (not synced, not restored to another device). Android: AES-GCM with a key wrapped by an Android Keystore key; it resets on keystore errors. The identity row is the source of truth: no certificate in the database means a new key, even if an old one is still in the Keychain, which survives an app delete on iOS. Android `allowBackup="false"`, `fullBackupContent="false"` and data-extraction rules that exclude everything.
- Consequences: A maintained plugin, no own Swift or Kotlin. App data, transfer history and trusted devices are not in Android backups. An iOS backup restored to a new iPhone brings the database but not the key, so that phone gets a new identity. The key is in Dart memory while the app runs (needed for TLS).

## D-031: The Receiving switch and server lifetime
- Date: 2026-11-03
- Status: Accepted
- Context: The brief asks for a global "Receiving on/off" switch that rejects offers from untrusted devices when off, and for the server to run only while receiving is on and the app is open. Stopping the server mid-transfer would break a transfer the user already accepted.
- Decision: One setting, on by default, on the Receive screen and in Settings. Off: stop advertising and hide the QR code at once, answer offers from untrusted senders with 403 `receiving_off`, and stop the server as soon as no session is offered or running. With the switch off the server never starts. The server still runs only while the Receive screen is open (D-016), with a new random port at each start.
- Consequences: Turning the switch off never breaks a running transfer. While the server drains, a trusted device can still make an offer. A paused session keeps the server up until the Receive screen closes.

## D-032: Abuse limits
- Date: 2026-11-03
- Status: Accepted
- Context: Anyone on the Wi-Fi can reach the server while it runs.
- Decision: Token buckets per remote IP: offers 3 at once, then 1 per 20 s; auth requests 10 at once, then 1 per 3 s; 429 with `retryAfter`. Headers at most 16 KB (431), because the dart:io limit is a fixed 1 MB. Bodies: 16 KB for auth and `complete`, 4 MB for offers (413). Memory caps: 1,024 tracked addresses, 64 open challenges, 256 tokens, oldest dropped first. Idle keep-alive connections close after 30 s. One unfinished session per sender fingerprint (was per claimed id, D-023).
- Consequences: A flood costs the receiver little and reaches the Accept prompt at most 3 times a minute per address. Someone sharing an address with an honest sender (NAT, hotspot) shares its bucket, which is fine on a home network. The numbers are a first guess; device tests may tune them.

## D-033: First contact, lookalikes and trust records
- Date: 2026-11-03
- Status: Accepted
- Context: Only the QR code carries the full fingerprint. The nearby list has a 16-character hint; a typed address has nothing. Trust must be by fingerprint, and a trusted name with another key must be flagged.
- Decision:
  - Without a QR fingerprint, the sender reads the fingerprint from one TLS handshake that sends no request (`probeFingerprint`). From the nearby list it must start with the TXT hint. Everything after that is pinned to it, and the pairing code checks it.
  - The Send screen runs this check itself for a typed address, so no path sends unpinned.
  - Trust records hold fingerprint, device id, name, platform, auto-accept, first and last seen. Lookup is by fingerprint only. A trusted name or id with another fingerprint is a lookalike: a warning on both phones, and the user can go on only as untrusted, with the code.
  - The same table serves both directions. The receiver trusts from the Accept prompt; the sender trusts after a completed send. Auto-accept matters only on the receiving side and is off by default.
- Consequences: A reinstalled phone shows up as a lookalike until the user forgets the old record or trusts the new one. A wrong QR fingerprint can never be "continued anyway".
