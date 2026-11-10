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
- Status: Superseded by D-065 (the interval; the mechanism stands)
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

## D-034: The database lives in Application Support, not Documents
- Date: 2026-11-03
- Status: Accepted
- Context: `drift_flutter` puts the database in the Documents folder by default. On iOS that folder is visible in the Files app (`UIFileSharingEnabled`, needed for received files), so the user could open or delete the database, and Phase 5 makes Documents the place for received files.
- Decision: Pass `databaseDirectory` = Application Support on both platforms. At startup, a database found in Documents is moved there once (side files first, then the main file), never over an existing one.
- Consequences: Files shows only received files. An interrupted move finishes on the next launch. Android moves too (both folders are private there), so the code path is the same.

## D-035: Android minimum SDK 29 (Android 10)
- Date: 2026-11-03
- Status: Accepted
- Context: Saving straight into the gallery and Downloads (D-040) needs MediaStore `IS_PENDING`, `RELATIVE_PATH` and the Downloads collection, all API 29. Below that, saving needs `WRITE_EXTERNAL_STORAGE`, file paths and a media scan: a second save path with its own bugs. The open decision "minimum OS versions" was waiting for this.
- Decision: `minSdk = 29`. iOS stays at 15.
- Consequences: Phones on Android 9 or older cannot install CrossDrop (a small share of active phones in 2026). One save path, no storage permission. `setRequireOriginal` and `ACCESS_MEDIA_LOCATION` (D-037) are available everywhere.

## D-036: Android files are read and written through file descriptors with dart:ffi
- Date: 2026-11-03
- Status: Accepted
- Context: Android hands out files as content URIs (gallery, Files, share intents). Rule 2 forbids file bytes on platform channels, and the brief asks to stream "without copying the file". `dart:io` cannot wrap a raw descriptor. Opening `/proc/self/fd/N` reopens the file by path, which other apps' providers and FUSE passthrough refuse.
- Decision: Kotlin opens the URI (`ParcelFileDescriptor`, `detachFd`) and passes only the descriptor number. Dart reads and writes it with `pread`, `pwrite`, `ftruncate`, `fsync` and `futimens` through `dart:ffi` (64-bit offset variants on Android). The blocking calls run in one background isolate (`FdWorker`), never on the UI isolate; the hash isolate calls them directly. `ByteSource` (`PathSource` or `FdSource`) flows through the reader, the upload and the hasher. A provider that cannot seek or has no size (some cloud apps) is streamed once into the staging folder by Kotlin. Package `ffi` (Dart team) is added for `calloc`.
- Consequences: No copy for gallery, Files and shared items; the same mechanism serves receiving (D-040). FFI is POSIX-only: its tests run on the Linux CI job and are skipped on Windows. Considered: copying every pick to a temp file (doubles space and time for big videos), a native reader that pushes chunks over a channel (against rule 2).

## D-037: Read Android originals with setRequireOriginal and ACCESS_MEDIA_LOCATION
- Date: 2026-11-03
- Status: Accepted
- Context: Since Android 10, MediaStore strips GPS from images an app reads, unless the app has `ACCESS_MEDIA_LOCATION` and asks for the original. The received file would then differ from the original, and its hash too.
- Decision: Declare `ACCESS_MEDIA_LOCATION` and ask for it with the photo permission (photo_manager `mediaLocation: true`). Open MediaStore items with `MediaStore.setRequireOriginal`. If that is refused, send the redacted file rather than nothing; the channel reports `original: false`.
- Consequences: Photos keep their location, as a user expects of "the original". The user can still remove location in their gallery before sharing.

## D-038: Prepare picked items before the offer; our own iOS exporter
- Date: 2026-11-03
- Status: Accepted
- Context: An iOS library item is not a file; it must be exported, may be in iCloud only, may be converted (D-039), and its exact size is unknown until then. The offer needs exact sizes, and v1 cannot skip a file inside a session. photo_manager's `originFile` exports into its own cache, without cancel, stall detection or a choice of resource.
- Decision:
  - On Send, after the receiver is checked, every picked item is prepared first ("Preparing 3 of 12", with iCloud progress and Cancel). Items that fail are left out with a reason (iCloud, no longer in the library or not shared under Limited access, unreadable); running out of space leaves out the rest. Then the offer is made with exact sizes.
  - iOS: `PHAssetResourceManager.requestData` with network access, written chunk by chunk to `<app support>/crossdrop_outgoing/<batch>/<n>/`, cancellable, failing after 90 s without progress. It exports the current version (edits applied: `fullSizePhoto`/`fullSizeVideo`, else the original resource), named after the original (`IMG_1234.HEIC`, not `FullSizeRender.jpg`).
  - Android: library items are not exported; their content URI is read in place (D-036).
  - Staged files live in Application Support (the OS temp folder may be emptied while a paused send waits), and are deleted when the send ends for good. At launch, batches that no unfinished send uses are deleted.
  - photo_manager stays for permission, Limited access, albums, the grid and thumbnails.
- Consequences: The offer is always exact, and a file that cannot be read never reaches the receiver. A big iOS video briefly needs its size again in free space (as ARCHITECTURE.md already said). Preparing many large iCloud items takes time before anything is sent; streaming while exporting is a later optimisation. Slow-motion videos arrive as the original high-frame-rate file, without the slow-motion ramp (no transcoding in v1).

## D-039: HEIC, Live Photo and video format rules
- Date: 2026-11-03
- Status: Accepted
- Context: The open decisions asked for HEIC and Live Photo defaults. Most Android galleries open HEIC; older ones do not. Android has no Live Photos.
- Decision: Defaults: send the original HEIC, and only the still of a Live Photo. Two settings (Settings > Sending photos to Android, iPhone only, schema 4): convert HEIC to JPEG before sending (ImageIO, quality 0.92, EXIF, GPS, orientation and colour profile kept, HDR gain map lost), and send the Live Photo video as a second file named after the still (`IMG_1234.MOV`), with a shared `livePhotoGroup`. They apply only when the receiver is not an iPhone. HEVC and HDR videos are always sent unchanged; nothing else is transcoded.
- Consequences: Originals by default, with a way out for old galleries. The receiver gets two ordinary files for a Live Photo. Dolby Vision may look washed out on some Androids (documented, not fixed).

## D-040: Android receives straight into a pending MediaStore item
- Date: 2026-11-03
- Status: Accepted
- Context: ARCHITECTURE.md says "insert into MediaStore as a pending item, write directly into it, then publish. No extra copy." Writing to a `.part` file and copying it in at the end would need twice the space for a big video.
- Decision:
  - The receive server stores files through a `ReceivedFileStore` interface. On Android the partial file is the pending item itself, created at the first byte (a declined offer leaves nothing). Photos go to `Pictures/CrossDrop`, videos to `Movies/CrossDrop`, other files to `Download/CrossDrop`.
  - The collection comes from the sanitized name's extension, never from the declared MIME type; a declared kind that contradicts the extension goes to Downloads. If MediaStore refuses the MIME type for the gallery, the item goes to Downloads and the user is told.
  - The item's URI is stored in `tempPath`. Resume, checkpoints, cut-back after a crash and the hash all work through its descriptor. A hash mismatch truncates the item; cancel, failure and the 24-hour cleanup delete it. An item that disappeared starts the file over. At launch, this app's pending items older than 24 hours that no session uses are deleted.
  - When verified, the item is published. `FolderStore` keeps the old behaviour for tests, the dev CLI and iOS.
- Consequences: No copy, no storage permission. Pending items are hidden from other apps until published. Name clashes are resolved by MediaStore ("IMG_1 (1).jpg"). A full disk during a write pauses the session as before.

## D-041: Document pickers: SAF in place on Android, a copy on iOS
- Date: 2026-11-03
- Status: Accepted
- Context: `file_picker` copies every pick into the cache on Android, against "stream without copying". On iOS, keeping security-scoped URLs open across backgrounding, pausing and restarts needs bookmarks and careful access lifetimes. ARCHITECTURE.md said "files arrive as security-scoped URLs".
- Decision: Android uses our own `ACTION_OPEN_DOCUMENT` (multiple, any type) and takes a persistable read grant per URI, released when the send ends. iOS keeps `file_picker` in import mode: iOS hands over a copy (downloading iCloud Drive files first, with its own UI), which is moved out of the temp folder into staging.
- Consequences: Android reads in place, and resumes after a restart. On iOS a picked document costs its size in free space while it is being sent, the same as a library export. The architecture row is updated.

## D-042: Creation dates
- Date: 2026-11-03
- Status: Accepted
- Context: The brief asks to keep the creation date where the platform allows.
- Decision: The sender puts `created` in the offer: the asset's `creationDate` on iOS; `DATE_TAKEN` (else the last modified time) on Android; the file's modification time for documents. The receiver applies it as follows:
  - iOS Photos: `PHAssetCreationRequest.creationDate`.
  - iOS Files: the modification date.
  - Android gallery: `DATE_TAKEN` at insert, and the file time (`futimens`) before publishing.
  - Android Downloads: the file time only.
  - In every case the file's own metadata (EXIF, QuickTime) goes along unchanged.
- Consequences: Photos and videos sort by when they were taken on both phones. Where it cannot be kept: iOS Files has no settable creation date, only the modification date; Android rescans the file when it is published and prefers the file's own metadata, so a PNG screenshot without EXIF may show the time it was received in some galleries; Android Downloads keeps only the modification time; iOS documents picked through the document picker are copies and carry the copy's time.

## D-043: iOS saving: Photos with add-only access, moved; Files as the fallback
- Date: 2026-11-03
- Status: Accepted
- Context: The brief asks to move, not copy, received media into Photos, with add-only permission, and to fall back to Files for formats Photos refuses.
- Decision: `PHAssetCreationRequest` with `shouldMoveFile`, the original name and the creation date. Add-only access is asked when the user accepts an offer with photos or videos (the accept does not wait for the answer). Formats Photos cannot import (WebM, Matroska, AVI, raw HEVC streams, documents) go straight to Files. Anything Photos refuses at save time, and everything if access is denied, goes to the Documents folder (Files > On My iPhone > CrossDrop) with a note on the Receive screen. The app is named CrossDrop on both platforms.
- Consequences: No copy and no read access needed to save. Photos may need temporary space while it imports a large moved file; that is not under our control.

## D-044: Android share target: SEND and SEND_MULTIPLE, singleTask
- Date: 2026-11-03
- Status: Accepted
- Context: Sharing from Gallery or Files should open the Send flow with the files preselected. With the default `singleTop`, a share starts a second CrossDrop activity inside the other app's task: a second engine, database connection and server. `receive_sharing_intent` copies shared files into the cache.
- Decision: Intent filters for `SEND` and `SEND_MULTIPLE` (`*/*`) on `MainActivity`, now `singleTask`, so every share reaches the running instance through `onNewIntent`. Our own small `ShareChannel`. It accepts only `content://` URIs from other apps: a `file://` URI, or one of CrossDrop's own, could make it send private files. It ignores intents redelivered after a configuration change or from Recents. Dart describes the URIs and opens the Send flow on top of whatever is open, so a running receive keeps going. Text-only shares get a message.
- Consequences: Files are read in place through the intent's read grant, which lasts while the process lives; a send of shared files cannot resume after the app was killed ("source unreadable", share again). `singleTask` also means Back from CrossDrop does not return to the sharing app's task.

## D-045: iOS Share Extension hands files to the app through an App Group inbox
- Date: 2026-11-03
- Status: Accepted
- Context: Share extensions have a memory limit of about 120 MB and must not run a transfer. The brief asks for an App Group hand-off.
- Decision:
  - **Extension:** a Share Extension target (UIKit, no Flutter). It loads each item with `loadFileRepresentation`, in its own format, and clones it into `<group>/Inbox/<uuid>/<n>/<name>`; only small image-only items (Markup screenshots) are loaded as data. It writes `manifest.json` last and atomically, then opens `crossdrop://share` through the responder chain. That is not a public API; if it fails, the extension says "Open CrossDrop to send".
  - **App:** checks the inbox at launch, on that URL and on every return to the foreground. It validates the manifest (version, at most 10,000 items, every path inside its share folder, no links, files present), moves the share into staging and opens the Send flow with the files preselected. Shares without a manifest for an hour are deleted.
  - **Setup:** the App Group id is the `APP_GROUP_ID` build setting (`group.com.example.crossdrop`), read from Info.plist at run time. The extension is embedded before Flutter's "Thin Binary" phase, which avoids Xcode's build-cycle error.
  - `receive_sharing_intent` is not used.
- Consequences: The extension stays far below its memory limit for any file size. If a re-signing tool drops or renames the App Group, sharing says it is not available, and the in-app pickers still work. Shared photos are what Photos hands over, which may be a rendered copy rather than the library original; for exact originals use the in-app picker.

## D-046: Home is the receive screen; receiving runs while the app is open
- Date: 2026-11-03
- Status: Accepted (changes D-016 and the server lifetime in D-031)
- Context: Phase 6 asks for a Home screen that shows "Ready to receive" with a Receiving switch. Until now the server ran only while a separate Receive screen was open, so a phone on Home could not be found.
- Decision:
  - `ReceiveHost`, above the navigator, keeps the receive controller alive on every screen once onboarding is done (D-050). Offers open the Incoming request on top of whatever is open.
  - The QR code and addresses move to a "My QR code" screen, which keeps the screen on while open. The server no longer keeps the screen on by itself; running transfers still do.
  - When the app has been hidden for 30 s with no offer waiting and no bytes moving, the server stops and advertising ends. It starts again, on a new port, when the app is shown. A paused session does not keep it running: its sender finds the phone again by id.
  - Because receiving now starts at launch, the server waits for the launch cleanup of expired partial files before it restores sessions, and discarding a received transfer that the server holds goes through the server's cancel.
  - A rename restarts receiving when nothing is in flight, so the new name is advertised.
- Consequences: Other phones on the same Wi-Fi can see this phone whenever CrossDrop is open and Receiving is on, not only on one screen. Untrusted senders still need Accept and the code check, and the switch hides the phone. No protocol or security code changed.

## D-047: Navigation with Navigator and named routes
- Date: 2026-11-03
- Status: Accepted
- Context: The app already used `Navigator`, a route observer and a global navigator key for shares. A routing package (go_router) would add a dependency for about twelve screens and no deep links.
- Decision: Plain `Navigator` with route names in `lib/app/navigation.dart`. The route observer tells the share listener and the offer prompt what is on top, so they do not open duplicates.
- Consequences: No new package. Deep links other than `crossdrop://share` stay out of scope.

## D-048: One transfer view model for both directions
- Date: 2026-11-03
- Status: Accepted
- Context: The sender's state (`SendSnapshot`) and the receiver's (`IncomingSession`, stored sessions) differ, but the Progress, Done, Failed and History screens show the same things.
- Decision: `TransferView` (stage, peer, files, bytes, speed, time left, reason, pairing code, resumable) is built from either. `ProgressView` and `ResultView` are plain widgets that take it.
- Consequences: One set of screens, tested without the engine. A new engine state needs one mapping in `transfer_view.dart`.

## D-049: Failure messages come from one table
- Date: 2026-11-03
- Status: Accepted
- Context: Each screen had its own wording for the same reason codes, and some offered no next step.
- Decision: `failure_messages.dart` maps every reason code to a title, a plain-language reason, the next step from ARCHITECTURE.md's failure table and one button (Resume, Send again, Scan QR code, Other ways to connect, or none). A pin mismatch never offers a retry. Unknown codes show the code, so users can report it.
- Consequences: Wording changes in one place, with unit tests per code.

## D-050: Onboarding first; receiving starts after it
- Date: 2026-11-03
- Status: Accepted
- Context: The brief asks for permissions at the moment they are needed. With D-046, receiving would start at launch and iOS would show its Local Network prompt before anything explained it.
- Decision: Three introduction pages on first launch. Receiving (and so the iOS Local Network prompt) starts when the user taps Get started or Skip, right after the page that explains Local Network. Camera, Photos, add-only Photos and notifications stay where they are used. `settings.onboardingDone`, schema 5, off by default, so phones upgraded from Phase 5 see the pages once. Settings can replay them.
- Consequences: The Local Network prompt on iPhone comes right after onboarding, not at the first Send. A database error shows Home rather than locking the user out.

## D-051: Open received files through our own channel
- Date: 2026-11-03
- Status: Accepted
- Context: The Done screen needs an Open button. `open_filex` opens file paths; received files are MediaStore content URIs on Android and Photos assets (`photos:<id>`) on iPhone.
- Decision: A small `crossdrop/open` channel. Android starts `ACTION_VIEW` with a read grant, for `content://media/...` URIs only. iOS opens the Photos app for `photos:<id>` (through the undocumented `photos-redirect://` scheme; there is no public way to show one asset) and previews a file inside Documents with Quick Look. Anything else is refused.
- Consequences: No new package. "Open Photos" opens the library, not the photo. If the scheme stops working, the button falls back to "Saved to Photos".

## D-052: Send picks files first, then the phone
- Date: 2026-11-03
- Status: Accepted
- Context: Phase 5 opened the nearby list first. The brief's Send screen shows the selected files, their size and a Send button, and shares from other apps arrive with files already chosen.
- Decision: Home > Send shows the pickers and the selection; Send opens the nearby list, which returns the chosen phone; the transfer screen takes over (preparing, code, progress, result). Sizes: documents and Android shares carry the size the platform reports; photos and videos only get a size when they are prepared (they may be in iCloud or converted), so the total says "at least" until sending starts.
- Consequences: One way into sending, shared with the share sheet. The exact total appears on the Progress screen.

## D-053: The sender can pause
- Date: 2026-11-03
- Status: Accepted
- Context: The brief asks for Pause on the Progress screen. The engine already pauses after the current chunk when iOS backgrounds the app, and resumes from the receiver's `receivedBytes`.
- Decision: Pause on the sender uses that same engine pause. A user pause is remembered, so returning to the foreground does not resume it, and the app going to the background does not pause it twice. The receiver has no Pause: it cannot stop the sender without the protocol, and Cancel covers it.
- Consequences: No protocol change. While paused, the receiver shows "Waiting for the sender to reconnect". After 24 hours the paused session expires as before.

## D-054: Android hotspot: LocalOnlyHotspot, owned by its screen
- Date: 2026-11-03
- Status: Accepted
- Context: Scenario 4 needs the Android phone to make a network the iPhone joins, with one QR code. `WifiManager.startLocalOnlyHotspot` (API 26) gives a random name and password and no internet. `startLocalOnlyHotspotWithConfiguration` exists only from API 36. The hotspot's address has no public API.
- Decision:
  - Use `startLocalOnlyHotspot`. Read the network from `getSoftApConfiguration()` (API 30+; name from `getWifiSsid()` on 33+) or `getWifiConfiguration()` (API 29). Refuse open and OWE networks.
  - Permissions, asked when the user taps Start: `NEARBY_WIFI_DEVICES` with `neverForLocation` on 13+; `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION`, capped at SDK 32, on 10–12. Location services off on 10–12 is its own error.
  - Find the address by comparing the address list before and after the start (`pickHotspotAddress`), waiting up to 10 s.
  - The hotspot belongs to the hotspot screen: leaving stops it (with a question if a transfer runs), and it stops 60 s after the last transfer, with Keep on.
  - The QR code gains optional `ws`, `wp`, `wsec`. A second, standard `WIFI:` code is shown for the iPhone Camera app.
- Consequences: No new package. Phones that cannot run a hotspot and Wi-Fi together lose their Wi-Fi while the hotspot is on. Unknown interface names fall back to "any new local address".

## D-055: iPhone joins with NEHotspotConfiguration when the build can, Settings otherwise
- Date: 2026-11-03
- Status: Accepted
- Context: Joining a network from an app needs the Hotspot Configuration capability. Apple's "Supported capabilities (iOS)" table gives Hotspot to Apple Developer Program and Enterprise members only; free Apple IDs, which the CI builds use (D-017), cannot have it. `joinOnce = true` drops the network after 15 s in the background or when the device sleeps.
- Decision:
  - Join with `NEHotspotConfigurationManager.apply`, `joinOnce = false`. CrossDrop removes the network it added 60 s after the last transfer, or 10 minutes after joining without a transfer, and removes older CrossDrop networks before a new join.
  - Before joining, a 1.5 s connect to the receiver: if it answers, the iPhone is already on that network. No `fetchCurrent`, which needs another paid capability or location.
  - The app reads its own embedded provisioning profile to know whether it has the entitlement. Without it, or when iOS answers `internal`, the user joins in Settings with the name and a Copy password button, and the app checks every 2 s until the receiver answers.
  - `Runner.entitlements` stays free-account safe; `RunnerHotspot.entitlements` adds the capability for paid-account builds.
- Consequences: The CI build works today through Settings. In-app join needs a paid account, an App ID with Hotspot enabled and the other entitlements file; nothing else changes.

## D-056: Android binds the whole process to a Wi-Fi without internet
- Date: 2026-11-03
- Status: Accepted
- Context: On a Wi-Fi without internet, Android keeps mobile data as the default network, so new sockets go over mobile data. Android recommends `Network.getSocketFactory()`, but `dart:io` creates its own sockets.
- Decision: `ConnectivityManager.bindProcessToNetwork(wifi)` when Wi-Fi is connected, not validated and not the default; clear it otherwise, and at once when the Wi-Fi is lost. The rule (`shouldBindToWifi`) is in Dart; Kotlin reports Wi-Fi and default-network changes.
- Consequences: Every socket CrossDrop opens afterwards uses the Wi-Fi. CrossDrop makes no calls outside the local network, so nothing else is affected. A VPN that is the default is left alone.

## D-057: The Personal Hotspot guide checks prefixes, not names
- Date: 2026-11-03
- Status: Accepted
- Context: Apps cannot turn on Personal Hotspot or read the Wi-Fi name without extra capabilities or location. The guide should still say when the phones are on the same network.
- Decision: The platform channels list IPv4 addresses with prefix lengths (`java.net.NetworkInterface` on Android, `getifaddrs` on iOS). The guide marks "hotspot on" (iPhone, `bridge*` in 172.20.10.0/28) and "joined" (Android, `wlan*` in that range) as hints, and says the phones share a network when a discovered phone's address is in one of this phone's subnets.
- Consequences: No permission. If iOS changes the hotspot range, only the hints stop; the same-network check keeps working.

## D-058: Benchmark builds: a release-mode flag, and benchmark files are discarded after verification
- Date: 2026-11-03
- Status: Accepted
- Context: The brief asked for benchmark mode in debug builds only. Flutter debug builds run Dart without full compilation and are several times slower, so their numbers are useless (BENCHMARKS.md already requires release). Hundreds of test files up to 2 GB would fill the receiver's gallery or Downloads. The Phase 7 plan proposed an optional `purpose` field in the offer for that.
- Decision:
  - Benchmark mode exists only with `--dart-define=CROSSDROP_BENCH=true`, on a release build. The flag is a `const bool`, so normal builds compile it out. CI has a `bench` input that makes `*-bench*` artifacts.
  - Instead of a protocol field, benchmark builds wrap the file store: a file named `crossdrop-bench-<size>-<runId>.bin` is received and verified like any other, then deleted instead of saved. Normal builds save it like any file. No protocol change.
  - CPU time comes from `getrusage` through `dart:ffi` (Android, iOS, Linux); memory from `ProcessInfo.currentRss`. Both phones write CSV rows that join on the run id.
- Consequences: The numbers are release numbers. A benchmark build must never reach users; the Settings entry says "test build".

## D-059: One stream per transfer until the benchmark shows a clear gain
- Date: 2026-11-03
- Status: Superseded by D-068 (2026-11-08)
- Context: Parallel streams can help on lossy or high-latency links, but cost complexity in resume, hashing and the receiver.
- Decision: Keep one TLS connection and one file at a time. Consider parallel streams only if the Phase 7 benchmark shows a single stream clearly below the link's capacity while neither phone's CPU is the limit: CPU well under one core, and MB/s well under an iperf3 baseline on the same network. The measurements come first, then a proposal.
- Consequences: Nothing changes now.

## D-060: No LocalSend compatibility in v1
- Date: 2026-11-03
- Status: Accepted
- Context: ARCHITECTURE.md left open whether to use the LocalSend protocol, so CrossDrop could talk to LocalSend users. Phases 1–7 built the custom protocol, including mutual pinned TLS, the signed sender challenge, resume by offset and the 6-digit code, and all of it is unit-tested.
- Decision: v1 keeps the custom protocol. LocalSend compatibility can be looked at again after v1 passes its device tests, as a separate adapter. It must not weaken the pinning rules.
- Consequences: CrossDrop does not see LocalSend devices. The open decision in ARCHITECTURE.md is closed.

## D-061: The auth commitment covers both fingerprints; protocol version 2
- Date: 2026-11-03
- Status: Accepted
- Context: The code review of 2026-11-03 (H1) found that the v1 commitment `SHA-256("crossdrop-commit-v1\n" + senderNonce)` fixed only the sender's nonce. The certificate arrived at `/v1/auth`, after the receiver's nonce was known, and the fingerprint is the SHA-256 of the whole DER, so any changed byte gives a new fingerprint for the same key. A man in the middle posing as the receiver to the sender and as a sender to the real receiver learns the sender's code first, then tries about 10^6 certificate variants until the real receiver's code matches. That takes under a second, well inside the 60 s challenge lifetime. D-029's claim of "one chance in a million per attempt" did not hold.
- Decision:
  - `commit = SHA-256("crossdrop-commit-v2\n" + receiverFp + "\n" + senderFp + "\n" + senderNonce)`. The receiver recomputes it with its own fingerprint and the fingerprint of the certificate it receives, and refuses any other certificate with `auth_failed`. Including `receiverFp` costs nothing and also binds the commitment to the pinned receiver.
  - The wire protocol becomes version 2 (`GET /v1/info` `versions`, TXT `v`, QR `v`, offer `protocol`); version 1 is not supported at all, because a receiver that still accepted v1 commitments would leave the attack open. URL paths stay under `/v1`.
  - Not done: checking the certificate's self-signature. It would not help: an attacker can re-sign the same key as often as it likes.
- Consequences: Each man-in-the-middle attempt is again one chance in a million, and failures show as codes that differ. Builds from before this change show the other phone as "needs update" and a QR code from them as "Update CrossDrop", instead of failing at authentication. D-029 stays in force for the code formula.

## D-062: A paused received session holds the keep-alive and the server for 150 s
- Date: 2026-11-03
- Status: Accepted
- Context: The code review (M3, L6) found that a paused received session kept the wake lock and the Android foreground service for good, and kept the server up with Receiving off. Releasing them at the first pause is worse: a Wi-Fi drop of a second would let an iPhone receiver whose auto-lock time has passed lock at once and be suspended, ending the transfer that the sender was about to resume.
- Decision: a session that was moving bytes and pauses stays held for 150 s (the sender's retry deadline of about 2 minutes, D-019, plus a margin), then releases the keep-alive and stops counting for the server's lifetime. Any new upload holds it again. A session restored as paused is not held. The policy is a small pure class, `SessionKeepAlive`, tested with fake timers.
- Consequences: after a sender goes to the background or gives up, the receiver's screen may sleep and its server may stop 150 s later (30 s more if hidden). The sender then finds it again by device id when both are open.

## D-063: App id under the owner's GitHub namespace; no debug-signed release builds; all rights reserved
- Date: 2026-11-03
- Status: Accepted
- Context: The code review listed release blockers: the app id was still `com.example.crossdrop` on Android and iOS, Android release builds were signed with the debug key, there was no LICENSE, and the pubspec description was the template's.
- Decision:
  - The id is `io.github.shreyashjunje.crossdrop` (iOS extension `.ShareExtension`, App Group `group.io.github.shreyashjunje.crossdrop`): a reverse-DNS name under a domain the owner controls (their GitHub Pages namespace), without buying a domain. The Kotlin package moved with the Android namespace.
  - Android release builds take the key from `android/key.properties` or `CROSSDROP_KEYSTORE_*` variables (CI secrets). Without a key a release build fails with a clear message; `CROSSDROP_ALLOW_DEBUG_SIGNING=true` marks a test build that may use the debug key. CI does that only while the repository has no key secrets, and names the APK `*-debugsigned`.
  - LICENSE says all rights reserved. Choosing an open-source licence is the owner's call before any public source release; this keeps every option open.
- Consequences: test phones get the new id as a separate app (uninstall the old one once). Losing the release key means no updates under this id, so it must be backed up. Steps are in RELEASE.md.

## D-064: The receiver reads ahead of the disk, up to 8 MB
- Date: 2026-11-03
- Status: Accepted
- Context: The code review (speed) found the receive loop serial: inside one `await for` it wrote 1 MB, handed it to the hasher and, every 4 MB, fsynced and wrote the database. While any of these was awaited the body stream was paused, the TCP window filled and the sender stalled. Disk and network never overlapped.
- Decision: the request body is read into a queue that a writer loop empties in about 1 MB writes. Reading pauses at 8 MB queued and resumes at 4 MB. The size limit is checked as bytes arrive (hard rule 6); a stalled or dropped client still keeps every byte that arrived; `checkpointAll` wakes an idle writer so it saves progress even with less than 1 MB queued. When the server closes, the writer stops after its current write and checkpoints it, so no writer outlives `close()`; the sender sends the queued rest again.
- Consequences: up to 8 MB more memory per running upload (one at a time per session, eight sessions at most), still bounded and still streamed (hard rule 1). The gain is measured in the Phase 7 benchmark; a test shows the socket is read while a write is stuck, and that the queue stays bounded.

## D-065: Checkpoint every 2 s or 64 MB, not every 4 MB
- Date: 2026-11-03
- Status: Accepted
- Context: D-022 fsynced the part file and wrote the database every 4 MB. The code review (speed item 3) pointed out that fsync plus a SQLite write that often is costly on phone flash and through Android's FUSE layer, and with D-064 it still competes with the writer for the disk.
- Decision: the mechanism of D-022 stays (fsync first, then store the byte count; restore cuts the part back). A running upload is checkpointed after 64 MB or 2 s, whichever comes first, and whenever it stops (drop, stall, pause, `checkpointAll` when iOS backgrounds the app). Both are `ReceiveServer.start` parameters, so the benchmark can compare.
- Consequences: after a crash or a kill, about 2 s of data is sent again instead of at most 4 MB; on a fast link that is more bytes, but it costs seconds, and drops (not crashes) still checkpoint at the exact byte. The `progress` event comes at the same pace.

## D-066: Measure each phone's limits first; the bigger speed changes wait for numbers
- Date: 2026-11-03
- Status: Accepted
- Context: The code review listed ten speed items in order of expected gain, starting with "measure first" (bench-only "TLS off" and "hash off" toggles and an iperf3 baseline). Items 2–5 (receiver read-ahead D-064, fewer checkpoints D-065, sender read-ahead, fewer copies in `FdFile`) are safe without numbers and are done. The rest change the protocol, native code or the transfer model.
- Decision:
  - **Measuring:** no TLS-off or hash-off transfer mode, not even in benchmark builds: a plain-HTTP or unverified path in the code is a downgrade waiting to happen (hard rule 4). Instead, Settings > Benchmark > "Measure this phone" times SHA-256, pinned TLS 1.3 on loopback and writes through the receive store, each on its own (BENCHMARKS.md, Step 0). With Step A/B and iperf3 that separates the costs the toggles would have.
  - **Native SHA-256** (CommonCrypto on iOS through FFI; on Android a small C SHA-256 with ARMv8 crypto instructions, built with the app): only if Step 0 shows `sha256` within 1.5× of a measured transfer on a test phone. It adds a native build to both platforms and must be tested on devices.
  - **Overlapping files** (PUT of file N+1 on a second connection while N completes): only if a series of many small files is clearly slower per byte than one large file (below about 70 %). It changes transfer rule 4 (one file at a time, one connection).
  - **Streaming the iOS export** (offer and upload while PhotoKit still exports): only if preparing large videos is a large share of the total time on the test iPhone. It needs the size before the export ends and native work on a Mac.
  - **Wi-Fi Direct on 5 GHz** instead of LocalOnlyHotspot: an experiment for the Android hotspot series, not a v1 change. The Personal Hotspot guide already tells users to turn on "Maximize Compatibility" (2.4 GHz, slower) only if the Android cannot see the network.
  - **Parallel streams:** D-059 stands; they come last.
- Consequences: the next speed work is chosen from measurements on the two test phones, and each change gets a before and after row in BENCHMARKS.md.


## D-067: Import from an iPhone by cable through its camera interface, on Android
- Date: 2026-11-08
- Status: Accepted
- Context: The owner asked for USB-C cable transfers, with photos shown the way a gallery shows them. Plugging an iPhone into an Android phone already works in Android's file manager, but it shows `DCIM/100APPLE`-style folders of HEIC, AAE and Live Photo MOV files, often without thumbnails, so choosing is hard. The options were: (a) the iPhone's camera interface (PTP) with Android as USB host, through the public `android.mtp.MtpDevice` API; (b) Apple's private USB multiplexing protocol (usbmux) implemented in Kotlin, which would allow both directions and any file through our own protocol, but is undocumented, large and could break with an iOS update; (c) Android USB tethering seen by the iPhone as Ethernet, which depends on the brand and works only on USB-C iPhones; (d) the iPhone 15+ as host reading the Android as a camera, which only covers photos Android → iPhone; (e) Apple's External Accessory framework, which needs MFi hardware.
- Decision:
  - Build (a): iPhone → Android only, camera roll only, no iPhone app. It uses only public Android API, works with USB-C and Lightning iPhones, and solves the problem the owner reported. Out of v1 scope in CLAUDE.md; added at the owner's request (2026-11-08).
  - Only Apple devices (vendor `0x05AC`) with a still-image interface are offered. Other cameras would work technically but are not tested.
  - Copies go into pending MediaStore items like received files (D-040), in 1 MB partial reads that never ask for more than the declared size (hard rules 1 and 6). Devices that refuse partial reads, and files of 4 GB or more, are copied whole and size-checked afterwards; for those, more bytes than declared are only caught after the file (the free-space check of the whole selection plus 200 MB bounds the harm). There is no hash: PTP offers none; the size check and the USB link's own CRC are what we have.
  - Grid: one roll, newest first, grouped by day; Live Photos and edited photos are one tile. By default only the still of a Live Photo and only the edited version of an edited photo are copied, as in Photos and with the Live Photo setting of D-039; both can be added from the menu.
  - No new package, no network use, no TLS: the cable is a direct link, and access needs the user's Allow on the iPhone and USB permission on Android.
  - (b) stays the route to Android → iPhone by cable if it is ever needed; it would carry the existing HTTPS protocol over a loopback port so the Dart core stays the same.
- Consequences: the feature is Android-only, one direction. Albums and non-camera-roll files are not reachable. The iPhone's "Transfer to Mac or PC" setting decides whether files are converted, and the screen tells the user to pick "Keep Originals". Partial-read support and the busy case with the Files app must be checked on devices (DEVICE_TESTS.md, "Cable import").

## D-068: Send screen fixes: real names, previews, faster picking, three files at once
- Date: 2026-11-08
- Status: Accepted
- Context: The owner tested on phones and reported four problems: picked files showed generic names instead of their own; there were no previews, so picked photos could not be told apart; the photo picker and the "Preparing" step were slow; files went strictly one after another. They also worried that files lost quality, because the sizes they saw looked smaller. They asked for all of it to be fixed, with the decisions taken by Claude.
- Decision:
  - **Names:** the iOS picker returns only ids. The Send screen now looks up the library's file names for the whole selection in one call to the existing ExportChannel `describe` (PHAssetResource names, no export). A pick without a name shows its kind and the time it was taken, never a blank.
  - **Previews:** a ThumbnailLoader interface (hard rule 9) with two sources. Library items use photo_manager thumbnails, which the OS caches. A receiving iPhone without read access to Photos shows the kind icon and is never asked for access just to draw a preview. Files and content URIs use a new crossdrop/thumbnail channel: Android ContentResolver.loadThumbnail, falling back to a sampled decode or a video frame; iOS QLThumbnailGenerator. Only the path of a small cached JPEG crosses the channel, never file bytes (hard rule 2). The cache is keyed by reference, size and date, kept under 48 MB on Android, and lives in Caches on iOS. References are never logged (hard rule 7).
  - **One preview queue:** the cable-import thumbnail queue (D-067) became generic. Picker grid: six at a time. Rows: three at a time. The newest request goes first, and a tile that leaves the screen before its turn is dropped. Before this, every tile the user scrolled past still queued a native request ahead of the visible ones, which was the main reason the grid felt slow.
  - **Picker loading:** "All photos" and a first page of 60 load before the other albums, which need one count query each.
  - **Preparing:** three items at once, keeping the pick order. Running out of space still skips every item not started yet; items already running finish. The size check of every file before the offer runs four at a time.
  - **Parallel files, superseding D-059:** the owner asked for this directly. D-059 was right that parallel streams cost complexity, but its premise was large files on one fast link. With many photos, most of the time goes to per-file round trips (status, upload, verify, hash wait), not to bandwidth. Running three files side by side hides that wait. The design:
    - The receiver advertises `uploadSlots` in /v1/info (3, `ReceiveServer.maxParallelUploads`). A PUT beyond it gets 503 `busy`. A missing field means 1, so an older receiver gets exactly the old behavior, and no protocol version bump is needed.
    - The sender runs min(3, uploadSlots) lanes, each on its own TLS connection pinned to the same fingerprint, reusing the session's token. Each lane takes the next file in offer order.
    - The receiver keeps a running hash for every file being uploaded and drops only idle files' hashes. So review M2's bound still holds: at most one isolate per running upload.
    - The first lane to reach a session outcome (a cancel, no space, the network giving up, the session lost, an unreadable source) stops the others with that outcome. Resume works as before: each file continues from its own receivedBytes.
    - Pause waits for every running upload to stop. Resume restarts all lanes.
    - Lanes that fail together look up the receiver's address and reopen the event socket only once.
  - **Quality:** nothing changed in the bytes; originals were already sent unchanged and checked with SHA-256. The size the owner saw differ is most likely rounding: we show 10^6-byte MB, while some galleries use 1024-based units. The Done screen now says "Original quality" and shows each file's exact byte count. The HEIC to JPEG setting now opens with its quality cost.
- Consequences:
  - Memory per lane is about two 1 MB chunks on the sender and an 8 MB read-ahead queue on the receiver, so 3 lanes stay under about 30 MB.
  - A large video sent next to photos shares the link with them; total throughput should be about the same.
  - Benchmarks should compare `parallelUploads` 1 and 3, with many small photos and with one large video, on both phones (BENCHMARKS.md). The slot count is one constant on each side if the numbers say otherwise.
  - Device checks N-1 to N-8 in DEVICE_TESTS.md, "Send screen fixes".

## D-069: Redesign on the Night Signal system
- Date: 2026-11-09
- Status: Accepted
- Context: The owner asked for a full redesign: professional, a few memorable moments, easy for non-technical people, one design system. The app used a teal Material seed theme with default widgets. The design was done as a canvas (brief, design system, every screen and state, flow map, UX decisions): https://claude.ai/artifact/XFq5LdCYi7ZoctsNEPLia6. The owner approved direction A, "Night Signal", and the build plan.
- Decision:
  - **Tokens:** one `CdColors` theme extension (dark and light), plus spacing, radius, motion and type tokens in `lib/app/tokens.dart`. Dark is the reference: ground #0E1116, one accent #C8F25A, always with dark text on it. Flat surfaces, 1 px borders, depth through surface tone, no shadows or gradients.
  - **Accent in light mode:** lime stays the fill (primary buttons, switch track, navigation indicator, `primaryContainer`) with dark text. Lime on a light background is too faint for text, icons or thin indicators, so in light mode `ColorScheme.primary` is the dark "accent ink" #4A6600 and progress indicators use it too. In dark mode both are lime.
  - **Status colours differ in lightness**, not just hue (dark: accent 0.77, warning 0.55, danger 0.37 relative luminance), and always come with an icon and a word.
  - **Fonts bundled as assets:** Space Grotesk (variable, weight set through `FontVariation`) for headings and big numbers, Inter (static 400, 500, 600) for the rest, both OFL, licences registered with `LicenseRegistry`. Not the `google_fonts` package: it downloads fonts at runtime, which hard rule 8 forbids. All numbers use tabular figures; both fonts have them.
  - **Haptics** for device found, lock-on, accepted, done and failed, behind a Dart interface. Success and error need a small native call (Flutter only ships impact and selection feedback).
  - **Flow changes (owner approved):** tapping a phone on the radar sends (no extra Send button); the code check lives inside Incoming and the sender's waiting sheet instead of a separate screen; sharing from another app opens straight on the radar; "Trust this device" is off by default; History gets All, Sent, Received and Unfinished filters.
  - **Motion** is 150 to 300 ms, and every loop stops under the system "reduce motion" setting (`MediaQuery.disableAnimations`). The radar falls back to a plain list at large text sizes and with a screen reader.
- Consequences: Every screen is rebuilt in small steps, one commit each, with the existing widget and accessibility tests kept passing. The benchmark screen keeps plain styling. Fonts add about 1.4 MB to the app. The contrast of every token pair is checked by a unit test; how the design feels, haptics and reduce motion can only be confirmed on phones (DEVICE_TESTS.md, "Redesign").

## D-070: Follow-up to the security audit of 2026-11-03 (S2, S7 to S10, S13)
- Date: 2026-11-09
- Status: Accepted
- Context: The audit of commit `c412bf1` left six Low or Medium findings open after S1 and S3 to S6 were fixed.
- Decision:
  - **S2, spoofed advert:** another mDNS service that claims a listed device id with a different fingerprint hint is ignored. The first-seen entry stays until it is lost or does not answer. Not done: listing both with a warning; the existing look-alike check stays the UI guard.
  - **S7, iOS backups:** `crossdrop_incoming` and `crossdrop_outgoing` are excluded from backup (`isExcludedFromBackup`) when the app first resolves its folders. Android already has backup off in its manifest.
  - **S8, foreign networks:** the receive server answers 403 `not_local` to any address that is neither loopback nor on a subnet of one of the phone's interfaces (the `crossdrop/network` `interfaces` channel). If the platform lists no usable address, requests pass: a platform gap must not block every transfer. Routed multi-subnet LANs no longer work; QR and hotspot remain.
  - **S9, client limits:** JSON replies over 1 MB fail as `bad_response`; an event message over 64 KB closes the event socket.
  - **S10, CI:** every action is pinned to a commit SHA, the workflow token is read-only, and Dependabot proposes action updates monthly.
  - **S13, code display:** the sender hides the pairing code only when the receiver says it trusts this phone and this phone trusts the receiver too.
- Consequences: S11 and S12 stay accepted as before. S7 and S8 depend on native behaviour and are only confirmed on phones (DEVICE_TESTS.md, "Audit follow-up").

## D-071: Data lanes, upload workers, stripes and the tree hash
- Date: 2026-11-10
- Status: Accepted (built and unit-tested; not yet run on phones)
- Context: The owner reported that transfers between the two phones are very slow and that files seem to get smaller. D-066 had put the larger speed changes on hold until there were numbers. There were none from phones, so the engine was measured on the owner's PC (12 threads, AOT, loopback, no radio):
  - pure-Dart SHA-256 in an isolate: about 135 MB/s alone, about 75 MB/s while a transfer runs;
  - dart:io TLS 1.3, one stream: about 90 MB/s; two to four streams in the **same** isolate: about 125 MB/s together; one isolate per stream: 72, 131, 167 and 201 MB/s for 1 to 4;
  - a real 1 GB transfer between two CLI processes: about 60 MB/s, with both main isolates busy the whole time.
  So the app itself, not Wi-Fi, set the ceiling on a good link: all TLS data moved through one isolate per phone (dart:io does it in 8 KB steps, each a round trip through the event loop), that isolate also draws the UI, and the three lanes of D-068 shared it. Once that was lifted, one SHA-256 over the file was the next limit.
  On size: the same 1 GB file arrived with the same byte count and SHA-256. Nothing in the transfer path changes a byte.
- Decision:
  - **Data lanes** on the receiver: three isolates, each an HTTPS listener on its own port with the same certificate, that take only `PUT`, decrypt, and forward the body to the unchanged handler on the main isolate with a 2 MB window. Every check, the part file, the checkpoints and the events stay where they were. Advertised as `dataPorts`.
  - **Upload workers** on the sender: an upload of 8 MB or more runs `UploadClient.put` in its own isolate with its own pinned connection and the session's token. Smaller files stay on the main port: an isolate and a handshake cost more than they save on a photo.
  - **Stripes:** from 32 MB a file goes over up to three connections in 1 MB blocks, put back in order by the receiver. Chosen over byte ranges written out of order because the part file stays append-only: resume, the checkpoint rule (D-022, D-065) and the size check (hard rule 6) did not have to change. Only one large file at a time is striped; several large files side by side already use a connection each.
  - **Tree hash:** SHA-256 over the SHA-256 of each 1 MB leaf, hashed on up to three isolates. Still SHA-256, still changes with any bit, and pure Dart, so it runs and is tested the same on both platforms. Not chosen: native SHA-256 (CommonCrypto would be easy on iOS, but Android has no public system library, so the Android phone would still limit every transfer, and it could not be tested on the PC); a faster non-cryptographic hash (weaker promise).
  - **Negotiation:** all of it through new fields in `/v1/info` (`dataPorts`, `stripes`, `treeHash`). No protocol version bump: an older sender or receiver gets exactly the old path. If the data ports stop answering while the main port works, the sender falls back to the main port.
  - **Not done:** refreshing the data ports after the receiver restarts mid-session (the fallback covers it); native TLS; anything for the radio link (see Consequences).
- Consequences:
  - Same PC, same 1 GB file: about 110 to 130 MB/s instead of 60, with sender and receiver sharing one CPU. Two phones each do half of that work, so the gain there may differ and must be measured (BENCHMARKS.md).
  - This raises the app's own ceiling. It does nothing for a slow link: on 2.4 GHz Wi-Fi (many routers, most phone hotspots) a few MB/s is all the radio gives, and through a router every byte crosses the air twice.
  - More isolates while a large file moves: three lanes (always there, idle otherwise) and up to three hash workers on the receiver, three upload workers and three hash workers on the sender. Memory per large upload stays bounded: about 20 MB on the receiver (8 MB queue, 2 MB per lane window, 2 MB per stripe), about 2 MB per worker on the sender.
  - The stored `sha256` of a received file is the tree root when the sender used the tree hash.
  - `CLAUDE.md` still says "SHA-256 ... sent in /complete" and one connection per session in its summary; ARCHITECTURE.md is the reference.
  - On Android, upload workers and hash workers read content URIs with blocking `pread` on the descriptor. That path only runs on Linux in CI and on phones, not on the Windows PC.
  - Device checks F-1 to F-6 in DEVICE_TESTS.md, "Faster transfers".
