# Feature: Keep-alive during transfers

- Phase: 3
- Status: Built, awaiting device tests
- Last updated: 2026-11-02

## Summary

A transfer must not die because the screen turned off or the user switched apps. While a transfer runs, the screen stays on. On Android, a foreground service keeps the transfer going with the screen off and shows its progress in a notification. On iPhone, which suspends apps in the background, the app uses a short background task to finish the current chunk and save progress, then continues when the user comes back.

## Scope

**In scope**

- Screen kept on while a transfer runs (both platforms), and while Receive is open, so the phone stays discoverable.
- Android: foreground service of type `dataSync` with a progress notification, a Wi-Fi lock and a wake lock; the `POST_NOTIFICATIONS` request on Android 13+.
- iOS: `beginBackgroundTask` when the app is hidden; every transfer saves and pauses inside it; resume on return.

**Out of scope** (and which phase picks it up)

- Receiving while the iPhone app is closed or suspended: not possible on iOS (ARCHITECTURE.md scope).
- Guiding users through OEM battery settings (Xiaomi, Oppo, Vivo, OnePlus): a later phase, once device tests show a need. `flutter_foreground_task` already has `openIgnoreBatteryOptimizationSettings` for it.
- Binding sockets to Wi-Fi when it has no internet: hotspot phase.

## Design

ARCHITECTURE.md, Platform modules, "Screen lock during transfer" and "Battery and OEM killers". The pieces:

- `KeepAlivePlatform` (interface) and `PlatformKeepAlive` (real) in `lib/platform/keep_alive.dart`, per hard rule 9.
- `KeepAliveCoordinator` in `lib/app/keep_alive.dart` (pure Dart, unit-tested):
  - **`begin` / `end`** per transfer. The first `begin` turns the screen on and, on Android, asks once for notification permission and starts the service. The last `end` turns everything off.
  - **`holdScreen` / `releaseScreen`** for screens that want the display on with no transfer (Receive).
  - **`progress`** updates the notification at most once per second.
  - **On iOS, `appBackgrounded`** (the app is hidden: lock, Home, app switcher) begins a background task and calls `onBackground()` on every transfer, then ends the task. The budget is 20 s; iOS gives about 30 s. If iOS asks for the time back early, the task ends at once. **`appResumed`** calls `onForeground()`.
- **What each side does on iOS backgrounding:**
  - **Sender:** stops after the current chunk (`UploadClient.requestPause`). The receiver saves what arrived and the session waits `paused`. On return it asks the receiver where to continue and goes on.
  - **Receiver:** `checkpointAll()` fsyncs and stores progress of every running upload. Uploads keep running until iOS suspends the app, then the sender sees a drop and retries; time in the background does not use up its retry deadline.
- **Android:** nothing pauses. The service keeps the process in the foreground state while the transfer runs in the app's own isolate. The service has no periodic task.
- **App-wide sender:** the send controller is not tied to the Send screen, so leaving the screen does not stop a transfer.

Choice of package: D-024.

## Code

| Path | Purpose |
| --- | --- |
| `lib/platform/keep_alive.dart` | Platform interface and implementation |
| `lib/app/keep_alive.dart` | `KeepAliveCoordinator`, `BackgroundAware` |
| `lib/app/providers.dart` | `keepAliveProvider` with the lifecycle listener |
| `ios/Runner/AppDelegate.swift` | `crossdrop/background` channel: `begin`, `end`, and `expiring` back to Dart |
| `android/app/src/main/AndroidManifest.xml` | Service declaration and permissions |

## Protocol and API

None on the wire. Platform channel `crossdrop/background` (iOS): `begin`, `end`; native-to-Dart `expiring`.

## Tests

**Unit tests (no phones)**

- `test/app/keep_alive_test.dart`:
  - Android: service lifetime across several transfers, permission asked once and denial not fatal, notification updates, no pausing in the background.
  - iOS: screen only, background task around saving, resume on return, a slow transfer cannot hold the task past the budget, early expiry ends the task once, screen holders.
- `test/core/engine/send_session_test.dart`: pause stops after the current chunk (no bytes flow while paused) and resume finishes the file.

**Device checks**

[DEVICE_TESTS.md](../DEVICE_TESTS.md), section "Phase 3": P3-3 (screen lock), P3-4 (force-close), and the notification parts of P3-1.

## Known limits and risks

- None of this has been run on a device yet. The iOS background time and the Android service behaviour must be confirmed in the device checks.
- Android 15 limits `dataSync` services to 6 hours a day per app. A 2 GB transfer takes minutes, so this matters only for unusual use.
- Some Android brands still kill foreground services. Watch for it in P3-3 on Xiaomi, Oppo, Vivo and OnePlus phones.
- If the user swipes CrossDrop away on Android, the service stops (`stopWithTask`). The transfer resumes on the next launch.

## Open questions

- None.
