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
- Status: Accepted
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
- Status: Accepted (temporary; superseded when Phase 4 lands)
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
- Status: Accepted (revisit with the Accept prompt and Phase 4)
- Context: Offers are still accepted automatically (D-011), so advertising whenever the app is open would let anyone on the Wi-Fi push files. Phase 4 brings the persistent certificate. Until then the server creates a certificate at each launch.
- Decision: The server and the advertisement run only while the Receive screen is open. TXT `fp` and the QR `fp` use the real fingerprint of the current per-launch certificate, not a placeholder. Nothing checks it yet.
- Consequences: The formats are final, and Phase 4 only has to start checking the fingerprint. Receiving requires opening Receive first. The fingerprint, port and QR code change at each launch.
