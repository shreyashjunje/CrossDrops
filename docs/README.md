# Docs

- [ARCHITECTURE.md](ARCHITECTURE.md): full v1 design: scope, connection modes, protocol, security, platform modules, failure handling.
- [DECISIONS.md](DECISIONS.md): log of key design decisions and why they were made.
- [CHANGELOG.md](CHANGELOG.md): notable changes to the project and docs.
- [DEVICE_TESTS.md](DEVICE_TESTS.md): acceptance checks that need real iPhone and Android phones.
- [BENCHMARKS.md](BENCHMARKS.md): measured transfer speeds on real devices.
- [features/](features/): one doc per feature, written from [features/_TEMPLATE.md](features/_TEMPLATE.md).
  - [file-transfer-poc.md](features/file-transfer-poc.md): Phase 1 proof of concept, HTTPS server and streaming client with resume and SHA-256 check.
  - [discovery.md](features/discovery.md): Phase 2 Bonjour discovery, nearby list, device identity, iOS Local Network permission, network changes.
  - [qr-connect.md](features/qr-connect.md): Phase 2 QR code and manual address fallback, strict payload parsing.
  - [transfer-engine.md](features/transfer-engine.md): Phase 3 session flow, Accept prompt, send queue, events, cancel, safety limits.
  - [resume.md](features/resume.md): Phase 3 resume after drops and restarts, checkpoints, backoff, 24-hour cleanup.
  - [keep-alive.md](features/keep-alive.md): Phase 3 screen on, Android foreground service, iOS background task.
  - [device-identity.md](features/device-identity.md): Phase 4 key pair and certificate, Keychain / Keystore storage, fingerprint as identity, reinstall.
  - [pairing-and-trust.md](features/pairing-and-trust.md): Phase 4 pinned TLS, sender authentication, 6-digit code, trusted devices, auto-accept, lookalike warnings.
  - [abuse-limits.md](features/abuse-limits.md): Phase 4 Receiving switch, rate limits, request limits, server lifetime.
- [TODAY-2026-11-02.md](TODAY-2026-11-02.md): short list of what was built, tested and left open on day one.
