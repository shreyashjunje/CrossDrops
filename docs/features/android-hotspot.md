# Feature: Android hotspot from the app

- Phase: 7
- Status: Built, awaiting device tests
- Last updated: 2026-11-03

## Summary

When there is no shared Wi-Fi, or the Wi-Fi keeps phones apart, the Android phone makes its own small Wi-Fi network from inside CrossDrop and shows one QR code. The iPhone scans it, joins the network and connects. The network has no internet, uses no mobile data, and stops when it is no longer needed ([ARCHITECTURE.md](../ARCHITECTURE.md), "Connectivity scenarios", scenario 4).

## Scope

**In scope**

- Start a LocalOnlyHotspot, read its name, password and security type.
- Find this phone's address on the new network.
- One QR code with the Wi-Fi name, password and the usual connection info (IP, port, fingerprint, id, name).
- A second, standard Wi-Fi QR code for the iPhone Camera app, for iPhone builds that cannot join from the app (D-055).
- The permission request, and a clear message for every way the phone can refuse.
- Stop the hotspot when the screen closes, and 60 s after the last transfer ends.

**Out of scope**

- Choosing the network name, password or band. `startLocalOnlyHotspotWithConfiguration` exists only from Android 16 (API 36); the random values are fine.
- Sharing the phone's internet. Android's own tethering does that, and the screen explains it as the fallback.
- Android-to-Android use (v1 scope).

## Design

**Start** (`HotspotController.start`, D-054):

1. Remember this phone's IPv4 addresses.
2. Ask the Kotlin channel to start. It requests the permission if needed:
   - Android 13+: `NEARBY_WIFI_DEVICES`, declared `neverForLocation`.
   - Android 10–12: `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` (both capped at SDK 32). These versions also refuse when location services are off; that gives `location_off`.
3. `WifiManager.startLocalOnlyHotspot`. The reservation gives the name, password and security:
   - Android 11+ (API 30): `getSoftApConfiguration()`, name from `getWifiSsid()` on 13+ (`getSsid()` before), `getPassphrase()`, `getSecurityType()`.
   - Android 10: `getWifiConfiguration()` (deprecated in 30), WPA2.
   - An open or OWE network is refused (`unsupported_security`): the QR code always carries a password.
4. Poll the address list every 0.5 s for up to 10 s. `pickHotspotAddress` takes a new address on a hotspot-like interface (`swlan`, `ap`, `softap`, `wlan1+`), then any new local address, then an existing hotspot interface (a hotspot shared with another app). Mobile data and VPN interfaces never count.
5. Show the QR code. The receive server already listens on all interfaces, and its network monitor re-advertises on the new address.

**Errors** (codes from `onFailed`, a `SecurityException`, or a 20 s timeout):

| Code | Cause | What the screen says |
| --- | --- | --- |
| `permission` | Nearby devices (or Location) refused | Why it is needed, Open app settings |
| `location_off` | Android 10–12 with location off | Turn on Location; CrossDrop does not use it |
| `tethering_on` | `ERROR_INCOMPATIBLE_MODE` | Turn off the phone's own hotspot first |
| `no_channel` | `ERROR_NO_CHANNEL` | Turn Wi-Fi off and on, try again |
| `disallowed` | `ERROR_TETHERING_DISALLOWED` (policy) | Use the phone's own hotspot or the iPhone's |
| `unsupported_security` | Open network | Try again |
| `no_address` | No address within 10 s | Try again |
| `stopped` | `onStopped()` from quick settings or the system | Start again if needed |
| `failed` | `ERROR_GENERIC`, timeout, anything else | Try again |

Every error also shows "Or use this phone's own hotspot" with the manual steps.

**Stopping** (D-054): the hotspot belongs to the hotspot screen. Leaving the screen stops it; if a transfer is running, a dialog asks first. When the last transfer in either direction ends, a card says "The network stops in 60 s" with **Keep on**. A new transfer cancels the countdown. Closing the reservation is the documented way to stop; the system tears the network down when no app holds it. Leaving or tapping Stop while the hotspot is still starting cancels the start: Kotlin answers that start with `cancelled` and closes the reservation if the system hands one over afterwards, and Dart stops the service again if it was disposed meanwhile (review H3).

**Sending the other way:** **Send files to the iPhone** opens Send on top of the hotspot screen, so the network stays up. The iPhone, once joined, is found by discovery or by its own QR code.

**Privacy:** the name and password are never logged; logs say `started (wpa3t)` and `running on swlan0`.

## Code

| Path | Purpose |
| --- | --- |
| `android/.../HotspotChannel.kt` | `crossdrop/hotspot`: permission, start, stop, `stopped` event |
| `android/.../MainActivity.kt` | Registers the channel, forwards the permission result, stops on engine clean-up |
| `lib/platform/hotspot.dart` | `HotspotService`, `ChannelHotspotService`, error codes |
| `lib/core/discovery/subnet.dart` | `pickHotspotAddress` |
| `lib/core/protocol/connect_payload.dart` | `ws`, `wp`, `wsec` QR fields |
| `lib/features/hotspot/hotspot_controller.dart` | Start, address wait, idle stop, `wifiJoinQr` |
| `lib/features/hotspot/hotspot_screens.dart` | `AndroidHotspotScreen` |

## Protocol and API

QR payload, optional fields (ARCHITECTURE.md, "QR code payload"):

- `ws`: Wi-Fi name, 1–32 bytes of UTF-8, no control characters.
- `wp`: WPA passphrase, 8–63 printable ASCII characters.
- `wsec`: `wpa2` (default), `wpa3t` (WPA3 transition), `wpa3`.

`ws` and `wp` come together or not at all. Older apps ignore the fields.

## Tests

**Unit tests (no phones)**

- `test/core/protocol/connect_payload_test.dart`: Wi-Fi fields round trip, escaping, every refusal, `toString` hides both.
- `test/core/discovery/subnet_test.dart`: `pickHotspotAddress` for new interfaces, Wi-Fi dropped, shared hotspot, mobile data.
- `test/features/hotspot/hotspot_controller_test.dart`: start, failure, no address, stopped elsewhere, 60 s stop, Keep on, Wi-Fi QR escaping; leaving while the system starts it or while the addresses are read, and Stop while starting, never leave a hotspot running.
- `test/features/hotspot/hotspot_screens_test.dart`: Start, leave stops it, error messages, permission button.

**Device checks**

[DEVICE_TESTS.md](../DEVICE_TESTS.md), "Phase 7": P7-1, P7-2, P7-3.

## Known limits and risks

- Phones that cannot run a hotspot and a Wi-Fi connection at the same time drop their Wi-Fi when the hotspot starts. That is expected; the screen does not need the old Wi-Fi.
- Some brands rename interfaces. If the address is not found, `no_address` appears; the logs show the interface names (not the addresses).
- Android 13+ may pick WPA3 only on 6 GHz. Older iPhones may not join; `wsec` is shown in the logs so the device test can tell.
- The QR code shows the password in clear on screen, as Android's own hotspot share does.

## Open questions

- None.
