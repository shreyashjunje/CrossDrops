import 'dart:io';
import 'dart:math';

import 'package:crossdrop/core/bench/bench.dart';
import 'package:crossdrop/core/bench/bench_stats.dart';
import 'package:crossdrop/core/bench/process_stats.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

BenchResult sent(int size, int buffer, double mbps, {bool ok = true}) =>
    BenchResult(
      runId: 'r',
      time: DateTime.utc(2026, 11, 3),
      role: BenchRole.sender,
      direction: 'iPhone → Android',
      network: 'Router 5 GHz',
      fileBytes: size,
      bufferBytes: buffer,
      run: 1,
      ok: ok,
      avgMBps: ok ? mbps : null,
    );

const mib = 1024 * 1024;

void main() {
  group('names and labels', () {
    test('sizeLabel', () {
      expect(sizeLabel(10 * mib), '10 MB');
      expect(sizeLabel(2048 * mib), '2 GB');
      expect(sizeLabel(256 * 1024), '256 KB');
      expect(sizeLabel(1500), '1500 B');
    });

    test('bench file names are recognised, others are not', () {
      final id = newRunId(Random(1));
      expect(id, matches(RegExp(r'^[0-9a-f]{8}$')));
      expect(isBenchFileName(benchFileName(100 * mib, id)), isTrue);
      expect(isBenchFileName('IMG_0001.HEIC'), isFalse);
      expect(isBenchFileName('crossdrop-bench-1-ABCDEF12.bin'), isFalse);
      expect(isBenchFileName('../crossdrop-bench-1-abcdef12.bin'), isFalse);
      expect(isBenchFileName('crossdrop-bench-1-abcdef12.bin.jpg'), isFalse);
    });
  });

  test('ensureBenchFile: exact size, random, reused', () async {
    final dir = Directory.systemTemp.createTempSync('cd_bench');
    addTearDown(() => dir.deleteSync(recursive: true));
    const size = 3 * mib + 123;
    final path = await ensureBenchFile(dir.path, size);
    expect(await File(path).length(), size);
    final raf = File(path).openSync();
    final a = raf.readSync(4096);
    raf.setPositionSync(mib);
    final b = raf.readSync(4096);
    raf.closeSync();
    expect(a, isNot(b), reason: 'blocks must differ');
    expect(a.where((x) => x == 0).length, lessThan(100));
    final modified = File(path).lastModifiedSync();
    expect(await ensureBenchFile(dir.path, size), path);
    expect(File(path).lastModifiedSync(), modified);
    expect(File(p.join(dir.path, 'bench-$size.bin.tmp')).existsSync(), isFalse);
  });

  group('throughput', () {
    test('average', () {
      expect(mbPerSecond(50000000, const Duration(seconds: 2)), 25);
      expect(mbPerSecond(1, Duration.zero), 0);
    });

    test('peak is the best 1 s window', () {
      final r = ThroughputRecorder();
      // 10 MB/s for 2 s, then 30 MB/s for 1.5 s.
      for (var ms = 0; ms <= 2000; ms += 100) {
        r.add(Duration(milliseconds: ms), ms * 10000);
      }
      for (var ms = 2100; ms <= 3500; ms += 100) {
        r.add(Duration(milliseconds: ms), 20000000 + (ms - 2000) * 30000);
      }
      expect(r.peakMBps(), closeTo(30, 0.01));
    });

    test('peak is null for runs under a second', () {
      final r = ThroughputRecorder()
        ..add(Duration.zero, 0)
        ..add(const Duration(milliseconds: 500), 1000);
      expect(r.peakMBps(), isNull);
    });

    test('a retry going back starts the window again', () {
      final r = ThroughputRecorder()
        ..add(Duration.zero, 0)
        ..add(const Duration(seconds: 1), 50000000)
        ..add(const Duration(seconds: 2), 10000000) // Receiver had less.
        ..add(const Duration(seconds: 3), 20000000);
      expect(r.peakMBps(), closeTo(50, 0.01));
    });

    test('median', () {
      expect(median([3, 1, 2]), 2);
      expect(median([4, 1, 2, 3]), 2.5);
      expect(median([]), isNull);
    });
  });

  group('best buffer', () {
    test('a clear winner everywhere', () {
      expect(
        bestBuffer([
          sent(100 * mib, 256 * 1024, 20),
          sent(100 * mib, mib, 25),
          sent(100 * mib, 4 * mib, 32),
          sent(1024 * mib, 256 * 1024, 21),
          sent(1024 * mib, mib, 26),
          sent(1024 * mib, 4 * mib, 33),
        ]),
        4 * mib,
      );
    });

    test('within 5 %: keep the 1 MB default', () {
      expect(
        bestBuffer([sent(1024 * mib, mib, 30), sent(1024 * mib, 4 * mib, 31)]),
        mib,
      );
    });

    test('median of three runs, failures and 10 MB ignored', () {
      expect(
        bestBuffer([
          sent(1024 * mib, mib, 20),
          sent(1024 * mib, mib, 21),
          sent(1024 * mib, mib, 90), // Outlier.
          sent(1024 * mib, 4 * mib, 25),
          sent(1024 * mib, 4 * mib, 25),
          sent(1024 * mib, 4 * mib, 0, ok: false),
          sent(10 * mib, mib, 99),
        ]),
        4 * mib,
      );
    });

    test('no results', () => expect(bestBuffer([]), isNull));
  });

  test('CSV row matches the header and escapes text', () {
    final row = BenchResult(
      runId: 'abcd1234',
      time: DateTime.utc(2026, 11, 3, 10),
      role: BenchRole.sender,
      direction: 'Android → iPhone',
      network: 'Other, "lab"',
      fileBytes: 100 * mib,
      bufferBytes: mib,
      run: 2,
      ok: true,
      seconds: 4.1234,
      avgMBps: 25.4321,
      peakMBps: 30,
      cpuPercent: 87.6,
      peakRssBytes: 150000000,
      wifiBand: '5 GHz',
      linkMbps: 866,
    ).toCsv();
    expect(
      row,
      'abcd1234,2026-11-03T10:00:00.000Z,sender,Android → iPhone,'
      '"Other, ""lab""",5 GHz,866,104857600,1048576,2,ok,4.12,25.43,30.00,'
      '88,150,0,,',
    );
    expect(row.split(',').length, BenchResult.csvHeader.split(',').length + 1);
  });

  group('process stats', () {
    test('CPU time where getrusage exists', () {
      final t = processCpuTime();
      if (Platform.isWindows) {
        expect(t, isNull);
      } else {
        expect(t, isNotNull);
        expect(t!.inMicroseconds, greaterThan(0));
      }
    });

    test('sampler: CPU share of wall time and peak memory', () async {
      var cpu = Duration.zero;
      var rss = 100;
      final s = ProcessSampler(cpu: () => cpu, rss: () => rss)..start();
      rss = 300;
      s.sample();
      rss = 200;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      cpu = const Duration(milliseconds: 25);
      final (pct, peak) = s.stop();
      expect(pct, inInclusiveRange(10, 55));
      expect(peak, 300);
    });

    test('sampler without CPU data', () {
      final s = ProcessSampler(cpu: () => null, rss: () => 1)..start();
      expect(s.stop().$1, isNull);
    });
  });
}
