# Feature: Onboarding

- Phase: 6
- Status: Built, awaiting device tests
- Last updated: 2026-11-03

## Summary

Three short pages on first launch: both phones need CrossDrop open; why the Local Network permission is needed; what to do when the phones do not find each other. Receiving starts only after them, so on iPhone the system's Local Network prompt appears right after the page that explains it. Every other permission is asked at the moment it is needed.

## Scope

**In scope**

- Three pages with Next, Skip and Get started; a replay from Settings.
- The order of permission prompts.

**Out of scope**

- Asking for permissions on the pages themselves (each is asked where it is used).
- Illustrations: icons for now.

## Design

| Page | iPhone | Android |
| --- | --- | --- |
| 1 | "Open CrossDrop on both phones": what CrossDrop does; both apps open, nearby, until files arrive; nothing goes through the internet | Same |
| 2 | "Allow Local Network": iPhone will ask; tap Allow; what Don't Allow means and where to change it | "Same Wi-Fi, no internet needed": no upload; which permissions come later and when |
| 3 | "If the phones don't find each other": same Wi-Fi, then the QR code, then hotspot mode (under Send > Can't find the other phone?) | Same |

**When each permission is asked**

| Permission | Asked when | Code |
| --- | --- | --- |
| Local Network (iOS) | Right after onboarding, when receiving starts advertising | `ReceiveHost`, gated by `receiveAllowedProvider` (D-050) |
| Camera | Scan QR code | `mobile_scanner` |
| Photos (read) | Photos & videos on the Send screen | `photo_manager` (D-038) |
| Photos add-only (iOS) | Accepting an offer with photos or videos | `ReceiveController.answer` (D-043) |
| Notifications (Android 13+) | The first transfer | `PlatformKeepAlive` |
| Nearby Wi-Fi devices (Android 13+) | Starting a hotspot (Phase 7) | Not yet |

`settings.onboardingDone` (schema 5) records that the pages were shown. It is off by default, so phones upgraded from Phase 5 see the pages once. `OnboardingGate` shows the pages or Home; if the database cannot be read it shows Home rather than locking the user out.

The pages are list views, so they scroll with large system text. The page title is a screen-reader header: "Page 2 of 3. Allow Local Network".

## Code

| Path | Purpose |
| --- | --- |
| `lib/features/onboarding/onboarding_screen.dart` | The pages, Next, Skip, Get started, replay |
| `lib/features/onboarding/onboarding_gate.dart` | Introduction or Home |
| `lib/features/receive/receive_host.dart` | `receiveAllowedProvider` = onboarding done |
| `lib/core/storage/settings_repository.dart` | `watchOnboardingDone`, `setOnboardingDone` |

## Protocol and API

None. Database schema 5: `settings.onboarding_done`.

## Tests

**Unit and widget tests (no phones)**

- `test/features/onboarding/onboarding_test.dart`: page content per platform; first launch shows the pages, then Home; Skip; later launches skip; receiving waits for the pages; large text in dark mode.
- `test/core/storage/migration_test.dart`: schema 4 to 5 keeps settings, the introduction is not marked shown.

**Device checks**

[DEVICE_TESTS.md](../DEVICE_TESTS.md), Phase 6, P6-1.

## Known limits and risks

- On iPhone, Local Network is asked right after onboarding even if the user only wants to send. That is the moment the page explains it, and the phone must be discoverable to receive anyway.
- A user who taps Don't Allow cannot be found. Find help and the Nearby denied view explain how to turn it on.

## Open questions

None.
