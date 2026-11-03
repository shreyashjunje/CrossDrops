# Device Tests

Acceptance checks that need real phones (one iPhone, one Android). Unit tests that run on a computer do not belong here.

## How this file is used

- Each phase gets a section with its acceptance checks, written before the phase is called done.
- Each check lists: steps, expected result, and what logs or screenshots to capture.
- After running a check, record the date, devices, OS versions, result (pass/fail) and notes.
- A device feature counts as working only after a check here has been run and passed.

## Installing the CI builds (no Mac needed)

The **Build** workflow (`.github/workflows/build.yml`) runs analyze and tests on every push. When started manually, it also builds an Android APK and an unsigned iPhone `.ipa`. Run it after each phase, then install both builds for that phase's checks.

### 1. Start the build

1. Push the commits to GitHub.
2. Start the workflow:
   - **Web:** on github.com, open the repository > **Actions** > **Build** > **Run workflow** > branch `main` > **Run workflow**.
   - **Or with the GitHub CLI:** `gh workflow run build.yml --ref main`.
3. Wait until all three jobs are green: Analyze and test, Android APK, iPhone unsigned IPA. The iPhone job takes about 10–20 min.
4. Open the run and download the artifacts at the bottom of the page:
   - `crossdrop-android-<sha>`, which contains `crossdrop-<sha7>.apk`, or `crossdrop-<sha7>-debugsigned.apk` while the repository has no release key secrets ([RELEASE.md](RELEASE.md))
   - `crossdrop-ios-unsigned-<sha>`, which contains `crossdrop-<sha7>-unsigned.ipa`

   Unzip both. Note the 7-character commit id for the Results tables.

If a job fails, open it, copy the red error lines and paste them back.

### 2. Install on Android

- **USB:** `adb install -r crossdrop-<sha7>.apk`
- **Or without USB:** copy the APK to the phone, open it, and allow "Install unknown apps" for the file manager when asked.
- **After the app id change (2026-11-03):** the app is now `io.github.shreyashjunje.crossdrop`, so it installs next to an older `com.example.crossdrop` build instead of replacing it. Uninstall the old one (`adb uninstall com.example.crossdrop`) so two CrossDrops do not both answer on the network.
- **"App not installed" / signatures do not match:** each `-debugsigned` APK is signed with a new debug key. `adb uninstall io.github.shreyashjunje.crossdrop`, then install again.

### 3. Install on iPhone from Windows (free Apple ID)

Do this once:

1. Install **iTunes** and **iCloud** for Windows from apple.com. The Microsoft Store versions do not work with Sideloadly.
2. Install **Sideloadly** from its official site, sideloadly.io.
3. Connect the iPhone by USB, unlock it, and tap **Trust** on the phone.
4. iOS 16 and later: Settings > Privacy & Security > **Developer Mode** > on. The phone restarts; confirm when asked.

For each build:

1. Open Sideloadly. Drag `crossdrop-<sha7>-unsigned.ipa` into it. Select your iPhone and enter your Apple ID. A secondary Apple ID is fine.
2. Click **Start**. Enter the Apple ID password and a two-factor code if asked. Wait for "Done".
3. **First time only:** on the iPhone, Settings > General > VPN & Device Management > your Apple ID > **Trust**.
4. Open CrossDrop.

Limits of a free Apple ID:
- The app stops opening after **7 days**. Install it again with Sideloadly, or turn on its auto-refresh.
- Only about 3 sideloaded apps can be active at once.
- Bundle id: Sideloadly may change it. If it says the id `io.github.shreyashjunje.crossdrop` is unavailable, use its "Bundle ID" option to set something unique, for example `com.<yourname>.crossdrop`.

**Paste back if it fails:** the Sideloadly log (its Log window) and the iOS version.

## Phase 1: file transfer proof of concept

Feature doc: [features/file-transfer-poc.md](features/file-transfer-poc.md). Speeds go in [BENCHMARKS.md](BENCHMARKS.md).

### Preparation (once)

1. **Build in release mode** on both phones from the same commit. The easiest way: run the Build workflow and install both artifacts ([Installing the CI builds](#installing-the-ci-builds-no-mac-needed)). Other ways:
   - Android (from this PC): `flutter run --release -d <android-device-id>` (`flutter devices` lists ids). Without `android/key.properties`, first set `$env:CROSSDROP_ALLOW_DEBUG_SIGNING='true'` (PowerShell) for a debug-signed test build.
   - iPhone (from a Mac with Xcode): open `ios/Runner.xcworkspace`, set your signing team under Runner > Signing & Capabilities (change the bundle id from `io.github.shreyashjunje.crossdrop` if Xcode says it is taken), then `flutter run --release -d <iphone-id>`.
2. **Create test files** on the PC (PowerShell, random content so nothing can be compressed or deduplicated):

   ```powershell
   function New-RandomFile([string]$Name, [long]$Bytes) {
     $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
     $buf = New-Object byte[] (1MB)
     $fs = [System.IO.File]::Create((Join-Path (Get-Location) $Name))
     try {
       for ($done = 0L; $done -lt $Bytes; $done += 1MB) {
         $rng.GetBytes($buf)
         $fs.Write($buf, 0, [int][Math]::Min(1MB, $Bytes - $done))
       }
     } finally { $fs.Close() }
   }
   New-RandomFile "crossdrop-100MB.bin" 100MB
   New-RandomFile "crossdrop-1GB.bin" 1GB
   Get-FileHash crossdrop-*.bin -Algorithm SHA256 | Format-List Path, Hash
   ```

   Keep the two hashes.
3. **Copy the files to both phones:**
   - Android: `adb push crossdrop-100MB.bin crossdrop-1GB.bin /sdcard/Download/`
   - iPhone: in the Apple Devices app (or iTunes) on Windows, select the iPhone > Files > crossdrop, and drag both files in. They then appear in the Files app under On My iPhone > crossdrop.
4. Free space: each phone needs about 3 GB free (picked files are copied to the app cache before sending, and the receiver needs room for the file).
5. Both phones on the same Wi-Fi, mobile data on, VPN off, Wi-Fi on the router band you want to measure.

**Logs:** Android `adb logcat -s flutter` (lines start with `[crossdrop.server]` or `[crossdrop.client]`). iPhone: `flutter logs -d <iphone-id>` on the Mac while the phone is connected, or Xcode > Devices and Simulators > Open Console filtered on `crossdrop`. Logs contain only ids, offsets and sizes.

### P1-1: Android receives 100 MB from iPhone

1. Android: open CrossDrop > Receive. Note the IP marked `wlan0` (or similar Wi-Fi interface) and the port.
2. iPhone: CrossDrop > Send. Type the Android IP and port. Pick file > Browse > On My iPhone > crossdrop > `crossdrop-100MB.bin`. Tap Send.
3. If iOS asks to find devices on the local network, tap Allow (then tap Send again if it failed).

**Expected**
- iPhone: progress bar and live MB/s move smoothly; ends with "Done, SHA-256 verified by receiver" and `Time X s · average Y MB/s`.
- Android: the file row ends with "Saved, SHA-256 verified".
- `adb shell ls -l /sdcard/Android/data/io.github.shreyashjunje.crossdrop/files/CrossDrop/` shows `crossdrop-100MB.bin` with size exactly 104857600.
- Optional: `adb shell sha256sum /sdcard/Android/data/io.github.shreyashjunje.crossdrop/files/CrossDrop/crossdrop-100MB.bin` equals the PC hash (some Android versions block shell access to this folder; then note "not checked").

**Paste back:** screenshot of both screens at the end, the iPhone result line, the `ls -l` line, and `adb logcat -s flutter` output for the run.

### P1-2: iPhone receives 100 MB from Android

1. iPhone: CrossDrop > Receive. Note the IP marked `en0` and the port. Allow the local network prompt if shown.
2. Android: CrossDrop > Send. Type the iPhone IP and port. Pick file > Downloads > `crossdrop-100MB.bin`. Tap Send.

**Expected**
- Android shows "Done, SHA-256 verified by receiver" and the time / MB/s line.
- iPhone row ends with "Saved, SHA-256 verified"; the iPhone screen stays on during the transfer.
- Files app > On My iPhone > crossdrop > CrossDrop contains `crossdrop-100MB.bin`, 104.9 MB.
- Optional: copy it back with the Apple Devices app and compare `Get-FileHash` with the original.

**Paste back:** screenshots of both screens at the end, the Android result line, and `adb logcat -s flutter` output (plus iPhone logs if you have them).

### P1-3: Android receives 1 GB from iPhone

Same as P1-1 with `crossdrop-1GB.bin` (expected size 1073741824). Picking may take a while on iPhone (the file is copied first); Send is enabled when the name and size appear.

**Expected:** as P1-1, and the iPhone app stays responsive (no freezes while hashing), the iPhone screen does not lock during the transfer.

**Paste back:** as P1-1, and roughly how warm each phone got.

### P1-4: iPhone receives 1 GB from Android

Same as P1-2 with `crossdrop-1GB.bin`.

**Expected:** as P1-2, and the Android app stays responsive during the transfer.

**Paste back:** as P1-2.

### P1-5: Stop and Resume (once per direction, 1 GB)

1. Start a 1 GB send (either direction). At about 40%, tap Stop on the sender.
2. Sender shows "Stopped. Tap Resume to continue."; receiver progress stops.
3. Wait 5 s, tap Resume.

**Expected:** the progress bar continues from about 40% (does not restart at 0), finishes with "Done, SHA-256 verified by receiver", and the receiver shows "Saved, SHA-256 verified". The sender log shows `sending from N of 1073741824` with N > 0 on the second run.

**Paste back:** the sender's `sending from` log lines, final screenshots.

### P1-6: Resume after Wi-Fi drop

1. Start a 1 GB send. At about 30%, turn Wi-Fi off on the **sender** for 10 s, then on again (same network).
2. Within about 15 s the sender should show "Failed: stalled: no progress for 15 s" or "Failed: network: ...".
3. Check the receiver IP is unchanged. Wait about 20 s (the receiver needs up to 15 s to notice the dropped upload), then tap Resume. If it says `busy`, wait 10 s and tap Resume again.

**Expected:** continues from about 30%, ends verified on both sides.

**Paste back:** what the sender showed after the drop, how long until Resume worked, logs from both phones.

### P1-7: Wrong address

1. On Send, type a wrong last IP digit (or wrong port) and tap Send.

**Expected:** "Failed: network: ..." within about 10 s, app still usable; Send works after fixing the address.

### Results

| Check | Date | iPhone, iOS | Android, version | Commit | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| P1-1 | | | | | | |
| P1-2 | | | | | | |
| P1-3 | | | | | | |
| P1-4 | | | | | | |
| P1-5 iPhone → Android | | | | | | |
| P1-5 Android → iPhone | | | | | | |
| P1-6 | | | | | | |
| P1-7 | | | | | | |

## Phase 2: discovery and QR connect

Feature docs: [features/discovery.md](features/discovery.md), [features/qr-connect.md](features/qr-connect.md).

### Preparation (once)

1. Build both phones from the same commit: run the Build workflow and install both artifacts ([Installing the CI builds](#installing-the-ci-builds-no-mac-needed)). The iPhone build is the first to include the Swift probe and the new Info.plist keys. If the iPhone job fails with a Swift error in `AppDelegate.swift`, paste it back and stop.
2. **Give each phone a distinct name** in CrossDrop > Settings (gear icon), for example "Test iPhone", "Test Android A", "Test Android B". Home then shows "This phone: <name>".
3. **Wi-Fi:** all phones on the same home Wi-Fi, VPN off. For P2-5 you also need a second network: a second Wi-Fi name (many routers have separate 2.4 GHz and 5 GHz names), a guest network without client isolation, or a hotspot from a third phone.
4. **Logs:**
   - Android: `adb logcat -s flutter`. Discovery lines start with `[crossdrop.discovery]`, for example `PeerAdded aaaaaaaa`, `advertising on port 53317`, `network changed: 1 address(es)`.
   - iPhone: `flutter logs -d <iphone-id>` on the Mac.
   - Logs contain ids, ports and counts only, never names or QR contents.

Wording below: "**Receive**" means open CrossDrop > Receive and leave it open. "**Nearby**" means CrossDrop > Send, which now opens the "Send to" list.

### P2-1: Home Wi-Fi, Android finds iPhone

1. iPhone: **Receive**. If iOS asks to find devices on the local network, tap **Allow**.
2. iPhone: the screen shows "Ready to receive as Test iPhone", "Phones on this Wi-Fi see you in their nearby list", and a QR code.
3. Android: **Nearby**. Start a stopwatch.
4. Android: when "Test iPhone" appears, note the time. Tap it.
5. Android: the Send screen opens with "To Test iPhone" and the IP and port filled in. Pick a small file and send it.
6. Optional multicast lock check, while Nearby is open on Android: `adb shell dumpsys wifi | findstr /i multicast`. Then go back to Home and run it again.

**Expected**
- "Test iPhone" appears within 5 s, with an iPhone icon. The subtitle shows the iPhone's IP and port; they match the iPhone's Receive screen.
- Send works and ends with "Done, SHA-256 verified by receiver".
- Step 6: a multicast lock (tag `bonsoirMulticastLock`) is listed while Nearby is open, and gone after leaving it. If the output has no lock list at all on your Android version, note "not checked".

**Paste back:** the seconds until it appeared, a screenshot of the Android list, the `adb logcat -s flutter` lines from opening Nearby to the end of the send, and the step 6 output.

### P2-2: Home Wi-Fi, iPhone finds Android

Same as P2-1 with roles swapped: Android on **Receive**, iPhone on **Nearby**.
- If this is the iPhone's first discovery, iOS shows the Local Network prompt when Nearby opens. Tap **Allow**.

**Expected**
- "Test Android A" appears within 5 s (within about 5 s of tapping Allow on first run), with an Android icon.
- Tapping it opens Send pre-filled, and the send works.
- No "Local Network" explanation screen appears.

**Paste back:** as P2-1, with iPhone logs if you have them.

### P2-3: iOS Local Network denied, then granted

1. iPhone: Settings > Privacy & Security > Local Network > **turn CrossDrop off**.
2. Android: **Receive**.
3. iPhone: **Nearby**. Wait up to 20 s.
4. Tap **Open Settings**. In CrossDrop's settings page, turn **Local Network** on and return to CrossDrop with the app switcher or the "< CrossDrop" link.
5. Wait up to 20 s.
6. Optional, fresh-install variant: delete the app, reinstall, open **Nearby**, and tap **Don't Allow** on the prompt. Then repeat steps 3 to 5.

**Expected**
- Step 3: after about 13 s (5 s search plus the 8 s probe), the screen "CrossDrop needs Local Network access" appears, with Open Settings, Try again and Scan a QR code anyway.
- Step 4: Open Settings opens CrossDrop's page in the Settings app.
- Step 5: the explanation goes away and "Test Android A" appears in the list.
- The app never freezes or crashes.

**Paste back:** screenshots of step 3 and step 5, how many seconds each took, and the iPhone log lines containing `local network probe`.

### P2-4: QR code when discovery is blocked

**Part A: QR path, both directions (any network).**
1. Android: **Receive**. iPhone: **Nearby** > **Scan QR code**. The first time, iOS asks for the camera: Allow. Point the camera at the Android QR code.
2. Expected: the scanner closes and Send opens with "To Test Android A". Send a small file.
3. Swap roles: iPhone on **Receive**, Android on **Nearby** > **Scan QR code** (allow the camera).

**Part B: discovery actually blocked.** Use one of these:
- (a) A network known to block mDNS, such as many office or guest networks, or a router with "IGMP snooping", "multicast enhancement" or "mDNS" filtering turned on.
- (b) If you have none: on the iPhone (sender) only, turn Local Network off as in P2-3. The QR connect is then also expected to fail; record that. On iOS, Local Network blocks both discovery and connections.

Then:
4. Receiver: **Receive**. Sender: **Nearby**. Wait 10 s.
5. Expected: the list stays empty, then shows "No phones found yet" and the hint to scan the QR code.
6. Sender: **Scan QR code** on the receiver's code.
   - Expected with (a): Send opens and the send works.
   - Expected with (a), if the network also isolates clients: within 5 s the message "Could not connect. This Wi-Fi may block phone-to-phone traffic, or a VPN is on. Try a hotspot."

**Part C: wrong codes.**
7. Sender: **Scan QR code** on any other QR code, for example a website, a Wi-Fi sharing code, or a payment QR.
8. Expected: "This is not a CrossDrop code…" under the camera view; the scanner stays open and nothing connects.
9. Android: in system Settings > Apps > CrossDrop > Permissions, deny Camera, then open the scanner.
   - Expected: "CrossDrop needs the camera…" and an Open Settings button that opens CrossDrop's App info page.

**Paste back:** for each part, what you saw (screenshots welcome, but do not post the QR codes themselves), which network type you used for Part B, and the logs.

### P2-5: Wi-Fi switched mid-session

Needs Wi-Fi A and Wi-Fi B (see Preparation).

1. Both phones on Wi-Fi A. Android: **Receive**. Note its IP. iPhone: **Nearby**, wait until "Test Android A" is listed.
2. **Android only:** switch to Wi-Fi B in quick settings. Keep Receive open.
3. Within about 5 s, the Android Receive screen should show the new IP (the QR code is redrawn). Note how long it took.
4. Watch the iPhone list for 30 s. Note whether, and when, "Test Android A" disappears. It may stay, because the iPhone cannot see network B.
5. If it is still listed, tap it.
   - Expected: within about 5 s, "Could not reach that phone…", and the entry disappears.
6. **iPhone:** switch to Wi-Fi B. The list should restart and show "Test Android A" again within about 10 s, with the new IP. Tap it and send a small file.
7. Repeat steps 1 to 6 with roles swapped: iPhone on Receive, Android on Nearby, and the iPhone switching networks first.

**Expected:** Receive shows the new address within about 5 s of the switch. The sender finds the receiver again once both are on the same network. A stale entry is removed when tapped. No crash, and no Receive restart needed.

**Paste back:** the timings from steps 3, 4 and 6 for both directions, and logs from both phones (look for `network changed`, `advertising restarted`, `browsing started`).

### P2-6: Two Android phones and one iPhone

1. Android A and Android B: **Receive**. iPhone: **Nearby**.
   - Expected: both "Test Android A" and "Test Android B" are listed, with Android icons and different IPs, sorted by name, within 5 s.
2. Android B: leave Receive (back to Home). Start a stopwatch.
   - Expected on the iPhone: "Test Android B" disappears. Note how long it took (up to about 2 minutes is acceptable for now; record what you see).
3. Android B: Settings > rename to "Test Android B2". Open **Receive** again.
   - Expected on the iPhone: one entry "Test Android B2", not two entries for B.
4. iPhone and Android B: **Receive**. Android A: **Nearby**.
   - Expected: "Test iPhone" (iPhone icon) and "Test Android B2" listed.
   - Tap each in turn and send a small file to each; both work.
5. Android A: pull down on the list.
   - Expected: the list empties and both devices come back within 5 s.
6. Each phone never lists itself.

**Paste back:** a screenshot of each list, the disappearance time in step 2, and logs from the phone on Nearby.

### P2-7: Manual address

1. Android: **Receive**. Note the IP (`wlan0`) and port.
2. iPhone: **Nearby** > **Enter IP**. Try these:
   - `8.8.8.8` → "Use the local address shown on Receive"
   - `192.168.1` → "Enter an address like 192.168.1.23"
   - port `0` → "Enter the port shown on Receive"
3. Enter the right IP with a wrong port.
   - Expected: within about 5 s, "Could not reach that phone…".
4. Enter the right IP and port.
   - Expected: Send opens with "To Test Android A"; send a small file.
5. Swap roles, with Android on Nearby (the iPhone IP is the `en0` line).

**Paste back:** what each step showed.

### Results

| Check | Date | iPhone, iOS | Android(s), version | Commit | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| P2-1 | | | | | | |
| P2-2 | | | | | | |
| P2-3 | | | | | | |
| P2-4 A | | | | | | |
| P2-4 B | | | | | | |
| P2-4 C | | | | | | |
| P2-5 Android switches | | | | | | |
| P2-5 iPhone switches | | | | | | |
| P2-6 | | | | | | |
| P2-7 | | | | | | |


## Phase 3: transfer engine, resume, keep-alive

Feature docs: [features/transfer-engine.md](features/transfer-engine.md), [features/resume.md](features/resume.md), [features/keep-alive.md](features/keep-alive.md). Speeds go in [BENCHMARKS.md](BENCHMARKS.md).

### Preparation (once)

1. **Build both phones from the same commit:** run the Build workflow and install both artifacts ([Installing the CI builds](#installing-the-ci-builds-no-mac-needed)). This is the first iPhone build with the `crossdrop/storage` and `crossdrop/background` Swift channels. If the iPhone job fails in `AppDelegate.swift`, paste the red lines back and stop.
2. **Phases 1 and 2 data:** the database moves to schema version 2 on first launch. Nothing to do, but if the app crashes on launch, paste the logs.
3. **Test files:** make `crossdrop-1GB.bin` and `crossdrop-2GB.bin` on the PC with the `New-RandomFile` function from Phase 1, preparation step 2 (`New-RandomFile "crossdrop-2GB.bin" 2GB`). Keep their SHA-256 values. Copy both to both phones (Phase 1, step 3). For P3-7 you also need 10 photos and short videos in the Android Downloads folder or Gallery, and in the iPhone Files app.
4. **Free space:** about 6 GB free on each phone. On iPhone, picked files are copied by the file picker before sending, and the receiver needs room for the file.
5. Both phones on the same home Wi-Fi, VPN off. Give them distinct names in Settings ("Test iPhone", "Test Android").
6. **Logs:**
   - Android: `adb logcat -s flutter`. New areas: `[crossdrop.send]`, `[crossdrop.server]`, `[crossdrop.keepalive]`, `[crossdrop.storage]`.
   - iPhone: logs need a Mac (`flutter logs`) or `idevicesyslog` from libimobiledevice on Windows, filtered on `crossdrop`. If you have neither, screenshots are enough.
   - Logs contain session and file ids, byte counts and states; never names or contents.

Wording below:
- "**Receive**" means CrossDrop > Receive, left open.
- "**Send to X**" means CrossDrop > Send > tap X in the list > **Add files** > pick > **Send**.

To check a received file's hash on Android:
- `adb shell sha256sum /sdcard/Android/data/io.github.shreyashjunje.crossdrop/files/CrossDrop/<name>`
- Or send it back to the PC with `adb pull` and use `Get-FileHash`.

On iPhone, received files are in Files > On My iPhone > crossdrop > CrossDrop.

### P3-1: 1 GB and 2 GB, both directions

Four runs: 1 GB iPhone → Android, 1 GB Android → iPhone, 2 GB iPhone → Android, 2 GB Android → iPhone. For each run:

1. Receiver: **Receive**.
2. Sender: **Send to** the receiver with the file. Start a stopwatch.
3. Receiver: the Accept prompt shows "Test iPhone wants to send you", "1 file · 1073.7 MB" (or 2147.5 MB) and the file name. Tap **Accept**.
4. Android, the first time on Android 13 or later: the system asks to allow notifications. Tap **Allow**. Then pull down the notification shade during the transfer.
5. Watch both screens until the end. Stop the stopwatch.

**Expected**
- **Sender:** "Waiting for the other phone to accept…", then "Sending" with size, MB/s and time left, all moving. The file row ends with a check mark, then "Done, SHA-256 verified by the receiver".
- **Receiver:** a card "From Test iPhone · 1 file" with a progress bar, speed and time left. It ends "Done, SHA-256 verified".
- **Android:** a notification "Sending to …" or "Receiving from …" whose percentage moves, at most once per second. It disappears at the end.
- **Both:** neither screen locks during the transfer, and both apps stay responsive (scrolling, no freezes).
- The received file's SHA-256 equals the PC value (Android: `sha256sum`; iPhone: send it back to Android, then `sha256sum`).
- 2 GB is about twice the 1 GB time.

**Paste back:**
- For each run: time, average MB/s, and the hash comparison.
- A screenshot of the Android notification.
- Sender logs from `offered` to `done`.
- Roughly how warm each phone got.

### P3-2: Accept prompt

1. Android: **Receive**. iPhone: **Send to** Android with a small file. On Android tap **Decline**.
2. Repeat, but do not answer on Android for 70 s.
3. Repeat, and on iPhone tap **Cancel** while Android still shows the prompt.
4. Send one more small file and tap **Accept**.

**Expected**
1. iPhone: "The other phone declined." Android card: "Declined".
2. After 60 s the Android prompt closes by itself. iPhone: "The other phone did not answer in time." Android: "Not answered in time".
3. The Android prompt closes. Android: "Cancelled by the sender". iPhone: "Cancelled".
4. It sends normally: steps 1 to 3 left no open session behind, so there is no "unfinished transfer" refusal.

**Paste back:** what each step showed (screenshots welcome), and logs from both phones.

### P3-3: Wi-Fi off and on mid-transfer

Use 1 GB. Run it for both directions, and for each direction turn off Wi-Fi first on the **sender**, then (a second run) on the **receiver**.

1. Start the send and accept it. At about 30%, turn Wi-Fi **off** on the chosen phone (Control Center or quick settings, so the phone stays on the screen).
2. Within about 15 s, the sender shows "Connection lost. Trying again in N s…" and the receiver card shows "Paused at …".
3. After 20 s, turn Wi-Fi back **on** (same network). Do not tap anything.
4. **Long outage:** repeat once with Wi-Fi off for **3 minutes**. After about 2 minutes, the sender should show "Lost the connection for 2 minutes… tap Resume". Turn Wi-Fi on and tap **Resume**.

**Expected**
- Step 3: within about 10 s of Wi-Fi coming back, the sender continues by itself from about 30%, not from 0. Both sides end verified, and the hash matches.
- Step 4: Resume continues from where it stopped and ends verified.
- If the receiver's IP changed (watch Receive), the sender log shows `receiver moved, trying the new address` and continues.

**Paste back:**
- For each run: seconds from Wi-Fi on to bytes moving again.
- The sender's `sending from N of 1073741824` lines (N must grow, never go back to 0).
- Screenshots of the "Trying again" and "Paused" states.
- Logs from both phones.

### P3-4: Lock the screen mid-transfer

Use 1 GB.

**A. iPhone sends, Android receives**
1. At about 30%, press the iPhone side button to lock it. Wait 30 s. Unlock and return to CrossDrop.

**B. Android sends, iPhone receives**
2. At about 30%, lock the iPhone (the receiver). Wait 30 s, unlock and return to CrossDrop with **Receive** still open.

**C. Android with the screen off**
3. Android sends to the iPhone. Lock the **Android** phone for 60 s.
4. Then the reverse: Android receives, and its screen is locked for 60 s.

**Expected**
- **A:** while locked, the Android card shows "Paused". On unlock the iPhone shows "Paused while CrossDrop is in the background" for a moment, then continues from about where it stopped, and ends verified.
- **B:** the Android sender shows "Connection lost. Trying again…" while the iPhone is locked, then continues within about 10 s of unlocking, and ends verified.
- **C:** the transfer **keeps going** with the Android screen off. The progress on the other phone keeps moving, and the Android notification stays.

**Paste back:**
- For A and B: seconds from unlock to bytes moving.
- iPhone logs if you have them (`background: saving 1 transfer(s)`).
- For C: whether progress kept moving with the screen off.
- The Android brand and model. Some brands kill background work; if the transfer stopped in C, also say whether CrossDrop is set to "No restrictions" in battery settings.

### P3-5: Force-close the receiving app and resume

Use 1 GB. Run it once with Android receiving and once with the iPhone receiving.

1. Start the send and accept it. At about 40%, force-close CrossDrop on the **receiver**:
   - iPhone: swipe up from the bottom, then swipe CrossDrop away.
   - Android: Recents, then swipe it away. Or Settings > Apps > CrossDrop > **Force stop**.
2. The sender shows "Connection lost. Trying again…".
3. Within 1 minute, open CrossDrop again on the receiver.
4. Expected: the dialog "Unfinished transfers" with "Receiving 1 file from Test …, about 40% of 1.07 GB done". Tap **Resume**. Receive opens.
5. Do nothing on the sender.
6. **Sender side variant** (once, either direction): force-close the **sender** at about 40%, reopen it, and in "Unfinished transfers" tap **Resume** on "Sending 1 file to …".

**Expected**
- Step 5: within about 15 s the sender finds the receiver at its new port (log: `receiver moved, trying the new address`). It continues from about 40% and ends verified, and the hash matches.
- If you were slower than 2 minutes, the sender shows "Lost the connection…". Tapping Resume works once Receive is open.
- Step 6: Send opens, continues from about 40% and ends verified.
- No duplicate file: Files or Downloads has one copy, not `name (1).bin`.

**Paste back:**
- Screenshots of the "Unfinished transfers" dialog.
- Seconds from Receive opening to bytes moving.
- Receiver logs (`restored, paused`).
- Sender logs (`receiver moved`, `sending from`).

### P3-6: Cancel from each side

Use 1 GB, iPhone → Android, then repeat Android → iPhone.

1. At about 30%, tap **Cancel** on the **sender**.
2. New send: at about 30%, tap **Cancel** on the **receiver's** card.
3. New send: tap Cancel on the sender while the receiver still shows the Accept prompt (as P3-2 step 3, other direction).
4. After each cancel, start a fresh small send between the same phones.

**Expected**
- Steps 1 and 2: both phones show a cancelled state within about 2 s:
  - Sender: "Cancelled" (step 1) or "Cancelled by the other phone" (step 2).
  - Receiver: "Cancelled by the sender" (step 1) or "Cancelled" (step 2).
  - The receiver's free space returns (Android: Settings > Storage; iPhone: Settings > General > iPhone Storage > CrossDrop does not keep growing by 300 MB per run).
- Step 4: the small send works every time (no "unfinished transfer" refusal).
- Nothing partial appears in Files, Downloads or the CrossDrop folder.

**Paste back:** screenshots of both phones after each cancel, and logs (`cancelled by sender` / `cancelled by receiver`).

### P3-7: Ten files at once

Both directions.

1. Sender: **Add files**, pick 10 files at once: photos, a few short videos, and one document. Add them in two rounds if the picker allows only one selection.
2. Send. The receiver gets **one** Accept prompt listing 5 names and "and 5 more".

**Expected**
- One prompt; the total size matches the sum.
- Files go one after another (each row reaches 100% before the next starts). The total bar and time left move steadily.
- The receiver card ends "Done, SHA-256 verified" with 10 check marks. All 10 files are in the save folder with their original names. Files with the same name get " (1)".
- Optional: turn Wi-Fi off and on once in the middle (as P3-3). The transfer continues with the current file, and no file is sent twice.

**Paste back:** screenshots of both cards at the end, total time, and the sender log (`file f0: saved` … `file f9: saved`).

### Not checked on devices

The 24-hour cleanup of partial files, hostile names, wrong sizes, hash mismatches and many-small-file runs are covered by unit tests. They are hard to trigger by hand.

### Results

| Check | Date | iPhone, iOS | Android, version | Commit | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| P3-1 1 GB iPhone → Android | | | | | | |
| P3-1 1 GB Android → iPhone | | | | | | |
| P3-1 2 GB iPhone → Android | | | | | | |
| P3-1 2 GB Android → iPhone | | | | | | |
| P3-2 | | | | | | |
| P3-3 sender Wi-Fi, both directions | | | | | | |
| P3-3 receiver Wi-Fi, both directions | | | | | | |
| P3-3 3-minute outage | | | | | | |
| P3-4 A | | | | | | |
| P3-4 B | | | | | | |
| P3-4 C | | | | | | |
| P3-5 Android receiver killed | | | | | | |
| P3-5 iPhone receiver killed | | | | | | |
| P3-5 sender killed | | | | | | |
| P3-6 iPhone → Android | | | | | | |
| P3-6 Android → iPhone | | | | | | |
| P3-7 iPhone → Android | | | | | | |
| P3-7 Android → iPhone | | | | | | |

## Phase 4: security, pairing and trust

Feature docs: [features/device-identity.md](features/device-identity.md), [features/pairing-and-trust.md](features/pairing-and-trust.md), [features/abuse-limits.md](features/abuse-limits.md).

### Preparation (once)

1. **Build both phones from the same commit** and install over the Phase 3 app, without deleting it first ([Installing the CI builds](#installing-the-ci-builds-no-mac-needed)). This is the first build with `flutter_secure_storage`. If the iPhone or Android job fails, paste the red lines and stop.
2. **Upgrade check:** open the app on both phones. The database moves to schema 3, and a new identity is created. Expected: the app opens normally. Settings shows a line "Security key xxxx xxxx xxxx xxxx". An unfinished Phase 3 transfer, if any, cannot resume: sending says "started by an older version … send the files again". Write down each phone's security key.
3. **The PC as a third device:** on the PC, in the repo, on the same Wi-Fi, check that `dart run tool/crossdrop_cli.dart` prints its usage. Each run of this tool is a new unknown device. A third phone works too, if you have one.
4. A small test file on each phone (any photo) and `small.bin` on the PC (any file of a few MB).
5. Names in Settings: "Test iPhone" and "Test Android". Both phones on the same home Wi-Fi, VPN off. Receiving on (the default).
6. **Logs:** as in Phase 3. New lines:
   - `[crossdrop.identity] created, fingerprint 1a2b3c4d`
   - `[crossdrop.server] sender 1a2b3c4d authenticated`
   - `authentication refused: …`
   - `rate limited …`
   - `session …: auto-accepted (trusted device)`
   Logs show only the first 8 characters of a fingerprint; never a key or a file name.

### P4-1: Pairing from the nearby list, both directions

For each direction (iPhone → Android, then Android → iPhone):

1. Receiver: **Receive**.
2. Sender: **Send** > tap the receiver in the list > **Add files** > one photo > **Send**.
3. Expected on the sender, under "Waiting for the other phone to accept…": "Check that the other phone shows this code:" and a 6-digit code such as `482 913`.
4. Expected on the receiver: the Accept prompt with "Check that the other phone shows this code:", **the same 6 digits**, and a "Trust this device" checkbox. The button says **Codes match, accept**.
5. Tick **Trust this device**, tap **Codes match, accept**. The file arrives as in Phase 3.
6. On the sender, after "Done": tap **Trust Test …** (the button under the status).
7. Both phones: Settings > Trusted devices lists the other phone, with the first 16 characters of its security key, matching the key you noted in preparation step 2.
8. Send another photo the same way. Expected: **no code** on either phone. The receiver still shows the Accept prompt (plain **Accept** button).

**Paste back:** a photo or screenshots of both screens at step 3–4 (the two codes side by side), screenshots of both Trusted devices lists, and the receiver log line `sender xxxxxxxx authenticated`.

### P4-2: QR pairing, then a tampered QR

1. Forget each other first: on both phones, Settings > Trusted devices > delete icon > **Forget**.
2. Android: **Receive**. iPhone: **Send** > **Scan QR code** > scan the Android QR > add a photo > **Send**. Expected: it connects, and both phones show the same code (the receiver cannot tell that the sender scanned a QR). Accept; the file arrives.
3. **Tampered QR:** on the Android Receive screen, note the IP and port. On the PC run:
   `dart run tool/crossdrop_cli.dart fake-qr <android-ip> <port>`
   This writes `fake-qr.svg`: the real IP and port, a wrong fingerprint. Open it in a browser on the PC.
4. iPhone: **Send** > **Scan QR code** > scan the QR on the PC screen.
5. Expected on the iPhone: "This isn't the device you scanned: its security key is different. Nothing was sent." No Send screen opens.
6. Expected on Android: no Accept prompt, nothing received.
7. Repeat steps 3–6 the other way: iPhone Receive, Android scans a fake QR made with the iPhone's IP and port.

**Paste back:** screenshots of the error on both phones, and the receiver's log around that time: there must be **no** `authenticated` line from the scan.

### P4-3: A third device on the same Wi-Fi tries to send without pairing

The PC CLI is the third device (or a third phone, if you have one; then use its Send screen with a typed address).

1. **Receiving on.** Android: **Receive**. On the PC:
   `dart run tool/crossdrop_cli.dart send <android-ip> <port> small.bin`
   Expected:
   - The PC prints `Pairing code: 123 456`.
   - Android shows an Accept prompt from "CrossDrop" with the **same code**, and no lookalike warning.
   - Tap **Decline**. The PC reports that the receiver answered `rejected`. Nothing is saved.
2. **Receiving off.** On the Android Receive screen, switch **Receiving** off. Expected: the QR code disappears, and the screen says it is off once nothing is running. On the iPhone, the Android phone leaves the nearby list within about 10 s (pull to refresh).
   Run the PC command again (with the same port; if the server already stopped, you get a connection error, which also passes). Expected:
   - With the server still up: the PC gets `receiving_off` (403), and Android shows "Refused a transfer from an untrusted device: receiving is off."
   - No Accept prompt.
3. **Trusted device while off.** Switch Receiving on, then off again while the iPhone (trusted since P4-2, if you trusted it there; otherwise trust it first) sends a photo from its still-open Send screen within a few seconds. Expected: the offer goes through. This is optional; the timing is tight.
4. **Rate limit.** Switch Receiving on. On the PC, run the send command 4 times within a minute, declining each prompt on Android. Expected: the 4th run fails with `rate_limited`. Android shows at most 3 prompts.
5. Repeat 1–2 with the iPhone as receiver.

**Paste back:** the PC output for each run, screenshots of the prompt with the code and of the "receiving is off" notice, and the receiver log lines `rate limited`.

### P4-4: Trusted device with and without auto-accept

The phones trust each other (P4-1 or P4-2).

1. **Without auto-accept** (the default): iPhone sends a photo to Android. Expected: no code, Accept prompt shown. Accept; it arrives.
2. **With auto-accept:** Android > Settings > Trusted devices > switch on auto-accept for Test iPhone. iPhone sends a photo. Expected: **no prompt**, the file arrives by itself. Android log: `auto-accepted (trusted device)`.
3. **Auto-accept is per key, not per name:** on the PC, run `dart run tool/crossdrop_cli.dart send …` to Android. Expected: a prompt with a code; the PC is not auto-accepted.
4. Switch auto-accept off again and send once more. Expected: the prompt is back.
5. Repeat 1–4 with the iPhone as receiver.

**Paste back:** screenshots of the Trusted devices list with the switch, and the receiver log for step 2.

### P4-5: Lookalike warning (same name, different key)

Needs P4-6 first (a reinstalled phone with a new key), or a third phone. With the PC:

1. Android trusts the iPhone ("Test iPhone").
2. A device with another key uses that name: after P4-6, on the reinstalled iPhone, set the name back to "Test iPhone" in Settings.
3. iPhone sends a photo to Android. Expected on Android: the Accept prompt has a red box: "Warning: this is not the "Test iPhone" you trusted. Its security key is different…". The code is shown. Decline.
4. The other way: Android trusts "Test iPhone" and opens Send > taps "Test iPhone" in the nearby list. Expected: a dialog "Not the "Test iPhone" you trusted" with **Stop** and **Continue anyway**. **Continue anyway** opens Send with a red warning, and the code check runs as for a new device.

**Paste back:** screenshots of the red box and of the dialog.

### P4-6: Reinstall changes the identity and loses trust

Do this on the iPhone first. iOS keeps Keychain items after an app is deleted, so this is the important case.

1. Note the iPhone's security key (Settings). The Android phone trusts the iPhone.
2. Delete CrossDrop from the iPhone (long press > Remove App > Delete App). Install it again with Sideloadly.
3. Open it. Expected:
   - Settings shows a **different** security key and an empty Trusted devices list.
   - The name is back to "iPhone".
   - Log: `identity created, fingerprint …` with a new value.
4. iPhone sends a photo to Android. Expected: Android shows a code (it does not trust this new key). If you renamed the iPhone to "Test iPhone", also the lookalike warning (P4-5).
5. On Android, Settings > Trusted devices still lists the old "Test iPhone" (old key). Forget it, then pair again (P4-1) to trust the new key.
6. Repeat 1–5 with Android (uninstall from Settings > Apps, then install the APK again). Android backup is off, so nothing is restored.

**Paste back:** screenshots of Settings before and after on each phone (security key line and Trusted devices list).

### P4-7: Receiving switch and new port

1. Receive screen: switch **Receiving** off. Expected: "Receiving is off. Turn it on to receive files." and no QR. The other phone's nearby list drops this phone.
2. Close and reopen Receive. Expected: still off (the switch is saved). Settings shows the same switch, off.
3. Switch it on. Expected: Starting…, then a QR code and a **new port number**. The other phone finds it again.

**Paste back:** the two port numbers, and screenshots of the off state.

### Not checked on devices

Covered by unit tests, hard to do by hand:
- A forged or relayed signature, a reused challenge, a commitment mismatch.
- The chain-substitution attack on pinning.
- Another sender reading or feeding someone else's session.
- Oversized headers and bodies.
- Expiry of challenges and tokens.

### Results

| Check | Date | iPhone, iOS | Android, version | Commit | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Upgrade from Phase 3 (prep step 2) | | | | | | |
| P4-1 iPhone → Android | | | | | | |
| P4-1 Android → iPhone | | | | | | |
| P4-2 QR | | | | | | |
| P4-2 tampered QR, iPhone scans | | | | | | |
| P4-2 tampered QR, Android scans | | | | | | |
| P4-3 Android receiver (on, off, rate limit) | | | | | | |
| P4-3 iPhone receiver (on, off) | | | | | | |
| P4-4 Android receiver | | | | | | |
| P4-4 iPhone receiver | | | | | | |
| P4-5 | | | | | | |
| P4-6 iPhone reinstall | | | | | | |
| P4-6 Android reinstall | | | | | | |
| P4-7 | | | | | | |

## Phase 5: media, saving and sharing from other apps

Feature docs: [features/media-picking.md](features/media-picking.md), [features/saving-received-files.md](features/saving-received-files.md), [features/format-handling.md](features/format-handling.md), [features/share-from-other-apps.md](features/share-from-other-apps.md).

### Preparation (once)

1. **Build both phones from the same commit** and install over the Phase 4 app without deleting it ([Installing the CI builds](#installing-the-ci-builds-no-mac-needed)).
   - This is the first build with the Share Extension and new Swift files. If the **iPhone unsigned IPA** job fails, paste its red lines and stop: nothing on iOS in Phase 5 has been compiled before this job.
   - **Android 10 or newer is required now** (D-035).
   - **Sideloadly and the extension:** the `.ipa` now contains `PlugIns/ShareExtension.appex`, which uses an App Group (`group.io.github.shreyashjunje.crossdrop`). Sideloadly signs the extension as a second app id; a free Apple ID allows 10 new app ids per 7 days. If Sideloadly reports an error about app groups or the extension, paste its log. If you changed the bundle id in Sideloadly, sharing may say "not available in this installation" (P5-9 step 6); the rest of Phase 5 still works.
2. **Upgrade check:**
   - iPhone: open CrossDrop, then the **Files** app > Browse > On My iPhone > **CrossDrop**. Expected: **no** `crossdrop.sqlite` file (it moved to a hidden folder). Files received in earlier phases are still there, in a `CrossDrop` subfolder.
   - Both: Settings, Trusted devices and the security key are unchanged; the app opens normally.
   - iPhone: Settings in CrossDrop now has "Sending photos to Android" with two switches, both off.
3. **Test files.**
   - On the iPhone (take them fresh, **do not edit** them; an edited photo is sent as its edited version and will not hash-match the original):
     - a 4K 60 fps video of about 30 s (Settings > Camera > Record Video > 4K at 60 fps, Formats > High Efficiency)
     - a HEIC photo
     - a JPEG (Settings > Camera > Formats > Most Compatible, take one, set it back)
     - a Live Photo
     - a screenshot (PNG)
     - a PDF and a ZIP in Files (any; Files can compress a folder into a ZIP)
   - On Android:
     - a JPEG photo
     - a PNG screenshot
     - a video
     - if the phone can, a HEIC photo
     - a PDF and a ZIP in Downloads
4. **On the PC:**
   - MediaInfo (mediaarea.net) to compare videos.
   - `adb` for pulling Android files.
   - Windows **Photos** (or File Explorer) to import from the iPhone.
   - On the iPhone, set Settings > Photos > Transfer to Mac or PC > **Keep Originals**, so Windows gets the original HEIC and MOV files.
5. **Hashes on the PC:** in PowerShell, `Get-FileHash -Algorithm SHA256 <file>` (or `certutil -hashfile <file> SHA256` in cmd).
6. **Logs:** as in Phase 4. New lines:
   - `[crossdrop.prepare] item 2 skipped (icloud)`
   - `[crossdrop.server] file f1: verified and saved (123 bytes, photos)` (the last word is `photos`, `videos` or `files`, then `unsupported` or `permission` if it fell back)
   - `[crossdrop.store] file f1: pending item gone`
   - `[crossdrop.photos] save refused (unsupported)`
   - `[crossdrop.share] …`
   No file names appear in logs.

### P5-1: 4K iPhone video to Android, same size and quality

1. Android: **Receive**. iPhone: **Send** > the Android phone > **Photos & videos** > the 4K video > **Add 1** > **Send**.
2. Expected on the iPhone: "Preparing 1 of 1…" briefly, then the code check (if not trusted) and sending. On Android: Accept, progress, then under the file "Saved to Movies/CrossDrop".
3. Android: open the gallery (Google Photos or the maker's gallery). Expected: the video is there, under its date of recording (not today, unless you recorded it today), and it plays.
4. Compare:
   - On the PC, import the original from the iPhone (Keep Originals) and run `adb pull /sdcard/Movies/CrossDrop/IMG_XXXX.MOV`.
   - Hash both files; expected **equal**.
   - In MediaInfo, compare on both files: Format (HEVC), Width × Height (3840 × 2160), Frame rate, Bit rate, HDR format (if any) and Duration. Expected **identical**.
   - On the phone, look at the playback: does HDR look right, or washed out? Write down which.

**Paste back:**
- Both hashes.
- MediaInfo "Video" sections of both files (Text view).
- The Android player and model, and whether HDR looked right.
- The receiver log line `verified and saved (… videos)`.

### P5-2: Formats, iPhone → Android

Send in one go: HEIC, JPEG, Live Photo, screenshot (Photos & videos), then PDF and ZIP (**Files**). Both settings off.

Expected on Android:

| Item | Received as | Where (shown under the file) | Gallery |
| --- | --- | --- | --- |
| HEIC | `IMG_….HEIC`, same hash as the original | Pictures/CrossDrop | Opens (most phones; write down if not) |
| JPEG | `IMG_….JPG`, same hash | Pictures/CrossDrop | Opens |
| Live Photo | only the still, `IMG_….HEIC` | Pictures/CrossDrop | A still photo |
| Screenshot | `IMG_….PNG` | Pictures/CrossDrop | Opens; note its date |
| PDF, ZIP | same names, same hash | Download/CrossDrop | In Files > Downloads > CrossDrop |

Then turn on both settings on the iPhone (Settings > Sending photos to Android) and send the HEIC and the Live Photo again. Expected: `IMG_….JPG` for the HEIC (opens everywhere, location and date kept: check photo details), and for the Live Photo both `IMG_….JPG` and `IMG_….MOV` (the 3-second video plays). Turn both settings off again.

**Paste back:** a screenshot of the Receive screen with the "Saved to …" lines, and the gallery's details (date, location) of the converted JPEG.

### P5-3: Formats, Android → iPhone

Send in one go from Android: JPEG, PNG screenshot, video, HEIC (if you have one), PDF, ZIP. If you have a `.webm` or `.mkv` file, add it.

Expected on the iPhone:
- Photos and the video appear in **Photos** (Recents), under their original date.
- PDF and ZIP are in Files > On My iPhone > CrossDrop.
- A WebM/MKV is in the same Files folder, with the note "(Photos cannot import this format)" under it on the Receive screen.
- The first time, iOS asks "CrossDrop would like to add to your Photos" right after you tap Accept. Tap **Allow**.

Then: iPhone Settings > Privacy & Security > Photos > CrossDrop > **None**. Send a JPEG again. Expected: it lands in Files with the note "(CrossDrop may not add to Photos)". Set it back to **Add Photos Only**.

**Paste back:** screenshots of the Receive screen and of the Files folder, and the log lines `verified and saved (…)`.

### P5-4: iCloud-only photo

Needs iCloud Photos with **Optimize iPhone Storage** on, and a photo whose original is only in iCloud (an older one, or one taken on another device). A small thumbnail and a cloud icon in Photos > info is a good sign.

1. **Offline:** turn on Airplane Mode, then turn Wi-Fi back on (same Wi-Fi as Android, so no internet if your router has none, otherwise use the Android hotspot without mobile data). Pick that photo plus one local photo > Send.
   Expected: "Preparing 1 of 2…", then after at most about 90 s: "1 item is not sent: IMG_…: only in iCloud and could not be downloaded…". The local photo is sent. Log: `item 0 skipped (icloud)`.
2. **Online:** with internet, send the iCloud photo again. Expected: "Preparing 1 of 1: downloading from iCloud 40%" rising, then it sends. The received file is the full-size original (several MB, not a thumbnail).
3. **Cancel while downloading:** pick a large iCloud-only video, Send, and tap **Cancel** during "downloading from iCloud". Expected: back to the selection, nothing offered to Android.

**Paste back:** screenshots of the skip message and of the download progress, and the sizes of the received file and the original.

### P5-5: Limited photo access

1. iPhone Settings > Privacy & Security > Photos > CrossDrop > **Limited Access**, choose 2 photos.
2. CrossDrop: Send > **Photos & videos**. Expected: only those 2, and the banner "CrossDrop can see only the photos you allowed" with **Select more** and **Settings**.
3. **Select more** > add a third > Done. Expected: the grid shows 3 at once, without reopening.
4. Pick one, go back, then in iOS Settings remove that photo from the allowed set, and Send. Expected: "1 item is not sent: …: no longer in your library, or not shared with CrossDrop."
5. Set access to **None**, open Photos & videos. Expected: "CrossDrop has no access to your photos" with **Open Settings**; Files still works.
6. Android 14+: Settings > Apps > CrossDrop > Permissions > Photos and videos > **Allow limited access**. Repeat 2–3; and **Don't allow** for step 5.

Set access back to Full afterwards.

**Paste back:** screenshots of the banner, of the denied screen, and of the skip message.

### P5-6: Original hash, both directions

Proves that the sent file is the library original, not a copy made for sharing.

1. iPhone → Android: one HEIC photo (unedited). PC: import the original from the iPhone, `adb pull /sdcard/Pictures/CrossDrop/IMG_….HEIC`. Hash both. Expected **equal**.
2. Android → iPhone: one JPEG from the camera. PC: `adb pull /sdcard/DCIM/Camera/<name>.jpg`; on the iPhone it is in Photos; import it on the PC (Keep Originals). Hash both. Expected **equal**.
   - If not equal, check whether the photo has a location. Expected: the received photo has the **same location**. CrossDrop asks Android for the unredacted original (D-037).

**Paste back:** the four hashes, and whether the location was kept.

### P5-7: Interruptions while saving to the gallery

1. **Android receiver killed mid-video:** iPhone sends the 4K video. At about 50%, swipe CrossDrop away on Android. Reopen it, open Receive. iPhone resumes (Phase 3 behaviour). Expected: the video completes, plays, has the same hash, and there is **one** copy in Movies/CrossDrop (no half file left).
2. **Cancel mid-video:** send again, cancel on either phone at about 50%. Expected: nothing in Movies/CrossDrop or the gallery. Check also with a file manager that shows hidden files: no `.pending-…` file left in Movies/CrossDrop.
3. **Android full:** fill the Android phone until less than the video's size is free (a big file in Downloads), then send the video. Expected: refused before Accept ("not enough space"). Free some space so it just fits the offer check, fill the rest during the transfer if you can. Expected: "The other phone ran out of space…" and Resume after freeing space.

**Paste back:** screenshots of the gallery and file manager after 1 and 2, and the logs.

### P5-8: Creation dates

For P5-2 and P5-3, open each received item's details:
- **Android gallery:** the date of HEIC, JPEG and video is the original's date. The PNG screenshot: write down whether it shows the screenshot's date or the receive time (a known limit, D-042).
- **Android Files (Downloads):** the PDF's modified time is the original's modified time.
- **iPhone Photos:** every photo and video has its original date (Photos > info).
- **iPhone Files:** "Modified" of the PDF is the original's.

**Paste back:** a short list: item, original date, date shown on the receiver.

### P5-9: Sharing from Photos and Gallery

1. **iPhone Photos:** select 3 items (a photo, a video, a Live Photo) > Share > **CrossDrop** (first time: More > add CrossDrop).
   - Expected: a sheet "Preparing files for CrossDrop…", then CrossDrop opens on the Nearby screen with "3 files ready. Choose the phone to send to." Pick Android > Send screen shows "2 photos, 1 video"… > Send.
   - If CrossDrop does not open by itself, the sheet says "3 files are ready. Open CrossDrop…": tap Done, open CrossDrop; expected the same Nearby screen. Write down which happened.
2. **iPhone Files:** share a PDF from Files > CrossDrop. Same as step 1.
3. **Text:** in Safari, Share a web page > CrossDrop (if listed). Expected: "CrossDrop sends files…".
4. **Android Gallery:** select 3 items > Share > **CrossDrop**. Expected: CrossDrop opens on Nearby with "3 files ready". Send to the iPhone.
5. **Android while receiving:** open Receive on Android, then go to Gallery and share a photo to CrossDrop. Expected: Nearby opens **on top**; going back returns to the Receive screen, still running.
6. If the iPhone share sheet says "Sharing to CrossDrop is not available in this installation", the App Group did not survive sideloading. Paste the Sideloadly log; the in-app pickers are the fallback.
7. **Memory:** share a large video (1 GB or more) from iPhone Photos. Expected: the sheet does not crash; CrossDrop receives it.

**Paste back:** which of the two iPhone outcomes in step 1, screenshots, and the receiver's "Saved to …" lines.

### P5-10: A share from Photos versus the in-app picker

Send the same HEIC photo twice from the iPhone: once with **Photos & videos** in CrossDrop, once via Share from Photos. Hash both on Android. Expected: the in-app one equals the original (P5-6). The shared one may differ (Photos can hand over a JPEG rendering); write down its name and hash.

**Paste back:** both names and hashes.

### Not checked on devices

Covered by unit tests:
- Manifest attacks on the iOS inbox (paths outside the share, links, too many items).
- Refused `file://` and own-package URIs in Android shares: the Kotlin check itself only runs on a phone. To try it, `adb shell am start -a android.intent.action.SEND -t text/plain --eu android.intent.extra.STREAM file:///sdcard/x.txt io.github.shreyashjunje.crossdrop/.MainActivity` should give "1 shared item(s) could not be used."
- A pending item that disappears, MIME types MediaStore refuses, and storage full at insert (fake MediaStore).

### Results

| Check | Date | iPhone, iOS | Android, version | Commit | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Build and Sideloadly install with extension (prep 1) | | | | | | |
| Upgrade check (prep 2) | | | | | | |
| P5-1 4K video, hash and MediaInfo | | | | | | |
| P5-2 iPhone → Android formats | | | | | | |
| P5-2 with HEIC→JPEG and Live video on | | | | | | |
| P5-3 Android → iPhone formats | | | | | | |
| P5-3 Photos access None → Files | | | | | | |
| P5-4 iCloud offline, online, cancel | | | | | | |
| P5-5 Limited access, iPhone | | | | | | |
| P5-5 Limited access, Android 14 | | | | | | |
| P5-6 hashes both ways | | | | | | |
| P5-7 kill, cancel, full | | | | | | |
| P5-8 dates | | | | | | |
| P5-9 share from Photos, Files, Gallery | | | | | | |
| P5-10 share vs picker | | | | | | |

## Phase 6: UI and onboarding

Feature docs: [features/ui-navigation.md](features/ui-navigation.md), [features/onboarding.md](features/onboarding.md), [features/settings.md](features/settings.md).

**What changed for earlier checks:** there is no Receive button any more. A phone is ready to receive whenever CrossDrop is open (Home shows "Ready to receive"). Its QR code and address are under **Show my QR code**. Sending starts with **Send** on Home: pick files, tap Send, then pick the phone.

### Preparation (once)

1. **Build both phones from the same commit** and install over the Phase 5 app without deleting it ([Installing the CI builds](#installing-the-ci-builds-no-mac-needed)).
   - New Swift file: `ios/Runner/OpenFileChannel.swift`. If the **iPhone unsigned IPA** job fails, paste its red lines and stop.
   - The Android debug APK was built on the PC before committing, so the Kotlin change compiles. It has not run on a phone yet.
2. **Delete and reinstall on one phone, for P6-1 only.** To see the iOS Local Network prompt again, the app must be new on the iPhone: delete CrossDrop from the iPhone (this gives it a new identity; the Android phone will show the lookalike warning once), then install the build. Keep the Android install as an upgrade, so both paths are covered.
3. **Logs:** as in Phase 5. New lines:
   - `[crossdrop.receive] hidden and idle: server stopped`
   - `[crossdrop.server] listening on port <n>` appears again when the app comes back.
   - `[crossdrop.open] failed: <code>`

   No file names appear in logs.
4. **Screens to check on two sizes.** If you have only one phone of each kind, make one look smaller:
   - iPhone: Settings > Display & Brightness > Display Zoom > **Larger Text** (the screen behaves like a smaller iPhone).
   - Android: Settings > Display > **Display size** > largest (same effect).

   Set it back afterwards.

### P6-1: First launch, introduction and permission timing

1. iPhone (fresh install): open CrossDrop.
   - Expected: page 1 "Open CrossDrop on both phones". **No** system prompt yet.
2. Tap **Next**. Expected: page 2 "Allow Local Network". Still no prompt.
3. Tap **Next**, then **Get started**.
   - Expected: Home, and **right away** the iOS prompt "CrossDrop would like to find and connect to devices on your local network". Tap **Allow**.
   - Home shows "Ready to receive as <name>".
4. Android (upgrade): open CrossDrop.
   - Expected: the three pages once (page 2 is "Same Wi-Fi, no internet needed").
   - Tap **Skip**. Home appears with no system prompt.
5. Close and reopen both apps. Expected: straight to Home, no pages.
6. Settings > **Show the introduction**. Expected: the pages again; the last button says **Close** and returns to Settings.
7. **Permissions come when used:**
   - Camera only at Scan QR code.
   - Photos only at Photos & videos.
   - On Android 13+, notifications at the first transfer.
   - On iPhone, add-only Photos at the first Accept with photos.

Paste back: a screenshot of the iPhone right after Get started, showing the prompt over Home.

### P6-2: Home, the Receiving switch and My QR code

1. Both phones on Home. Expected: "Ready to receive as <name>", and the text "Phones on the same Wi-Fi with CrossDrop open can see you".
2. On Android: **Send** > pick any photo > **Send**. Expected: the iPhone is listed with "iPhone · same Wi-Fi". Go back.
3. On the iPhone, turn **Receiving** off.
   - Expected: "Receiving is off".
   - Within about 5 s the iPhone disappears from Android's list (tap the refresh icon).
   - Turn it back on: it reappears.
4. iPhone: **Show my QR code**.
   - Expected: a QR code on white, also in dark mode. The screen does not dim while it is open.
   - "No camera? Type the address" shows the IP and port.
5. Put the iPhone in the background (home gesture) for **more than 30 s**, then reopen CrossDrop.
   - Expected: Android's list loses the iPhone while it is away.
   - After reopening, the iPhone shows "Starting…" briefly, then "Ready to receive", and Android finds it again.
   - The log shows `hidden and idle: server stopped`.
6. Repeat step 5 on Android (home button, 30 s, back). Same expectations.

### P6-3: Send iPhone → Android, untrusted, end to end

Use the iPhone after P6-1 (new identity, not trusted by Android).

1. iPhone: **Send**.
   - Expected: Photos & videos and Files buttons, and a text "Choose photos, videos or files…".
2. Pick 3 photos and a PDF.
   - Expected: they are listed, each with an × to remove.
   - The summary reads like "3 photos, 1 file · at least 1.2 MB", and "The full size is shown when sending starts".
   - Remove one photo with ×: the list and the count update.
3. Tap **Send**. Expected: the nearby list shows the Android phone with "Android phone · same Wi-Fi". Tap it.
4. Expected on the iPhone:
   - "Preparing 1 of 3…".
   - Then "Waiting for <Android> to accept…" with the 6-digit code under "Check that the other phone shows this code".
5. Expected on Android: the full-screen **Incoming files** request.
   - Your iPhone's name, "iPhone · Not trusted", and the box "First time from this device…".
   - "wants to send you 3 files · <size>", the names, the same 6-digit code, "Trust this device", and "This request expires in N s" counting down.
6. Tick **Trust this device**, tap **Codes match, accept**.
   - Expected on Android: the Progress screen. Bars, "Receiving 1 of 3", speed and time left (on a large file), and the note "You can switch apps: the transfer continues…".
   - Expected on the iPhone: "Keep CrossDrop open and the screen on until the transfer finishes".
7. When done:
   - **Android** shows a check, "3 files received", "from <iPhone> · <size>", "Where to find them: Saved to Pictures/CrossDrop" (and Download/CrossDrop for the PDF), and an **Open** button per file.
   - Tap Open on a photo: the gallery or a viewer shows it. Tap Open on the PDF: a PDF viewer opens.
   - **The iPhone** shows "3 files sent", "The other phone checked every file with SHA-256", and "Trust <Android>". Tap it.
8. Send again from the iPhone. Expected: no code on either phone, and Android's request says "Trusted".

Paste back: screenshots of steps 5, 6 (both phones) and 7 (both phones).

### P6-4: Send Android → iPhone, offer over another screen

1. iPhone: open **Settings** (stay there).
2. Android: Send a video and a WebM or ZIP file to the iPhone.
3. Expected: the Incoming request appears on the iPhone **on top of Settings**.
   - Accept. Progress shows "Keep CrossDrop open and the screen on…".
4. When done:
   - The iPhone shows "Saved to Photos" for the video, with **Open Photos**.
   - The other file shows "Saved to Files > On My iPhone > CrossDrop", with **Open**.
   - Open Photos opens the Photos app; Open shows a Quick Look preview. Write down whether Open Photos worked.
5. Send again and do **not** answer.
   - Expected: the countdown reaches 0 and the request closes by itself.
   - Android shows "Not answered", "Nobody tapped Accept on the other phone within 60 seconds", and **Send again**.
6. Send again and tap **Decline**. Expected on Android: "Declined" and **Send again**. Tap it: the Send screen opens.

### P6-5: Pause, Resume and Cancel

Use a video of 300 MB or more.

1. iPhone → Android. During sending, tap **Pause** on the iPhone.
   - Expected on the iPhone: "Paused. Tap Resume to go on", with a **Resume** button.
   - Within about 15 s, Android shows "Paused. Waiting for <iPhone> to reconnect…".
2. Wait 30 s, then tap **Resume**. Expected: it continues from where it stopped (the percentage does not go back to 0), and finishes with the hash checked.
3. Pause again. Lock the iPhone for 10 s, unlock. Expected: it is **still paused** (a user pause is kept). Resume.
4. New send. On Android, tap **Cancel** > **Cancel transfer**.
   - Expected on Android: "Cancelled", "You stopped the transfer. Unfinished files were deleted."
   - On the iPhone: "Cancelled by <Android>" and **Send again**.
5. New send. Cancel on the **iPhone**. Expected on Android: "Cancelled by <iPhone>".

### P6-6: Failures say what happened and what to do

1. **Receiving off:**
   - Forget the iPhone in Android's Settings > Trusted devices, so the next send needs the code again.
   - Turn Receiving off on Android, then send from the iPhone.
   - Expected on the iPhone: "The other phone is not receiving", "Receiving is turned off on it", "Ask its owner to turn Receiving on…".
2. **Connection lost:**
   - Send a large video iPhone → Android. During sending, turn Wi-Fi off on Android and leave it off for **more than 2 minutes**.
   - Expected on the iPhone: "Connection lost… trying again", then "Connection lost", "The phones could not reach each other for 2 minutes", a next step that mentions hotspot mode, and **Resume**.
   - Turn Wi-Fi on again, wait for Android to show "Ready to receive", then tap **Resume**. Expected: it finishes.
3. **QR on a network that blocks phones (if you have one, such as a guest Wi-Fi):**
   - Scan the other phone's QR code.
   - Expected: "Could not connect" in a bar at the bottom, with a **Help** action that opens "Can't find the other phone?".

Paste back: screenshots of each failure screen.

### P6-7: Can't find the other phone? and hotspot mode

1. On either phone: Send > pick a file > Send > **Can't find the other phone?**
   - Expected, in this order: "1. Check both phones", "2. Use the QR code" with **Scan QR code**, and "3. Use hotspot mode".
   - On the iPhone, a Local Network step with **Open Settings**; tapping it opens CrossDrop's page in Settings.
2. Tap **Scan QR code**. Expected: back on the nearby list and the camera opens. Scan the other phone's code; sending starts.
3. **Hotspot mode** on Android:
   - Expected: "This phone makes the network" and "Join the iPhone's Personal Hotspot".
   - Tap the first. Expected: the note "Starting the network from CrossDrop comes in the next update", and steps for Android's own hotspot.
4. **Hotspot mode** on the iPhone: expected "Join the Android phone's network" and "This iPhone makes the network".
5. **Follow the Personal Hotspot guide for real:**
   - Turn off Wi-Fi on both phones.
   - Turn on Personal Hotspot on the iPhone and join it from Android.
   - Open CrossDrop on both. Send a photo in each direction.
   - Write down whether they found each other in the list, or needed the QR code.
   - Android may say the network has no internet: stay connected. This is scenario 5; if the transfer fails, it may be the mobile-data routing that Phase 7 fixes. Paste the logs.

### P6-8: History

1. Home > **History** (clock icon).
   - Expected: the transfers from today under "Today".
   - Each shows ↗ or ↙, "To/From <name>", file count, size and platform, a status (Done, Failed, Cancelled, Declined), and the time.
2. Tap a received one. Expected: the Done view with **Open**. Open works.
3. Tap a failed or cancelled one. Expected: the Failed view with the reason.
4. Unfinished send:
   - Start a large send, Pause it, and kill the iPhone app (swipe up).
   - Reopen. If asked "Unfinished transfers", tap **Later**.
   - History > the transfer. Expected: "Unfinished: N% of…", **Resume** and **Discard**.
   - Tap **Resume**. Expected: it continues and finishes.

### P6-9: Settings

1. Rename the iPhone to "Test iPhone". Expected: within a few seconds, Android's nearby list (refresh) shows "Test iPhone". Rename it back.
2. Turn Receiving off in **Settings**, go Home. Expected: Home shows "Receiving is off". Close and reopen the app: still off. Turn it on.
3. iPhone only: "Sending photos to Android" has two switches. Turn on **Convert HEIC to JPEG**, send a HEIC photo to Android: it arrives as `.JPG`. Turn it off again.
4. **Trusted devices:**
   - The Android phone is listed with "Accept without asking".
   - Turn that on and send from Android: the iPhone saves the files with no request.
   - Turn it off, then **Forget** (confirm). The next send asks for the code again.
5. **About:** version 1.0.0, the sections, and the security key in groups of four. Open-source licenses opens a list.

### P6-10: Screen readers

1. iPhone: Settings > Accessibility > **VoiceOver** on. Android: **TalkBack** on.
2. Receive an untrusted offer.
   - Expected on the Incoming request: the sender is read, then the warning, the file count.
   - The code is read digit by digit ("Code 4 8 2 9 1 3").
   - The buttons are read as "Decline" and "Codes match, accept".
3. During the transfer, swipe through Progress.
   - Expected: "Total progress, 42%"; each file as "<name>, 40%" or "<name>, done".
   - The stage line is announced when it changes.
4. In History, each row is read as one item: "Sent, To <name>, …".
5. Turn the screen reader off.

Paste back: anything that is read wrongly or not at all.

### Screen review checklist

For each screen, check the four conditions and tick or note a problem. **Small phone:** the smaller of your phones, or Display Zoom / Display size as in preparation 4. **Large phone:** the larger one at normal zoom. **Large text:** iPhone Settings > Accessibility > Display & Text Size > Larger Text, slider to the far right (also try one of the extra-large accessibility sizes); Android Settings > Display > Font size at maximum. **Dark mode:** the system dark theme on.

What to look for on every screen:
- No text is cut off mid-word or overlapped. Long names may end with "…".
- Every button is fully visible, or reachable by scrolling.
- Text is easy to read against its background. Warnings (red or tinted boxes) are readable in dark mode.
- The QR code has a white background in dark mode.
- Nothing jumps or flickers while progress updates.

| Screen | How to reach it | Small phone | Large phone | Large text | Dark mode |
| --- | --- | --- | --- | --- | --- |
| Onboarding, 3 pages | Settings > Show the introduction | | | | |
| Home, ready | Open the app | | | | |
| Home, receiving off | Switch off | | | | |
| Home, with a transfer in progress | During P6-5 | | | | |
| My QR code | Home > Show my QR code | | | | |
| Send, empty and with 10+ items | Home > Send | | | | |
| Nearby, list and empty after 10 s | Send > Send | | | | |
| Can't find the other phone? | Nearby, bottom link | | | | |
| Hotspot mode and both guides | Help > Hotspot mode | | | | |
| Incoming request, untrusted with 7+ files | P6-3 | | | | |
| Incoming request, trusted | P6-3 step 8 | | | | |
| Progress, sender waiting with code | P6-3 step 4 | | | | |
| Progress, running, both phones | P6-3 step 6 | | | | |
| Progress, paused | P6-5 | | | | |
| Done, received (Open buttons) | P6-3 step 7 | | | | |
| Done, sent (Trust button) | P6-3 step 7 | | | | |
| Failed, connection lost | P6-6 | | | | |
| Failed, declined / not answered | P6-4 | | | | |
| History, list and detail | Home > History | | | | |
| Settings | Home > Settings | | | | |
| Trusted devices | Settings | | | | |
| About | Settings | | | | |

### Not checked on devices

Covered by tests on the PC:
- Flutter's tap-target, label and contrast guidelines on every Phase 6 screen in light and dark; Home, Send, Settings and History on a 320 × 568 phone with 2× text (`test/a11y/`).
- Failure wording for every reason code (`failure_messages_test.dart`).
- Schema 5 migration.

### Results

| Check | Date | iPhone, iOS | Android, version | Commit | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Build and install (prep 1) | | | | | | |
| P6-1 introduction and prompt timing | | | | | | |
| P6-2 Home, switch, QR, background 30 s | | | | | | |
| P6-3 iPhone → Android end to end, Open | | | | | | |
| P6-4 Android → iPhone over Settings, timeout, decline | | | | | | |
| P6-5 Pause, Resume, Cancel both sides | | | | | | |
| P6-6 failure screens | | | | | | |
| P6-7 help, hotspot UI, Personal Hotspot for real | | | | | | |
| P6-8 History, resume from History | | | | | | |
| P6-9 Settings | | | | | | |
| P6-10 VoiceOver and TalkBack | | | | | | |
| Screen review checklist | | | | | | |

## Phase 7: hotspot mode and benchmarks

Feature docs: [features/android-hotspot.md](features/android-hotspot.md), [features/iphone-join-hotspot.md](features/iphone-join-hotspot.md), [features/iphone-personal-hotspot-guide.md](features/iphone-personal-hotspot-guide.md), [features/android-network-binding.md](features/android-network-binding.md), [features/benchmark-mode.md](features/benchmark-mode.md). The speed protocol is in [BENCHMARKS.md](BENCHMARKS.md), "Phase 7".

**Important for the iPhone:** the CI build is signed by Sideloadly with a free Apple ID. Apple gives the Hotspot Configuration capability to paid Developer Program accounts only, so **this build cannot join a network from the app**. It shows the manual path instead (P7-4). In-app join (P7-5) needs a paid account; skip P7-5 until then.

### Preparation (once)

1. **Build both phones from the same commit**, normal build (bench off), and install over the Phase 6 app ([Installing the CI builds](#installing-the-ci-builds-no-mac-needed)).
   - New Swift file: `ios/Runner/HotspotJoinChannel.swift`. If the **iPhone unsigned IPA** job fails, paste its red lines and stop.
   - The Android debug and release APKs (also with the bench flag) were built on the PC before committing, so the Kotlin compiles. Nothing has run on a phone yet.
2. **For P7-9 and BENCHMARKS.md only**, a second pair of builds with **bench** ticked.
3. **Logs:** as in Phase 6. New lines (no names, passwords or addresses):
   - `[crossdrop.hotspot] started (wpa2|wpa3t|wpa3)`, `running on <interface>`, `start failed: <code>`, `stopped`, `stopped by the system or the user`, `stopping: idle after the last transfer`
   - `[crossdrop.hotspot] join: <outcome>`, `join step: <step>`, `removing the joined network`
   - `[crossdrop.network] bound to Wi-Fi (no internet there)`, `binding cleared`, `binding to Wi-Fi failed`
   - `[crossdrop.bench] <size> / <buffer> #<n>: <x> MB/s, retries <n>`
4. Note the Android version: on **Android 10–12** the permission is Location; on **13+** it is Nearby devices.

### P7-1: Android starts the hotspot and shows one QR code

1. Android: turn off the phone's own hotspot. Wi-Fi may be on or off.
2. Send > pick a file > Send > **Can't find the other phone?** > Hotspot mode > **This phone makes the network** > **Start**.
   - First time, expected: the system asks for **Nearby devices** (13+) or **Location** (10–12). Tap **Don't allow**.
   - Expected: "CrossDrop needs the Nearby devices permission…", **Try again**, **Open app settings**, and "Or use this phone's own hotspot".
3. Tap **Try again** and allow.
   - Expected within a few seconds: a QR code, "Network: <name>  Password: <password>", **Show a code for the iPhone Camera**, **Send files to the iPhone**.
   - Android's status bar shows a hotspot icon.
4. Logs: `started (...)` and `running on ...`. Write down the security (`wpa2`, `wpa3t`, `wpa3`) and the interface.
5. Press Back. Expected: back to Hotspot mode, the hotspot icon disappears, log `stopped`.

**Paste back:** screenshot of step 3 (cover the password if you like), the two log lines, Android version.

### P7-2: Refusals and stopping

1. **Tethering on:** turn on Android's own hotspot in quick settings, then Start in CrossDrop.
   - Expected: "Turn off the phone's own hotspot (tethering) first". Turn tethering off, **Try again**: works.
   - Some phones can run both; if the network simply starts, write that down.
2. **Android 10–12 only, location off:** turn off Location in quick settings, Start.
   - Expected: "Turn on Location in quick settings…".
3. **Stopped elsewhere:** with the network running, turn the hotspot off from quick settings (if the phone shows it).
   - Expected: "The network was stopped…" and Try again. Log `stopped by the system or the user`.
4. **After a transfer:** start the network, join from the iPhone (P7-3 or P7-4), send one photo.
   - Expected on Android after the transfer: "Transfer done. The network stops in 60 s." counting down.
   - Tap **Keep on**: the card goes away and the network stays.
   - Send another photo, then wait 60 s. Expected: the network stops by itself, log `stopping: idle after the last transfer`.
5. **Leaving during a transfer:** start a large transfer over the hotspot, press Back on the Android hotspot screen.
   - Expected: "Stop the network?" dialog. **Stay** keeps it; **Stop and leave** stops it and the transfer pauses (the sender shows reconnecting).

**Paste back:** which steps behaved as expected, and logs for any that did not.

### P7-3: The iPhone Camera joins with the Wi-Fi code

1. Start the network on Android, tap **Show a code for the iPhone Camera**.
2. iPhone: open the **Camera** app (not CrossDrop), point it at the code, tap the "Join network" banner > **Join**.
   - Expected: the iPhone joins; Settings > Wi-Fi shows the network with "No Internet Connection".
3. On Android tap **Show the CrossDrop code**. On the iPhone: CrossDrop > Send > pick a photo > Send > **Scan QR code**, scan it.
   - Expected: no join step (already joined: log `join step: checking` then `connected`), then the usual connect and transfer.

**Paste back:** whether the Camera offered to join, and whether the transfer finished.

### P7-4: iPhone joins from the CrossDrop code, free Apple ID build

1. iPhone: forget the Android network if it is known (Settings > Wi-Fi > ⓘ > Forget). Stay on your normal Wi-Fi or turn Wi-Fi on with no network.
2. Android: start the network. iPhone: CrossDrop > Send > pick 2 photos > Send > **Scan QR code**, scan the CrossDrop code.
   - Expected: "Join <name>'s network" with steps, the network name and password, **Copy password** and "Waiting for the network…". (This build cannot join in-app; log `join step: manual`.)
3. Tap **Copy password**, open Settings > Wi-Fi, tap the network, paste, **Join**. Come back to CrossDrop.
   - Expected within a few seconds: the screen closes by itself and the transfer starts (code check if not trusted). Log `join step: connected`.
4. **Other direction:** on Android tap **Send files to the iPhone**, pick a photo, Send.
   - Expected: the iPhone appears in the list (or use the iPhone's Show my QR code), and the photo arrives.
5. **Already connected:** iPhone, still on the Android's network: Hotspot mode > Join the Android phone's network > **Scan QR code**, scan again.
   - Expected: straight to "Connected to <name>'s network", no steps.
6. **Wrong network:** stop the hotspot on Android and start it again (new code). On the iPhone scan the **old** screenshot if you have one, or wait on the manual screen with the network off.
   - Expected: it keeps waiting; Back leaves cleanly.

**Paste back:** screenshots of steps 2 and 3, logs from the iPhone (`[crossdrop.hotspot]` lines), whether step 4 found the iPhone in the list or needed the QR code.

### P7-5: In-app join (paid Apple Developer account only)

Skip until a paid account is set up: enable **Hotspot** on the App ID, sign with `Runner/RunnerHotspot.entitlements` ([features/iphone-join-hotspot.md](features/iphone-join-hotspot.md)).

1. Scan the CrossDrop code. Expected: iOS asks "CrossDrop wants to join Wi-Fi network …". Tap **Cancel**.
   - Expected: "The iPhone did not join, because Cancel was tapped", **Try again**, **Join in Settings instead**.
2. **Try again** > **Join**. Expected: "Joining…", then connected and the transfer starts.
3. After the transfer, wait 60 s. Expected: the iPhone leaves the network and returns to its usual Wi-Fi; log `removing the joined network`.
4. Lock the iPhone during a large transfer for 30 s, unlock. Expected: still on the network, the transfer resumes.

### P7-6: Android network binding on a Wi-Fi without internet

Needs a Wi-Fi with no internet that the Android can join as a client. Easiest: a spare router, or your router with its internet (WAN) cable unplugged. (An iPhone Personal Hotspot usually has internet through the iPhone's mobile data, and iOS will not turn it on with mobile data off.)

1. Android: **mobile data on**, join the no-internet Wi-Fi. When Android says "no internet", choose to stay connected (or it may stay by itself).
2. iPhone: join the same Wi-Fi.
3. Open CrossDrop on both. Android log, expected: `bound to Wi-Fi (no internet there)`.
4. Send a 100 MB file Android → iPhone, then iPhone → Android.
   - Expected: both finish. Android Settings > Network > data usage for CrossDrop: mobile data does not grow by 100 MB.
5. Plug the internet back in (or join your normal Wi-Fi). Expected: `binding cleared`; transfers still work.
6. **Control (optional, shows why it is needed):** in step 1, with Wi-Fi without internet and mobile data on, the Phase 6 build should fail to send from Android. Only if you still have it installed; skip otherwise.

**Paste back:** the `[crossdrop.network]` lines, whether both transfers finished, the mobile data counter before and after.

### P7-7: iPhone Personal Hotspot guide, for real

1. Turn off Wi-Fi on both phones. On both: Send > … > Hotspot mode > the Personal Hotspot choice ("Join the iPhone's Personal Hotspot" on Android, "This iPhone makes the network" on iPhone).
   - Expected: "Step 1 of 3: Turn on Personal Hotspot" and a status line: iPhone "No phone has joined this iPhone yet", Android "This phone is not on an iPhone's hotspot yet".
2. iPhone: Settings > Personal Hotspot > Allow Others to Join. Android: join it in Settings > Wi-Fi.
   - Expected within 2 s, back in CrossDrop: iPhone "Personal Hotspot is on and a phone has joined." Android "This phone is on an iPhone's Personal Hotspot."
3. **Next** to step 3 on both. Expected: "<other phone> is on the same network" (if discovery works over the hotspot), or "Looking for the other phone…" (then use the QR code).
4. Send a photo each way (Send files; or Show my QR code / Scan QR code).
5. If the Android could not see the iPhone's network, turn on **Maximize Compatibility** and repeat; write down that it was needed.

**Paste back:** screenshots of step 2 on both phones, whether step 3 found the other phone by itself, logs if a transfer failed.

### P7-8: Hotspot suggestion on a Wi-Fi that keeps phones apart

Needs a guest Wi-Fi with client isolation, or two different networks: put the Android on one Wi-Fi and the iPhone on another (for example the router's guest network).

1. iPhone: Send > pick a photo > Send. Wait until "Can't find the other phone?" appears (about 5 s).
2. Android: Home > **Show my QR code**. iPhone: **Scan QR code**, scan it.
   - Expected: "Could not connect … guest and public Wi-Fi … use hotspot mode" message, and at the top of the list a card "The phones can't reach each other on this Wi-Fi" with **Use hotspot mode**.
3. Tap **Use hotspot mode**. Expected: Hotspot mode with the iPhone choices.

**Paste back:** screenshot of the card.

### P7-9: Benchmark build smoke test

With the **bench** builds on both phones:

1. Trust each other and turn on **Auto-accept** for the other phone on both (Settings > Trusted devices).
2. Both: Settings > **Benchmark (test build)**. Network: the real one. Android: Choose > the iPhone. Sizes **10 MB**, all three buffers, runs **1** > **Start series**.
   - Expected: three runs finish in under a minute; Results show three sender lines on the Android and three receiver lines on the iPhone, each with MB/s and CPU.
3. iPhone: Files > On My iPhone > CrossDrop: `crossdrop-bench.csv` exists; **no** `crossdrop-bench-*.bin` files were saved. Android: Downloads has **no** `crossdrop-bench-*.bin`.
4. **Copy CSV** on both and paste here.
5. Repeat from the iPhone as sender.
6. Then run the protocol in [BENCHMARKS.md](BENCHMARKS.md), "Phase 7".

**Paste back:** both CSVs.

### Not checked on devices

Covered by tests on the PC:
- QR Wi-Fi fields: every refusal, escaping, password never in `toString`.
- Hotspot address detection, the 60 s stop and Keep on, the join flow for every iOS answer, the network removal timers.
- The binding rule for every combination, binding after Wi-Fi loss, failed binds retried.
- Same-subnet checks, the iPhone hotspot range.
- Benchmark: 8 runs over loopback HTTPS with verification and discard, best-buffer rule, CSV format, CPU time on Linux and macOS (CI), buffer step sizes.

Not covered anywhere yet: real `startLocalOnlyHotspot` behaviour on your Android brand, NEHotspotConfiguration (needs a paid account), WPA3-only hotspots with an older iPhone.

### Results

| Check | Date | iPhone, iOS | Android, version | Commit | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Build and install (prep 1) | | | | | | |
| Bench builds (prep 2) | | | | | | |
| P7-1 start, permission, QR, stop on Back | | | | | | |
| P7-2 tethering, location, stopped elsewhere, 60 s, leave | | | | | | |
| P7-3 Camera Wi-Fi code | | | | | | |
| P7-4 join from CrossDrop code (free ID), both directions | | | | | | |
| P7-5 in-app join (paid account) | | | | | | |
| P7-6 network binding without internet | | | | | | |
| P7-7 Personal Hotspot guide | | | | | | |
| P7-8 hotspot suggestion | | | | | | |
| P7-9 benchmark smoke test | | | | | | |
