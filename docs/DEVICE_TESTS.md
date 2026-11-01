# Device Tests

Acceptance checks that need real phones (one iPhone, one Android). Unit tests that run on a computer do not belong here.

## How this file is used

- Each phase gets a section with its acceptance checks, written before the phase is called done.
- Each check lists: steps, expected result, and what logs or screenshots to capture.
- After running a check, record the date, devices, OS versions, result (pass/fail) and notes.
- A device feature counts as working only after a check here has been run and passed.

## Phase 1: file transfer proof of concept

Feature doc: [features/file-transfer-poc.md](features/file-transfer-poc.md). Speeds go in [BENCHMARKS.md](BENCHMARKS.md).

### Preparation (once)

1. **Build in release mode** on both phones from the same commit:
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

