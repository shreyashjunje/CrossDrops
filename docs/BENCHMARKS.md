# Benchmarks

Measured transfer speeds on real devices.

## How this file is used

- Follows the benchmark matrix in [ARCHITECTURE.md](ARCHITECTURE.md): file sizes 10 MB, 100 MB, 1 GB, 2 GB × router 2.4 GHz, router 5 GHz, Android hotspot, iPhone hotspot × both directions. Compare with LocalSend on the same phones.
- Buffer sizes (256 KB, 1 MB, 4 MB) are compared here before changing defaults.
- Each result records date, devices, OS versions, network mode, file size, direction, buffer size, average speed and notes.
- Results here back any speed claim made in the app or docs, and set the v1 speed target.

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
