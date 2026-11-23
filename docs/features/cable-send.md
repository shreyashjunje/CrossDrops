# Feature: Send by cable

- Phase: 8 (after v1 scope)
- Status: Built, awaiting device tests
- Last updated: 2026-11-24

## Summary

Either phone picks photos, videos or files in CrossDrop and sends them to the other over a USB cable (iPhone → Android: D-073; Android → iPhone: D-074). No Wi-Fi and no hotspot. The normal CrossDrop protocol runs over the cable: pinned TLS, Accept and the 6-digit code, SHA-256 or the tree hash, resume, six upload lanes and the data lanes, so many files and large videos behave exactly like on Wi-Fi and every file arrives byte for byte. See D-073.

## Scope

**In scope**

- Both directions, both apps open in the foreground, an Android with USB host mode.
- Everything the Send screen can pick.
- Unplugging and plugging in again: the send resumes.

**Out of scope**

- Sending while the iPhone app is in the background (iOS closes its sockets).

## Design

- **Transport:** Apple's USB multiplexing protocol (usbmux), as iTunes and Xcode use. The Android is the USB host and opens TCP-like connections to ports on the iPhone. The cable test (U-11) proved it on an iPhone 17 Pro and a Samsung S20 FE.
- **Host name:** the receiver is `cable.crossdrop.invalid`. `pinnedHttpClient` and `probeFingerprint` open those sockets through the isolate's `cableDialer` and run TLS on them with the same pin checks (`lib/core/cable/cable_route.dart`).
- **Control:** the iPhone's `CableLink` listens on 127.0.0.1:47913 (47914, 47915). The Android bridge connects and sends `hello {port?, id, name}`; the iPhone answers with its own hello. The iPhone asks `dial {listen, port}`; the Android answers with a joined connection or `fail {listen}`. JSON lines, at most 4 KB (`cable_messages.dart`).
- **Android sends (D-074):** the Android's dialer binds 127.0.0.1:P and calls `cableDial {listen, port}`; `CableBridge.dialOut` opens usbmux straight to the iPhone's receive or data lane port and joins it to P.
- **Dials:** a dial binds a new 127.0.0.1 port in the isolate that dials, so upload workers get their own sockets and no bytes pass through the main isolate. The Android only joins its receive server's ports.
- **Android:** `UsbMux.kt` (usbmux v2, 16 KB reads like usbmuxd, a 512 KB window per connection, the iPhone's window respected) and `CableBridge.kt` (control, dials, a pipe per connection). Bytes stay in Kotlin. `UsbCableChannel` starts it (`cableStart`, `cableStop`, `cable` events) and pauses it while the cable test holds the iPhone.
- **When:** Android runs the bridge while an iPhone is plugged in, the receive server is up and Receiving is on (`CableReceiveController`). The iPhone runs the link while the app is in the foreground (`CableSendController`).
- **Screens:** iPhone Nearby lists "<name> · Connected by cable" at the top; tapping it checks the phone like a first contact (fingerprint probe, then the code). The Android home card says what the cable can do (`cable_card.dart`).
- **Resume:** the send's locator returns the cable host when the phone on the cable has the receiver's device id.

## Code

| Path | Purpose |
| --- | --- |
| `lib/core/cable/cable_route.dart` | Reserved host, sendable dialer, per-isolate dialer. |
| `lib/core/cable/cable_messages.dart` | Control messages and line splitting. |
| `lib/core/cable/cable_link.dart` | iPhone end: control listener, dials. |
| `lib/core/security/pinning.dart` | TLS over a dialed socket, same pin checks. |
| `lib/features/cable/cable_controllers.dart` | iPhone link and Android bridge lifecycles. |
| `android/.../UsbMux.kt` | usbmux protocol engine. |
| `android/.../CableBridge.kt` | Control connection, dials, pipes. |

## Tests

**Unit and end-to-end tests (no phones)**

- `test/core/cable/cable_route_test.dart`: pinned requests and the probe over the cable, refused and silent dials, a dialer sent to another isolate.
- `test/core/cable/cable_link_test.dart`: messages, hello, refused dial, unplug, missing hello, takeover, oversized lines, port fallback.
- `test/core/cable/cable_send_test.dart`: 120 photos and two 40 MB videos (striped, workers, tree hash) byte for byte; unplug and resume.
- `test/features/cable/cable_controllers_test.dart`: Android start, update, stop, refused permission; iPhone peer; loopback only.

**Device checks**

[DEVICE_TESTS.md](../DEVICE_TESTS.md), section "Send by cable (D-073)", C-1 to C-8.

## Known limits and risks

- **Not tested on a phone yet.** `UsbMux.kt` runs only against a real iPhone.
- Speed is capped by the cable: USB 2 (the iPhone's own cable) is about 35-40 MB/s at best. Reads are 16 KB at a time, one in flight; if a USB 3 cable shows the reader as the limit, queued reads (`UsbRequest`) are the next step.
- Whether the iPhone takes usbmux connections to a socket bound to 127.0.0.1 only is checked in C-1. If not, the link binds to all addresses and pinned TLS still protects it.
- usbmux is undocumented; an iOS update could change it. Wi-Fi and hotspot modes stay.
- The iPhone may ask "Trust This Computer?" once.
