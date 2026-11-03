# Feature: Android network binding

- Phase: 7
- Status: Built, awaiting device tests
- Last updated: 2026-11-03

## Summary

When an Android phone joins a Wi-Fi without internet (an iPhone Personal Hotspot with no mobile data, or any offline network), Android keeps mobile data as the default network. New sockets then leave over mobile data and never reach the other phone. CrossDrop binds its own process to the Wi-Fi network in exactly that case ([ARCHITECTURE.md](../ARCHITECTURE.md), scenario 7).

## Scope

**In scope**

- Watching the Wi-Fi network and the default network.
- Binding and unbinding the process, for the app's lifetime.

**Out of scope**

- iPhone: iOS sends local subnet traffic over Wi-Fi even when the Wi-Fi has no internet.
- The Android phone that *is* the hotspot: it is not a Wi-Fi client, and traffic to its own clients goes over the hotspot interface.

## Design

- **Rule** (`shouldBindToWifi`, D-056): bind when Wi-Fi is connected, **not** validated (no internet) and **not** the default network. Otherwise clear the binding:
  - a normal Wi-Fi with internet is the default and needs nothing;
  - a VPN that is the default must keep routing (scenario 6);
  - a Wi-Fi without internet that is still the default (mobile data off) needs nothing.
- **How:** `ConnectivityManager.bindProcessToNetwork(network)`. Android's recommended per-socket way (`Network.getSocketFactory()`) cannot reach sockets that `dart:io` creates itself. The binding covers every socket CrossDrop opens afterwards, including the HTTPS client, the WebSocket and the server's listening socket. CrossDrop makes no calls outside the local network (CLAUDE.md hard rule 8), so nothing else is affected.
- **Changes:** a `NetworkCallback` on Wi-Fi and a default-network callback report every change to Dart. When the Wi-Fi is lost, Kotlin clears the binding at once (a binding to a lost network breaks every new socket), and Dart binds again when a matching Wi-Fi returns. A failed bind is tried again at the next change. Dart applies changes one at a time, newest last, so a loss reported while a bind is still running is applied after it (review L7).
- **Logs:** `[crossdrop.network] bound to Wi-Fi (no internet there)`, `binding cleared`, `binding to Wi-Fi failed`.

## Code

| Path | Purpose |
| --- | --- |
| `android/.../NetworkChannel.kt` | `crossdrop/network`: `wifiState`, `wifiChanged`, `bind`, `interfaces` |
| `lib/platform/network.dart` | `NetworkPlatform`, `WifiState` |
| `lib/core/discovery/subnet.dart` | `shouldBindToWifi` |
| `lib/app/network_binding.dart` | `NetworkBinder`, started at the app root |

## Protocol and API

None.

## Tests

**Unit tests (no phones)**

- `test/core/discovery/subnet_test.dart`: the rule for every combination.
- `test/app/network_binding_test.dart`: bind at start, normal Wi-Fi, changes, Wi-Fi lost and back, failed bind retried, band from frequency.

**Device checks**

[DEVICE_TESTS.md](../DEVICE_TESTS.md), "Phase 7": P7-6.

## Known limits and risks

- A server socket opened *before* binding is not moved; incoming connections should reach it anyway. Checked on devices in P7-6.
- Some VPN apps in "always-on, block connections without VPN" mode refuse the binding; the log says so and scenario 6 applies.

## Open questions

- None.
