# Feature: iPhone Personal Hotspot guide

- Phase: 7 (screens from Phase 6)
- Status: Built, awaiting device tests
- Last updated: 2026-11-03

## Summary

Apps cannot turn on an iPhone's Personal Hotspot. This guide tells the user, in three steps, to turn it on in Settings, join it from the Android phone, and continue with discovery or the QR code. While it is open, it shows what this phone sees: whether the hotspot is on, whether the Android has joined, and whether the other phone is on the same network ([ARCHITECTURE.md](../ARCHITECTURE.md), scenario 5).

## Scope

**In scope**

- Three steps, the same on both phones: turn on Personal Hotspot, join it from the Android, check and continue.
- A live status line on every step and a same-network check on the last.
- Buttons to Send files or Show my QR code to receive.

**Out of scope**

- Turning on Personal Hotspot from the app (iOS does not allow it).
- Joining the iPhone's hotspot from the Android app (`WifiNetworkSpecifier` gives a network without internet routing to the app only and a system dialog; the user's own Wi-Fi join is simpler and keeps working for other apps).

## Design

**Status** (`personalHotspotLink`, every 2 s, D-057):

- iPhone: an address on a `bridge*` interface in 172.20.10.0/28 means Personal Hotspot is on and a device has joined.
- Android: a `wlan*` address in 172.20.10.0/28 means it is on an iPhone's hotspot.
- The range is what iOS uses in practice; Apple does not document it. It only drives the hint, never a decision.

**Same network** (`peersOnSameNetwork`): step 3 starts the nearby search and lists phones whose address is in the same subnet as one of this phone's addresses. Prefix lengths come from the platform: `java.net.NetworkInterface` on Android, `getifaddrs` on iOS (`crossdrop/network` `interfaces`). Without them (tests, desktop), /28 is assumed in the hotspot range and /24 elsewhere.

**Steps' advice:**

- Keep the Personal Hotspot screen open until the Android joins: iOS hides the network otherwise.
- **Maximize Compatibility** if the Android cannot see the network (2.4 GHz, slower).
- If Android says "no internet", stay connected. With mobile data on the iPhone, the hotspot has internet; without, Android network binding ([android-network-binding.md](android-network-binding.md), D-056) keeps CrossDrop's traffic on the Wi-Fi.

## Code

| Path | Purpose |
| --- | --- |
| `lib/features/hotspot/personal_hotspot_guide.dart` | Guide, `personalHotspotLink`, `peersOnSameNetwork`, `withAssumedPrefix` |
| `lib/core/discovery/subnet.dart` | `sameSubnet`, `addressSharingSubnet`, `looksLikeIphoneHotspot` |
| `lib/platform/network.dart` | `NetworkPlatform.interfaces` |
| `android/.../NetworkChannel.kt`, `ios/Runner/HotspotJoinChannel.swift` (`NetworkInfoChannel`) | Interface prefixes |

## Protocol and API

None.

## Tests

**Unit tests (no phones)**

- `test/core/discovery/subnet_test.dart`: `sameSubnet` for /24, /28, /16, /32, /0 and bad input; `addressSharingSubnet`; `looksLikeIphoneHotspot`.
- `test/features/hotspot/hotspot_screens_test.dart`: iPhone sharing, Android joined, peers on the same network, assumed prefixes, step navigation.

**Device checks**

[DEVICE_TESTS.md](../DEVICE_TESTS.md), "Phase 7": P7-7.

## Known limits and risks

- If iOS ever changes the hotspot range, the ticks stay off but nothing breaks: the same-network check uses real prefixes.
- Whether Bonjour works across an iPhone Personal Hotspot between its clients and the iPhone itself is checked on devices (P7-7). If not, the QR code works.

## Open questions

- None.
