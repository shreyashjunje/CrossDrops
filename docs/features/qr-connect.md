# Feature: QR code and manual address connect

- Phase: 2
- Status: Built, awaiting device tests
- Last updated: 2026-11-02

## Summary

Some Wi-Fi networks block Bonjour, or discovery fails for another reason. For those cases the receiver shows a QR code with everything needed to connect, and the sender scans it with the camera. A typed IP and port is the last fallback. Each path checks who answers before opening Send.

## Scope

**In scope**

- QR code on the Receive screen: `crossdrop://connect?v=1&ip=...&port=...&fp=...&id=...&n=...` ([ARCHITECTURE.md](../ARCHITECTURE.md), "QR code payload").
- QR scanner with camera permission handling on both platforms.
- Strict payload parsing that refuses malformed and hostile codes.
- Manual IP and port entry.
- Redrawing the QR code when the Wi-Fi or IP changes.

**Out of scope** (and which phase picks it up)

- Pinning the TLS connection to the QR fingerprint (Phase 4). The fingerprint is parsed, validated and carried in `ConnectTarget.fingerprint`, marked `TODO(phase4)`.
- Wi-Fi name and password in the QR code for Android hotspot mode (hotspot phase). Unknown parameters are already ignored, so adding them later will not break older apps.
- A "connect timed out, try hotspot mode" flow with a hotspot button (hotspot phase). For now the message only suggests a hotspot.

## Design

- **Which address goes in the code:** the Wi-Fi client interface (`wlan*`, `en0`), then a hotspot interface (`swlan*`, `ap*`, `bridge*`), then any other address in a local range. Mobile data and VPN interfaces never appear. If there is no such address, Receive shows "No Wi-Fi or hotspot address" instead of a code.
- **Fingerprint:** the full SHA-256 of the receiver's current certificate. It is created at each launch until Phase 4 (D-016).
- **The code is drawn on white** so it scans in dark mode, and it is never logged (CLAUDE.md rule 7).
- **Parsing** (`ConnectPayload.parse`) refuses:
  - anything over 1024 characters
  - whitespace or control characters
  - a scheme other than `crossdrop` or a host other than `connect`, including look-alike Unicode hosts
  - user info, a port in the authority, an extra path or a fragment
  - stray or truncated `%` escapes and invalid UTF-8
  - missing or repeated parameters
  - `v` other than 1, reported separately as "update CrossDrop"
  - `ip` that is not a dotted IPv4 literal in 10/8, 172.16/12, 192.168/16, 169.254/16 or 100.64/10. Hostnames are never resolved, and leading zeros, hex and short forms are refused.
  - `port` that is not plain digits in 1–65535
  - `fp` that is not 64 hex characters, or `id` that is not a UUID
  - `n` that is empty after sanitizing

  Error messages never include the payload.
- **After a scan:** `checkPeer` calls `GET /v1/info` and requires the id from the code. A different device answering gives "This isn't the device you scanned". No answer gives "This Wi-Fi may block phone-to-phone traffic, or a VPN is on. Try a hotspot."
- **Manual entry:**
  - The same IPv4 local-range rule applies, and the port must be 1–65535 in plain digits.
  - There is no expected id, so any CrossDrop device answering at that address is accepted. Its name is shown on Send.
  - Phase 4 will require the 6-digit code for this path.
- **Camera permission:** `mobile_scanner` asks on first use. If the user refuses, the scanner explains why the camera is needed and offers Open Settings.

## Code

| Path | Purpose |
| --- | --- |
| `lib/core/protocol/connect_payload.dart` | `ConnectPayload` build and strict parse, IPv4 helpers |
| `lib/core/discovery/network_monitor.dart` | `pickQrAddress`, network change events |
| `lib/features/receive/receive_controller.dart`, `receive_screen.dart` | QR payload and display |
| `lib/features/nearby/qr_scan_screen.dart` | Scanner, camera permission errors |
| `lib/features/nearby/manual_address_dialog.dart` | Typed IP and port, validators |
| `lib/core/client/peer_check.dart` | Check before Send |

## Protocol and API

QR payload v1, all parameters required, each exactly once:

| Key | Value |
| --- | --- |
| `v` | `1` |
| `ip` | Dotted IPv4 in a local range |
| `port` | 1–65535 |
| `fp` | 64 hex characters, SHA-256 of the receiver certificate |
| `id` | Device UUID |
| `n` | Device name, percent-encoded |

Packages: `qr_flutter` (draw) and `mobile_scanner` (scan), D-014. iOS needs `NSCameraUsageDescription`; Android needs `CAMERA` (camera hardware marked optional).

## Tests

**Unit tests (no phones)**

- `test/core/protocol/connect_payload_test.dart`: valid payloads, round trip with spaces, `&` and emoji in the name, every local range, about 50 rejected inputs (other schemes, Wi-Fi QR, look-alike host, user info, fragment, control characters, bad percent encoding, invalid UTF-8, repeated parameters, public, loopback, multicast and malformed IPs, bad ports, bad fingerprint and id), and error text free of the payload.
- `test/core/discovery/network_monitor_test.dart`: which address goes in the code.
- `test/features/nearby/manual_address_test.dart`: typed IP and port validation.
- `test/features/nearby/nearby_controller_test.dart`: a QR connect carries the full fingerprint and id; a typed address has no expected id.

**Device checks**

[DEVICE_TESTS.md](../DEVICE_TESTS.md), section "Phase 2: discovery and QR connect" (P2-4, P2-5, P2-7).

## Known limits and risks

- **Until Phase 4 the fingerprint is not checked.** A man in the middle on the same network could still intercept a QR connection (D-011).
- **Manual entry trusts whatever CrossDrop device answers** at the address.
- **The QR code changes at each launch**, because the port and certificate do (D-016). A photo of an old code usually fails to connect, because the port has changed.

## Open questions

- None.
