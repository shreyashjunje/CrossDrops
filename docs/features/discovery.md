# Feature: Discovery on the local network

- Phase: 2
- Status: Built, awaiting device tests
- Last updated: 2026-11-02

## Summary

Phones on the same Wi-Fi find each other without typing anything. While Receive is open, a phone advertises `_crossdrop._tcp` over Bonjour/mDNS. The Send flow opens a Nearby screen that lists the phones it finds, by name and platform. Tapping one checks who answers at that address (`GET /v1/info`) and opens Send with the address filled in. If nothing is found within about 5 seconds, the screen suggests the QR code or a typed address. On iPhone it also checks whether Local Network access is turned off and, if so, explains how to turn it on.

## Scope

**In scope**

- Advertising and browsing `_crossdrop._tcp` with TXT `v`, `id`, `n`, `p`, `fp` (bonsoir, D-012).
- A persistent device id and editable name, stored in a drift database (D-013).
- Nearby list with add, update and remove events keyed by device id; devices that disappear or do not answer are removed.
- iOS Local Network permission: `NSLocalNetworkUsageDescription`, `NSBonjourServices`, detection of "denied" and a link to Settings (D-015).
- Android Wi-Fi multicast lock while browsing or advertising (held by bonsoir, D-012).
- Re-advertising and re-browsing when the Wi-Fi or IP changes, and when the app returns to the foreground.
- `GET /v1/info` on the receive server.

**Out of scope** (and which phase picks it up)

- The 6-digit code check, "Trust this device", and pinning the TLS connection to the fingerprint (Phase 4). The TXT `fp` is shown nowhere and not checked yet.
- Advertising while the app is open but Receive is not (with the Accept prompt, D-016).
- Hotspot mode and Android socket binding to a Wi-Fi without internet (hotspot phase).
- Rediscovering a peer by id to resume after its IP changed mid-transfer (session-flow phase).

## Design

Follows [ARCHITECTURE.md](../ARCHITECTURE.md) "Discovery advertisement", "Connection flow" and the Discovery and Local network permission rows of "Platform modules". Specific to this feature:

- **Service instance name** is `CrossDrop-<first 8 characters of the device id>`. It carries no personal data and rarely clashes. The user's device name travels only in the TXT `n` key.
- **TXT record:** `v=2` (`v=1` before D-061), `id=<UUID>`, `n=<name, at most 63 UTF-8 bytes>`, `p=ios|android`, `fp=<first 16 hex characters of the certificate SHA-256>`. Until Phase 4 the certificate is created at each launch, so `fp` changes at each launch (D-016). Keys are read case-insensitively. A record with a newer `v` needs only `v`, `id` and `n`, and is listed as "needs update".
- **Peer list** (`PeerList`, pure state machine): it keeps the latest record per device id and maps service names to ids, so a `lost` event removes the right device. If one device has several service names, it is removed only when the last name is lost. It ignores records with a bad TXT, our own id, a port outside 1–65535, or no IPv4 address in a local range. The local-range rule means a hostile advertisement cannot point us at the internet (CLAUDE.md rule 8). Each change is emitted as `PeerAdded`, `PeerUpdated` or `PeerRemoved`.
- **Removal:** a device disappears on a `lost` event, when tapping it fails with a network or identity error, on pull to refresh, and when browsing stops. Android NSD sometimes reports `lost` late; device test P2-6 measures this.
- **Tap to connect:** `checkPeer` calls `GET /v1/info` with a 5 s timeout. It confirms a common protocol version and that the device id matches the list entry, then opens Send with the IP and port filled in (still editable).
- **Network changes:** `NetworkMonitor` combines `connectivity_plus` events (every event counts, because a Wi-Fi switch can keep the same IP) with a 3 s poll of local IPv4 addresses. Both are debounced by 1 s. On a change, Receive re-advertises and redraws the QR code, and Nearby restarts browsing with an empty list. Mobile data and VPN interfaces (`rmnet*`, `pdp_ip*`, `tun*`, `utun*`, ...) are ignored.
- **Lifecycle:** Nearby stops browsing when the app is paused, which releases the Android multicast lock, and starts again on resume. Receive re-advertises on resume, because iOS suspends the app when the screen locks.
- **iOS permission detection** (D-015): bonsoir does not report the `PolicyDenied` state, so after 5 s with nobody found the app calls a small Swift probe. The probe advertises a short-lived Bonjour service and browses for it:
  - It answers `granted` as soon as it sees its own service.
  - At the 8 s timeout it answers `denied` if the browser was waiting with `PolicyDenied`, otherwise `unknown`.
  - On `denied`, Nearby shows the explanation screen with Open Settings, Try again and Scan a QR code anyway. Any peer that appears afterwards clears the screen. Returning from Settings probes again.
- **Logging:** bonsoir's own logs are off because they contain device names. Our logs show only event types and the first 8 characters of device ids.

## Code

| Path | Purpose |
| --- | --- |
| `lib/core/discovery/mdns_backend.dart` | `MdnsBackend` interface and events |
| `lib/core/discovery/bonsoir_backend.dart` | bonsoir implementation |
| `lib/core/discovery/txt_record.dart` | TXT encode and validated decode |
| `lib/core/discovery/peer_list.dart` | `Peer`, `PeerChange`, `PeerList` state machine |
| `lib/core/discovery/discovery_service.dart` | `PeerBrowser`, `Advertiser`, instance name |
| `lib/core/discovery/network_monitor.dart` | Network change detection, reachable addresses, QR address choice |
| `lib/core/client/peer_check.dart` | `ConnectTarget`, `checkPeer` (`GET /v1/info`) |
| `lib/core/security/device_identity.dart` | UUID, default name, `IdentityRepository` |
| `lib/core/protocol/device_name.dart` | Device name sanitizing |
| `lib/core/storage/database.dart` | drift database, `identity` table |
| `lib/platform/local_network.dart` | Dart side of the `crossdrop/local_network` channel |
| `ios/Runner/AppDelegate.swift` | `LocalNetworkChannel`, `LocalNetworkProbe` |
| `android/app/src/main/kotlin/.../MainActivity.kt` | Same channel: always `granted`, opens App info |
| `lib/features/nearby/` | Nearby screen and controller, permission view |
| `lib/features/settings/settings_screen.dart` | Device name |

## Protocol and API

- `GET /v1/info` returns 200 `{"id": "<uuid>", "name": "...", "platform": "ios|android", "versions": [2]}`.
- Platform channel `crossdrop/local_network`:
  - `probe({timeoutMs})` returns `"granted" | "denied" | "unknown"`.
  - `openSettings()` opens the app's page in Settings.

**Android permissions** (min SDK 24 to target SDK; none of them needs location):

| Permission | Why | Runtime prompt |
| --- | --- | --- |
| `INTERNET` | Sockets | No |
| `CHANGE_WIFI_MULTICAST_STATE` | Multicast lock for mDNS | No |
| `ACCESS_WIFI_STATE` | Wi-Fi state for the multicast lock | No |
| `ACCESS_NETWORK_STATE` | Network change events | No |
| `CAMERA` | QR scanning ([qr-connect.md](qr-connect.md)) | Yes, when the scanner opens |

`NEARBY_WIFI_DEVICES` (Android 13+) is not needed for NSD on the same Wi-Fi. The hotspot phase adds it.

## Tests

**Unit tests (no phones)**

- `test/core/discovery/txt_record_test.dart`: round trip, case-insensitive keys, sanitized names, newer versions, and 17 rejected shapes.
- `test/core/discovery/peer_list_test.dart`: add, update, no-op, lost, several names per device, a name moving to another device, own id, bad TXT, non-local or missing IPv4, bad port, unsupported version, unreachable, clear.
- `test/core/discovery/discovery_service_test.dart`: browser and advertiser over a fake backend (start, stop, restart, sawSelf, retry after a failed start).
- `test/core/discovery/network_monitor_test.dart`: address filtering, QR address choice, IP change, same-IP Wi-Fi switch, debouncing, stop.
- `test/core/client/peer_check_test.dart`: `/v1/info` over loopback, identity mismatch, version mismatch, nothing listening.
- `test/core/security/device_identity_test.dart`, `test/core/protocol/device_name_test.dart`: UUID format, persistence and rename, name rules.
- `test/features/nearby/nearby_controller_test.dart`: sorting, lost devices, the iOS denied path (probe after the timeout, cleared when a peer appears), no probe on Android, refresh, unreachable devices dropped, dispose stops browsing.

**Device checks**

Listed in [DEVICE_TESTS.md](../DEVICE_TESTS.md), section "Phase 2: discovery and QR connect".

## Known limits and risks

- **The Swift probe and Info.plist changes have not been built yet.** They need a Mac with Xcode.
- **A device can advertise any id, name or `fp`.** The list keeps the newest record per id, so a spoofer on the same Wi-Fi can replace an entry. Phase 4 protects this with TLS pinning and the 6-digit code.
- **The iOS probe cannot tell "not asked yet" from "granted"** until the first-run prompt has been answered. A user who leaves the prompt open longer than about 13 s may briefly see the "denied" screen. Try again fixes it.
- **Android NSD may report `lost` late, or not at all.** Tapping a stale entry removes it.
- **Receive is visible only while its screen is open** (D-016).

## Open questions

- Should the nearby list show the IP and port? It does now, to help device testing; it could be hidden later.
