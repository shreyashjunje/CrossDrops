# Status after Phase 7 (2026-11-03, updated after the code review)

**Code review of 2026-11-03:** every bug (H1–H4, M1–M6, L1–L8) and every release blocker is fixed in the code and unit-tested; speed items 1–5 are in (item 1 as "Measure this phone", D-066); items 6–10 wait for measurements (D-066). What needs a phone is in [DEVICE_TESTS.md](DEVICE_TESTS.md), "Code review fixes" (R-1 to R-9). Run those with the smoke tests below.

All v1 features in CLAUDE.md are now in the code: transfer engine, discovery, QR, pinned TLS and pairing, media saving, sharing from other apps, UI, Android hotspot, iPhone Personal Hotspot guide, and benchmark builds. CI runs analyze and tests on every push.

**No phase is done yet.** Under the Definition of done, a phase also needs its checks run on one iPhone and one Android phone. Every Results table in [DEVICE_TESTS.md](DEVICE_TESTS.md) and [BENCHMARKS.md](BENCHMARKS.md) is still empty.

**Added 2026-11-08 (D-068):** real file names on iPhone picks, previews of picked, sent and received files, a faster photo picker and preparation, three files at once, and "original quality" with exact byte counts on the Done screen. Unit-tested; device checks N-1 to N-8 in [DEVICE_TESTS.md](DEVICE_TESTS.md), "Send screen fixes". The iOS Swift part (QuickLook previews) has not been compiled yet: the next CI build is its first.

**Added 2026-11-08:** import from an iPhone by cable on Android (D-067, [features/usb-import.md](features/usb-import.md)). Built and unit-tested; device checks U-1 to U-9 in [DEVICE_TESTS.md](DEVICE_TESTS.md), "Cable import".

## What is left

### 1. Device testing (blocks everything else)
- About 90 checks from P1-1 to P7-9. None has been run on an iPhone. Android has had one 1.2 MB transfer to a PC (Phase 1).
- **The Phase 1 and 2 steps are out of date.** P1-1, for example, says to type an IP on the Send screen and to look for the file in the app's own folder. Since then, Phase 5 moved received files to MediaStore and Photos, and Phase 6 replaced the screens. Running them as written would give false failures.
- P7-5 (in-app hotspot join) needs a paid Apple Developer account. Without one it stays untested, and the Settings route (P7-4) is what v1 uses.

### 2. Benchmarks
- The speed tables in BENCHMARKS.md are empty: router at 2.4 and 5 GHz, Android hotspot and iPhone hotspot, both directions.
- These open decisions wait on the numbers:
  - the speed target (ARCHITECTURE.md, Open decisions);
  - the best buffer size;
  - how many files at once (D-068: 3; compare 1 and 3 with many photos and with one large video).

### 3. Open decisions
- **LocalSend compatibility:** no for v1 (D-060). Look at it again after v1.
- **Speed target:** set from the benchmark results (see 2).

### 4. Deferred until device tests show a need
- Guiding users to OEM battery settings on Xiaomi, Oppo, Vivo and OnePlus ([keep-alive.md](features/keep-alive.md)).
- Fixes for whatever the device tests turn up.

### 5. Before giving it to anyone (after testing)
- ~~A real bundle id and application id~~: `io.github.shreyashjunje.crossdrop` (D-063).
- ~~Release signing~~: set up; create the key and add the CI secrets ([RELEASE.md](RELEASE.md)).
- App icon and an iPhone distribution route (TestFlight needs a paid account).
- Privacy text (no data leaves the local network) and a store listing, if it goes to the stores.

## What to do next, in order

1. **Start the Build workflow:** github.com > Actions > Build > Run workflow on `main`. Then run it again with **bench** ticked. Download the APK and the IPA. See [Installing the CI builds](DEVICE_TESTS.md#installing-the-ci-builds-no-mac-needed).
2. **Install both builds:** the APK with `adb install -r`, the IPA with Sideloadly. Fill in the "Build and install" rows of the Phase 7 table. Paste back any errors.
3. **Smoke test before the full pass.** These four confirm the core works on real phones:
   - P6-3: iPhone → Android, end to end, untrusted.
   - P6-4: Android → iPhone.
   - P4-1: pairing in both directions.
   - P7-9: benchmark smoke test.

   If one fails, stop and paste back screenshots and `adb logcat -s flutter`. Fixing those first saves running 90 checks against a broken build.

   Then R-1 to R-9 (code review fixes). Uninstall the old `com.example.crossdrop` app first: the new id installs as a separate app.
4. **Next coding task (for Claude):** bring P1 and P2 up to date with the current screens, and add a short "v1 core pass" list at the top of DEVICE_TESTS.md. The full pass then follows the app as it is today, not as it was in each phase.
5. **Full device pass:** Phases 3 to 7, then the updated 1 and 2. Write each result in its table with the date, OS versions and commit.
6. **Benchmarks:** use the bench build and fill in BENCHMARKS.md. Then decide the speed target, the buffer size and D-059.
7. **Release prep** (section 5 above).
