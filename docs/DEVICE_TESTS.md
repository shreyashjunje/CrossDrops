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
   - `crossdrop-android-<sha>`, which contains `crossdrop-<sha7>.apk`
   - `crossdrop-ios-unsigned-<sha>`, which contains `crossdrop-<sha7>-unsigned.ipa`

   Unzip both. Note the 7-character commit id for the Results tables.

If a job fails, open it, copy the red error lines and paste them back.

### 2. Install on Android

- **USB:** `adb install -r crossdrop-<sha7>.apk`
- **Or without USB:** copy the APK to the phone, open it, and allow "Install unknown apps" for the file manager when asked.

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
- Bundle id: Sideloadly may change it. If it says the id `com.example.crossdrop` is unavailable, use its "Bundle ID" option to set something unique, for example `com.<yourname>.crossdrop`.

**Paste back if it fails:** the Sideloadly log (its Log window) and the iOS version.

## Phase 1: file transfer proof of concept

Feature doc: [features/file-transfer-poc.md](features/file-transfer-poc.md). Speeds go in [BENCHMARKS.md](BENCHMARKS.md).

### Preparation (once)

1. **Build in release mode** on both phones from the same commit. The easiest way: run the Build workflow and install both artifacts ([Installing the CI builds](#installing-the-ci-builds-no-mac-needed)). Other ways:
   - Android (from this PC): `flutter run --release -d <android-device-id>` (`flutter devices` lists ids).
   - iPhone (from a Mac with Xcode): open `ios/Runner.xcworkspace`, set your signing team under Runner > Signing & Capabilities (change the bundle id from `com.example.crossdrop` if Xcode says it is taken), then `flutter run --release -d <iphone-id>`.
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
- `adb shell ls -l /sdcard/Android/data/com.example.crossdrop/files/CrossDrop/` shows `crossdrop-100MB.bin` with size exactly 104857600.
- Optional: `adb shell sha256sum /sdcard/Android/data/com.example.crossdrop/files/CrossDrop/crossdrop-100MB.bin` equals the PC hash (some Android versions block shell access to this folder; then note "not checked").

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
- `adb shell sha256sum /sdcard/Android/data/com.example.crossdrop/files/CrossDrop/<name>`
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
