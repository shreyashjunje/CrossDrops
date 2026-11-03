# Feature: Benchmark mode

- Phase: 7
- Status: Built, awaiting device runs
- Last updated: 2026-11-03

## Summary

A hidden screen in benchmark builds that sends the same random test files through the real transfer engine, many times, and records speed, CPU and memory. It produces the numbers in [BENCHMARKS.md](../BENCHMARKS.md): which buffer size to use, which network mode is fastest, and how CrossDrop compares with LocalSend.

## Scope

**In scope**

- Sizes 10 MB, 100 MB, 1 GB, 2 GB; buffers 256 KB, 1 MB, 4 MB; 1, 3 or 5 runs each.
- Per run: direction, network label, Wi-Fi band and link speed (Android), file size, buffer, time, average and peak MB/s, CPU %, peak memory, retries, failures.
- The receiving phone records its own CPU and memory for the same runs.
- CSV in the app's Documents folder, and Copy CSV.
- The best-buffer rule.

**Out of scope**

- Parallel streams. Not built: the plan is to add them only if the measurements show a clear gain (D-059).
- Automatic network switching between runs.
- Shipping it: normal builds do not contain it.

## Design

**Build flag** (D-058): `--dart-define=CROSSDROP_BENCH=true`, on a **release** build. The brief said debug builds only, but Flutter debug builds run Dart without full compilation and are several times slower, so their numbers mean nothing (BENCHMARKS.md already requires release). The flag is a `const bool`: in normal builds the screen, its Settings entry and the discarding store are compiled out. CI: Actions > Build > Run workflow > tick **bench**; artifacts are named `*-bench*`.

**Running a series** (`BenchRunner`):

- The sender picks the receiver through the normal nearby list (pinned TLS, as always), then runs the cases. Buffers alternate within each repeat (1 GB/256 KB #1, 1 GB/1 MB #1, 1 GB/4 MB #1, 1 GB/256 KB #2, ...), so warm-up or a neighbour's traffic does not favour one buffer. There is a 2 s pause between runs.
- Test files are random (xorshift), written 1 MB at a time into the temp folder, and reused while their size matches.
- Each run is a normal `SendSession` with the chosen `chunkSize`. Files are named `crossdrop-bench-<size>-<runId>.bin`.
- The receiver must auto-accept (trusted device with auto-accept on); the time does not include the Accept prompt either way.
- The screen stays on during a series (wakelock).

**What is measured:**

| Field | How |
| --- | --- |
| Time, average MB/s | From the first upload byte until the receiver confirmed the verified save (its SHA-256 check and save included). MB = 10^6 bytes, as in BENCHMARKS.md |
| Peak MB/s | Best 1 s window of the sender's progress (updates every 100 ms). The sender counts bytes handed to the socket, so a window can read up to one buffer high; trust the average more |
| CPU % | Process CPU time (user + system, `getrusage` via `dart:ffi`) ÷ wall time. 100 % = one core; can exceed 100 % because hashing runs in its own isolate |
| Peak memory | Highest `ProcessInfo.currentRss` seen during the run |
| Retries | Times the session went into `retrying` |
| Wi-Fi band, link | Android `WifiInfo` frequency and link speed of the Wi-Fi client; empty on iPhone and on the phone that is the hotspot |

**Receiver side** (`ReceiverBenchTracker`): when "Record runs this phone receives" is on, every session whose files all have benchmark names gets a row with role `receiver`, from the first received byte to the end of the session, with this phone's CPU and memory. Rows join with the sender's on `run_id` (taken from the file name).

**Receiving benchmark files** (D-058): bench builds wrap the file store in `BenchDiscardingStore`. A benchmark file is received into its normal partial file, hashed and verified like any other, then deleted instead of saved, so 2 GB runs do not fill the gallery or Downloads. History shows the run, with nothing to open. Other files are saved normally. No protocol change.

**Best buffer** (`bestBuffer`): median MB/s per file size and buffer, sender rows only, sizes of 100 MB and up. A buffer qualifies if its median is within 5 % of the best for every size. The 1 MB default wins a tie; otherwise the qualifying buffer with the highest total. If none qualifies everywhere, the highest total wins.

**CSV columns** (`BenchResult.csvHeader`):

`run_id, time_utc, role, direction, network, wifi_band, link_mbps, file_bytes, buffer_bytes, run, result, seconds, avg_MBps, peak_MBps, cpu_pct, peak_rss_MB, retries, reason, app_version`

No names, addresses or fingerprints (CLAUDE.md hard rule 7).

## Code

| Path | Purpose |
| --- | --- |
| `lib/core/bench/bench.dart` | Flag, sizes, buffers, names, test file |
| `lib/core/bench/bench_runner.dart` | Cases and runs |
| `lib/core/bench/bench_stats.dart` | Throughput, median, best buffer, CSV |
| `lib/core/bench/process_stats.dart` | CPU time and memory |
| `lib/core/bench/bench_store.dart` | Verify, then discard, benchmark files |
| `lib/features/bench/bench_screen.dart` | Screen and CSV file |
| `lib/features/bench/receiver_bench.dart` | Receiver rows |
| `lib/core/client/upload_client.dart`, `lib/core/engine/send_session.dart` | `chunkSize` (default 1 MB, unchanged) |
| `.github/workflows/build.yml` | `bench` input |

## Protocol and API

None.

## Tests

**Unit tests (no phones)**

- `test/core/bench/bench_test.dart`: names, labels, test file (size, randomness, reuse), average, peak window, retry, median, best buffer, CSV, CPU time, sampler, the flag is off in tests.
- `test/core/bench/bench_runner_test.dart`: 8 runs over loopback HTTPS with the discarding store (every file verified, nothing left), refused offers as failed rows, normal files still saved.
- `test/features/bench/receiver_bench_test.dart`: receiver rows.
- `test/core/transfer_test.dart`: 256 KB and 4 MB buffers write in steps of that size.

**Device checks**

[DEVICE_TESTS.md](../DEVICE_TESTS.md), "Phase 7": P7-9, and the protocol in [BENCHMARKS.md](../BENCHMARKS.md), "Phase 7".

## Known limits and risks

- The receive side writes in 1 MB pieces whatever the sender's buffer; the buffer test measures the sender's read and write size.
- iOS may stop a series if the screen locks; the wakelock prevents that while the screen is open.
- Generating a 2 GB test file takes a few seconds on the first run and needs 2 GB free on the sender.

## Open questions

- None.
