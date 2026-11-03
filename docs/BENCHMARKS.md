# Benchmarks

Measured transfer speeds on real devices.

## How this file is used

- Follows the benchmark matrix in [ARCHITECTURE.md](ARCHITECTURE.md): file sizes 10 MB, 100 MB, 1 GB, 2 GB × router 2.4 GHz, router 5 GHz, Android hotspot, iPhone hotspot × both directions. Compare with LocalSend on the same phones.
- Buffer sizes (256 KB, 1 MB, 4 MB) are compared here before changing defaults.
- Each result records date, devices, OS versions, network mode, file size, direction, buffer size, average speed and notes.
- Results here back any speed claim made in the app or docs, and set the v1 speed target.
- From Phase 7, benchmark builds record runs as CSV; see "Phase 7" below.

## Phase 1: proof of concept

### How to measure

- Build in **release** mode on both phones (`flutter run --release`). Debug builds are much slower and their numbers are not comparable.
- Use the test files from [DEVICE_TESTS.md](DEVICE_TESTS.md) "Phase 1" (random content, exactly 100 MB = 104,857,600 bytes and 1 GB = 1,073,741,824 bytes).
- Record the sender's result line after **Done**: `Time X s · average Y MB/s`. MB here means 10^6 bytes; the average is bytes sent in that run ÷ time from the start of the upload until the receiver confirmed the verified save, so it includes the receiver's hash check and move.
- Only fresh, uninterrupted runs count. If a run needed Resume, write it in Notes and do not use its MB/s.
- Keep both phones within about 2 m of each other and of the router, screens on, not charging if possible. Note anything unusual (other traffic, phone hot, battery saver on).
- Run each row 3 times; the median goes in the summary.

### Setup

Fill in once per test session.

| Field | Value |
| --- | --- |
| Date | |
| iPhone model, iOS version | |
| Android model, Android version | |
| App commit (`git log --oneline -1`) | |
| Build mode | release |
| Buffer size | 1 MB (default) |
| Router model, Wi-Fi standard (e.g. Wi-Fi 5/6) | |
| Phone–phone and phone–router distance | |

### Results

| Direction | File size | Network | Run | Time (s) | MB/s | Date | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| iPhone → Android | 100 MB | Router 2.4 GHz | 1 |  |  |  |  |
| iPhone → Android | 100 MB | Router 2.4 GHz | 2 |  |  |  |  |
| iPhone → Android | 100 MB | Router 2.4 GHz | 3 |  |  |  |  |
| iPhone → Android | 100 MB | Router 5 GHz | 1 |  |  |  |  |
| iPhone → Android | 100 MB | Router 5 GHz | 2 |  |  |  |  |
| iPhone → Android | 100 MB | Router 5 GHz | 3 |  |  |  |  |
| iPhone → Android | 100 MB | Android hotspot | 1 |  |  |  |  |
| iPhone → Android | 100 MB | Android hotspot | 2 |  |  |  |  |
| iPhone → Android | 100 MB | Android hotspot | 3 |  |  |  |  |
| iPhone → Android | 100 MB | iPhone hotspot | 1 |  |  |  |  |
| iPhone → Android | 100 MB | iPhone hotspot | 2 |  |  |  |  |
| iPhone → Android | 100 MB | iPhone hotspot | 3 |  |  |  |  |
| Android → iPhone | 100 MB | Router 2.4 GHz | 1 |  |  |  |  |
| Android → iPhone | 100 MB | Router 2.4 GHz | 2 |  |  |  |  |
| Android → iPhone | 100 MB | Router 2.4 GHz | 3 |  |  |  |  |
| Android → iPhone | 100 MB | Router 5 GHz | 1 |  |  |  |  |
| Android → iPhone | 100 MB | Router 5 GHz | 2 |  |  |  |  |
| Android → iPhone | 100 MB | Router 5 GHz | 3 |  |  |  |  |
| Android → iPhone | 100 MB | Android hotspot | 1 |  |  |  |  |
| Android → iPhone | 100 MB | Android hotspot | 2 |  |  |  |  |
| Android → iPhone | 100 MB | Android hotspot | 3 |  |  |  |  |
| Android → iPhone | 100 MB | iPhone hotspot | 1 |  |  |  |  |
| Android → iPhone | 100 MB | iPhone hotspot | 2 |  |  |  |  |
| Android → iPhone | 100 MB | iPhone hotspot | 3 |  |  |  |  |
| iPhone → Android | 1 GB | Router 2.4 GHz | 1 |  |  |  |  |
| iPhone → Android | 1 GB | Router 2.4 GHz | 2 |  |  |  |  |
| iPhone → Android | 1 GB | Router 2.4 GHz | 3 |  |  |  |  |
| iPhone → Android | 1 GB | Router 5 GHz | 1 |  |  |  |  |
| iPhone → Android | 1 GB | Router 5 GHz | 2 |  |  |  |  |
| iPhone → Android | 1 GB | Router 5 GHz | 3 |  |  |  |  |
| iPhone → Android | 1 GB | Android hotspot | 1 |  |  |  |  |
| iPhone → Android | 1 GB | Android hotspot | 2 |  |  |  |  |
| iPhone → Android | 1 GB | Android hotspot | 3 |  |  |  |  |
| iPhone → Android | 1 GB | iPhone hotspot | 1 |  |  |  |  |
| iPhone → Android | 1 GB | iPhone hotspot | 2 |  |  |  |  |
| iPhone → Android | 1 GB | iPhone hotspot | 3 |  |  |  |  |
| Android → iPhone | 1 GB | Router 2.4 GHz | 1 |  |  |  |  |
| Android → iPhone | 1 GB | Router 2.4 GHz | 2 |  |  |  |  |
| Android → iPhone | 1 GB | Router 2.4 GHz | 3 |  |  |  |  |
| Android → iPhone | 1 GB | Router 5 GHz | 1 |  |  |  |  |
| Android → iPhone | 1 GB | Router 5 GHz | 2 |  |  |  |  |
| Android → iPhone | 1 GB | Router 5 GHz | 3 |  |  |  |  |
| Android → iPhone | 1 GB | Android hotspot | 1 |  |  |  |  |
| Android → iPhone | 1 GB | Android hotspot | 2 |  |  |  |  |
| Android → iPhone | 1 GB | Android hotspot | 3 |  |  |  |  |
| Android → iPhone | 1 GB | iPhone hotspot | 1 |  |  |  |  |
| Android → iPhone | 1 GB | iPhone hotspot | 2 |  |  |  |  |
| Android → iPhone | 1 GB | iPhone hotspot | 3 |  |  |  |  |

### Summary (median of 3 runs, MB/s)

| Direction | File size | Router 2.4 GHz | Router 5 GHz | Android hotspot | iPhone hotspot |
| --- | --- | --- | --- | --- | --- |
| iPhone → Android | 100 MB | | | | |
| iPhone → Android | 1 GB | | | | |
| Android → iPhone | 100 MB | | | | |
| Android → iPhone | 1 GB | | | | |

Hotspot rows are optional in Phase 1: Android network binding is not built yet, so turn off mobile data on the phone that joins the hotspot.

## Phase 7: buffer sizes, network modes and LocalSend

Measured with benchmark builds ([features/benchmark-mode.md](features/benchmark-mode.md)). The Phase 1 tables above stay for history; Phase 7 replaces them.

### Builds

1. Actions > **Build** > Run workflow > branch `main`, tick **bench** > Run workflow (or `gh workflow run build.yml --ref main -f bench=true`).
2. Install `crossdrop-<sha7>-bench.apk` and `crossdrop-<sha7>-bench-unsigned.ipa` as in [DEVICE_TESTS.md](DEVICE_TESTS.md#installing-the-ci-builds-no-mac-needed). They are release builds with **Settings > Benchmark (test build)**.
3. Do not use these builds for anything else, and delete them afterwards.

### Rules (same as Phase 1, plus)

- Same two phones for everything. Battery above 50 %, not charging, battery saver and low-power mode off, Bluetooth off, other apps closed.
- Phones **1 m apart**, screens on, lying still. In router modes both about **2 m from the router**, line of sight. Write the distances in Setup.
- The phone that joins a hotspot has **mobile data off**, except in P7-6, which checks network binding.
- Wait until both phones are cool before each series. If the CSV shows retries, write why in Notes; runs with retries do not count in the medians.
- MB = 10^6 bytes in MB/s. File sizes are binary (1 GB = 1,073,741,824 bytes), as before.

### One-time preparation

1. Pair the phones once with a normal transfer and tick **Trust this device** on both. Then on each phone: Settings > Trusted devices > the other phone > **Auto-accept** on. Without it every run waits for a tap.
2. Open **Settings > Benchmark** on both phones. Leave **Record runs this phone receives** on.
3. On both, set **Network** before every series. It goes into the CSV.
4. Free space: the sender needs room for the test files (about 3.2 GB for all four sizes); the receiver needs 2.1 GB free during a 2 GB run (files are deleted after each run).

### Setting up each network

| Network label | How |
| --- | --- |
| Router 2.4 GHz | Both phones on the router's 2.4 GHz network. If the router uses one name for both bands, turn 5 GHz off for this series, or use a 2.4 GHz-only guest network **with client isolation off**. The Android CSV rows show `wifi_band` = 2.4 GHz; if not, stop and fix. |
| Router 5 GHz | Same, 5 GHz only. Check `wifi_band` = 5 GHz. |
| Android hotspot | Android: Send > Can't find the other phone? > Hotspot mode > This phone makes the network > **Start**. iPhone: join it (scan, or Settings > Wi-Fi with the shown password). On the Android, tap **Benchmark (test build)** on the hotspot screen, so the network stays up; never go back from the hotspot screen during a series. |
| iPhone hotspot | iPhone: Settings > Personal Hotspot > Allow Others to Join (leave **Maximize Compatibility** off unless the Android cannot see it; write down which). Android: join it in Settings > Wi-Fi, mobile data off. Then Settings > Benchmark on both. |

### Step 0: each phone's own limits (D-066)

Before the network series, on **each** phone: Settings > Benchmark > **Measure this phone** (about a minute, screen on, nothing else running). It measures, 256 MB each, without the network:

- `sha256`: SHA-256 in a background isolate, as both phones hash every file.
- `tls_loopback`: pinned TLS 1.3 between two isolates on this phone, the cost of TLS and the socket stack without the radio.
- `write_fsync_4mb` and `write_fsync_64mb`: writing through the store received files use (MediaStore on Android, the app folder on iPhone), with a checkpoint every 4 MB (before D-065) and every 64 MB or 2 s (now).

Rows go to `crossdrop-limits.csv` next to `crossdrop-bench.csv`. Run it twice and keep the second (the first warms caches). Paste both phones' files.

| Phone | sha256 MB/s | tls_loopback MB/s | write_fsync_4mb MB/s | write_fsync_64mb MB/s |
| --- | --- | --- | --- | --- |
| iPhone | | | | |
| Android | | | | |

How to read it, with Step A and B and an iperf3 baseline:

- A step within about 1.5× of a transfer's MB/s on the same phone is that transfer's ceiling. `sha256` on the receiver is the first candidate on budget Androids (pure Dart).
- If `write_fsync_4mb` is clearly below `write_fsync_64mb`, D-065 already pays off; if both are close to the transfer speed, the disk is the limit.
- CrossDrop well below iperf3 while every step here is far above it points at the protocol path (one file at a time, the per-file round trips), not at CPU or disk.

The decisions waiting on these numbers are in D-066.

### Step A: choose the buffer size

On **Router 5 GHz**, then on **Android hotspot**:

1. On the sending phone: Choose the other phone; sizes **1 GB** only; all three buffers; **3** runs each > **Start series** (9 runs, about 5–10 minutes).
2. Then the other direction: start the same series from the other phone.
3. That is 36 runs in all. The screen shows "Best buffer so far" from its own sender rows; I will compute the final answer from all CSVs with the same rule (median, sizes ≥ 100 MB, within 5 % of the best on every network and direction, ties go to 1 MB).

Paste both CSVs (Copy CSV, or the file) after Step A. If the winner is not 1 MB, I change the default in a separate commit before Step B and tell you the numbers that justify it.

### Step B: the full matrix

At the chosen buffer only (untick the others), **3 runs**, all four sizes:

| Network | iPhone → Android | Android → iPhone |
| --- | --- | --- |
| Router 2.4 GHz | 12 runs | 12 runs |
| Router 5 GHz | 12 runs | 12 runs |
| Android hotspot | 12 runs | 12 runs |
| iPhone hotspot | 12 runs | 12 runs |

96 runs. The 2 GB runs dominate: at 20 MB/s one takes almost 2 minutes, so plan 3–4 hours with network changes. One series per cell; set Network first.

After each network: on both phones **Copy CSV** and paste it, or send the file, so a crash cannot lose it. **Start a new CSV** only when I ask.

### Comparing with LocalSend fairly

LocalSend is the closest open-source app (HTTPS, local network, no cloud). Compare **100 MB and 1 GB, both directions, 3 runs**, on the same four networks, same phones, same places, same session.

1. **Install** LocalSend from the App Store and Google Play. Write its version in Setup.
2. **Settings** in LocalSend on both phones:
   - **Encryption: on** (the default; HTTPS, like CrossDrop's TLS).
   - On the receiver: **Quick Save** on, so no Accept tap is timed. Note the save folder.
   - Same device names as usual; nothing else changed.
3. **Same files, same place:** both apps send the same bytes from the same folder.
   - On the PC, make two random files with the tool from DEVICE_TESTS.md "Phase 1": exactly 100 MB (104,857,600 bytes) and 1 GB (1,073,741,824 bytes).
   - Android: `adb push` them to `/sdcard/Download/`. Both apps pick them from Downloads.
   - iPhone: iTunes for Windows > the iPhone > File Sharing > CrossDrop > add both files. They appear in Files > On My iPhone > CrossDrop, where both apps can pick them.
   - CrossDrop sends them with the normal **Send** button, not the benchmark screen; its result is the sender's "Time X s · average Y MB/s" line. (iOS copies a picked document before sending; that copy is not timed.)
4. **Timing LocalSend:** it shows a progress bar but no final average. Start a **screen recording on the receiving phone**, send, and stop after "Finished". From the recording, time = first movement of the progress bar to "Finished" (±0.2 s at 30 fps). MB/s = file bytes ÷ 10^6 ÷ time.
5. **Order:** alternate apps run by run (CrossDrop #1, LocalSend #1, CrossDrop #2, ...), so heat and battery affect both the same. Delete received files between runs on both apps.
6. **Hotspot fairness:** CrossDrop's in-app hotspot exists only while its screen is open, and LocalSend cannot use it. For the "Android hotspot" column run **both apps over Android's own Settings hotspot** (tethering), mobile data off on both phones, label it "Android tethering (Settings)". CrossDrop's in-app hotspot result from Step B is a separate column.
7. **Same rules:** same distances, same router, same time of day, screens on.

Record LocalSend in the table below; I add CrossDrop's from the same session.

### Setup (Phase 7)

| Field | Value |
| --- | --- |
| Date | |
| iPhone model, iOS version | |
| Android model, Android version | |
| App commit (bench build) | |
| LocalSend version (iOS / Android) | |
| Router model, Wi-Fi standard, channel width if known | |
| Phone–phone and phone–router distance | |
| Maximize Compatibility on the iPhone hotspot | |

### CSV columns

`run_id, time_utc, role, direction, network, wifi_band, link_mbps, file_bytes, buffer_bytes, run, result, seconds, avg_MBps, peak_MBps, cpu_pct, peak_rss_MB, retries, reason, app_version`

- `role` is `sender` or `receiver`; the two phones' rows join on `run_id`.
- `cpu_pct`: 100 = one core busy; can exceed 100 (hashing runs in parallel).
- `peak_MBps` is the best 1 s window on the sender and can read up to one buffer high; the average is the figure that counts.

### Step A results: buffer size (median MB/s, 1 GB)

| Network | Direction | 256 KB | 1 MB | 4 MB | Sender CPU % (1 MB) | Receiver CPU % (1 MB) |
| --- | --- | --- | --- | --- | --- | --- |
| Router 5 GHz | iPhone → Android | | | | | |
| Router 5 GHz | Android → iPhone | | | | | |
| Android hotspot | iPhone → Android | | | | | |
| Android hotspot | Android → iPhone | | | | | |

Chosen buffer: … (filled in from the CSVs)

### Step B results: median MB/s at the chosen buffer

| Direction | File size | Router 2.4 GHz | Router 5 GHz | Android hotspot | iPhone hotspot |
| --- | --- | --- | --- | --- | --- |
| iPhone → Android | 10 MB | | | | |
| iPhone → Android | 100 MB | | | | |
| iPhone → Android | 1 GB | | | | |
| iPhone → Android | 2 GB | | | | |
| Android → iPhone | 10 MB | | | | |
| Android → iPhone | 100 MB | | | | |
| Android → iPhone | 1 GB | | | | |
| Android → iPhone | 2 GB | | | | |

### CrossDrop and LocalSend (median MB/s, same session)

| Direction | File size | App | Router 2.4 GHz | Router 5 GHz | Android tethering (Settings) | iPhone hotspot |
| --- | --- | --- | --- | --- | --- | --- |
| iPhone → Android | 100 MB | CrossDrop | | | | |
| iPhone → Android | 100 MB | LocalSend | | | | |
| iPhone → Android | 1 GB | CrossDrop | | | | |
| iPhone → Android | 1 GB | LocalSend | | | | |
| Android → iPhone | 100 MB | CrossDrop | | | | |
| Android → iPhone | 100 MB | LocalSend | | | | |
| Android → iPhone | 1 GB | CrossDrop | | | | |
| Android → iPhone | 1 GB | LocalSend | | | | |

### Parallel streams

Not built (D-059). After Step B I compare, per network: single-stream MB/s, both phones' CPU %, and, if you can run it, an iperf3 baseline (Android: an iperf3 app or Termux `iperf3 -s`; iPhone: an iperf3 client app; `-P 4` for four streams). I propose parallel streams only if CrossDrop is clearly below the iperf3 figure (more than about 25 %) while neither phone's CPU is near one core, and I show you those numbers first.
