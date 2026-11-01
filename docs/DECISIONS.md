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
