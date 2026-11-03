# Feature: iPhone joins the Android hotspot

- Phase: 7
- Status: Built, awaiting device tests (in-app join needs a paid Apple account, see below)
- Last updated: 2026-11-03

## Summary

The iPhone scans the Android's hotspot QR code, joins that Wi-Fi network and connects to the Android, without the user typing anything. Builds signed with a free Apple ID cannot join from the app, so the same screen then walks the user through Settings > Wi-Fi and goes on by itself once the Android answers ([ARCHITECTURE.md](../ARCHITECTURE.md), scenario 4).

## Scope

**In scope**

- Scanning a hotspot code from Send > Scan QR code, or from Hotspot mode > Join the Android phone's network.
- In-app join with `NEHotspotConfigurationManager`.
- The user tapping Cancel on the iOS prompt, an iPhone already on that network, and builds without the capability.
- Waiting until the Android's server answers, then the normal pinned connect.
- Removing the network afterwards.

**Out of scope**

- Reading the current Wi-Fi name (`NEHotspotNetwork.fetchCurrent`): it needs the "Access Wi-Fi Information" capability (also paid-only) or location permission. A direct check of the receiver is enough.

## Design

**Capability** (D-055): `NEHotspotConfigurationManager` needs the Hotspot Configuration capability, entitlement `com.apple.developer.networking.HotspotConfiguration`. Apple's "Supported capabilities (iOS)" table lists Hotspot for Apple Developer Program and Enterprise members only, not for free accounts. The CI build is installed with a free Apple ID (D-017), so:

- `Runner.entitlements` (default) stays without it, so free-account signing keeps working.
- `RunnerHotspot.entitlements` adds it. With a paid account: enable **Hotspot** on the App ID in the developer portal, then set Runner > Build Settings > Code Signing Entitlements to `Runner/RunnerHotspot.entitlements` (or add the capability in Xcode > Signing & Capabilities > + Capability > Hotspot Configuration).
- At run time, `canJoin` reads the app's own `embedded.mobileprovision`. If its `Entitlements` lack the key, the app goes straight to the manual path. With no profile (App Store), it tries; iOS answers `internal` without the entitlement, which also leads to the manual path.

**Flow** (`HotspotJoinFlow`):

1. **Checking:** a 1.5 s TCP connect to the IP and port from the code. If it answers, the iPhone is already on that network: no prompt.
2. **Joining** (with the capability): `apply(NEHotspotConfiguration(ssid:passphrase:isWEP: false))` with `joinOnce = false`. Before that, networks from earlier sessions are removed (`getConfiguredSSIDs`, all of which are this app's).
3. **Outcomes:**

   | iOS result | Flow |
   | --- | --- |
   | success | Waiting: check every 1 s for up to 30 s |
   | `alreadyAssociated` | Waiting |
   | `userDenied` | "Cancel was tapped" with Try again and Join in Settings instead |
   | `invalid*` | "The iPhone refused this network's name or password" |
   | `internal`, newer system codes | Manual |
   | `pending`, `applicationIsNotInForeground` | Failed, Try again |

4. **Manual:** steps, the name and password, **Copy password**, then a check every 2 s until the receiver answers.
5. **Connected:** from Send, the screen closes and Nearby connects with the fingerprint from the code (pinned, as any QR connect). From Hotspot mode, it offers **Send files to <name>** and explains how to receive.

**Why `joinOnce = false`:** Apple documents that a `joinOnce` network is dropped when the app is in the background for more than 15 s or the device sleeps. CrossDrop pauses and resumes across screen locks (keep-alive.md), so the network must survive. Instead, `JoinedHotspot` removes the network CrossDrop added 60 s after the last transfer ends, or 10 minutes after joining if no transfer starts. A network the user joined in Settings is not removed by CrossDrop.

**Local Network permission:** the first connection to the Android still triggers the iOS Local Network prompt if it was not answered yet (discovery.md).

## Code

| Path | Purpose |
| --- | --- |
| `ios/Runner/HotspotJoinChannel.swift` | `crossdrop/hotspot_join`: `canJoin`, `join`, `forget` |
| `ios/Runner/RunnerHotspot.entitlements` | Entitlements for paid-account builds |
| `lib/platform/hotspot.dart` | `HotspotJoiner`, `JoinCapability`, `JoinOutcome` |
| `lib/features/hotspot/join_flow.dart` | `HotspotJoinFlow` state machine, `tcpReachable` |
| `lib/features/hotspot/joined_hotspot.dart` | Removes the joined network later |
| `lib/features/hotspot/hotspot_screens.dart` | `JoinAndroidHotspotScreen`, `JoinHotspotScreen` |
| `lib/features/nearby/nearby_screen.dart` | A scanned hotspot code joins before connecting |

## Protocol and API

No protocol change. The QR fields are in [android-hotspot.md](android-hotspot.md).

## Tests

**Unit tests (no phones)**

- `test/features/hotspot/join_flow_test.dart`: already joined, in-app join then wait, `alreadyAssociated`, timeout, Cancel then Try again, no entitlement, entitlement stripped, invalid, switching to manual stops the wait, dispose stops polling.
- `test/features/hotspot/hotspot_screens_test.dart`: manual join shows name, password and Copy, then Connected; Cancel shows both ways on; a network joined from the app is remembered and removed.

**Device checks**

[DEVICE_TESTS.md](../DEVICE_TESTS.md), "Phase 7": P7-4 (free Apple ID build), P7-5 (paid account, when available).

## Known limits and risks

- **Free Apple ID builds cannot join in-app.** This is Apple's rule, not a bug. The manual path and the Camera Wi-Fi QR code on the Android cover it.
- Sideloading tools may drop or rename entitlements. `canJoin` reads the installed profile, so the app reacts to what is really there.
- WPA3-only networks (some Android 13+ hotspots on 6 GHz) may not join on older iPhones. Not verified.
- iOS may show "No Internet Connection" under the network. That is expected.

## Open questions

- None. Whether to buy a paid Apple Developer account for in-app join is the owner's choice; nothing else depends on it.
