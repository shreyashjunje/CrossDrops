/// Throughput of one benchmark run, from (time, bytes) samples.
///
/// - Average: all bytes ÷ time from the first upload byte until the
///   receiver confirmed the verified save (docs/BENCHMARKS.md).
/// - Peak: the best [window] of the sender's progress. The sender counts
///   bytes once they are handed to the socket, so a window can read up to
///   one buffer high; that is noted in the docs.
class ThroughputRecorder {
  ThroughputRecorder({this.window = const Duration(seconds: 1)});

  final Duration window;
  final List<(Duration, int)> _samples = [];

  /// The peak of samples dropped at a retry.
  double? _earlier;

  /// [at] since the start of the run; [bytes] sent so far.
  void add(Duration at, int bytes) {
    if (_samples.isNotEmpty && _samples.last.$2 > bytes) {
      // A retry went back to the receiver's count: keep the peak so far
      // and start the window anew.
      _earlier = peakMBps();
      _samples.clear();
    }
    _samples.add((at, bytes));
  }

  /// Best MB/s (10^6 bytes) over any [window]; null with too few samples.
  double? peakMBps() {
    var best = _earlier;
    var j = 0;
    for (var i = 0; i < _samples.length; i++) {
      final (t, b) = _samples[i];
      while (j < i && t - _samples[j].$1 > window) {
        j++;
      }
      // The window ending at sample i, starting at the newest sample at
      // least [window] earlier, or the first one.
      final start = j > 0 ? _samples[j - 1] : _samples[j];
      final dt = t - start.$1;
      if (dt < window) continue;
      final rate = (b - start.$2) / dt.inMicroseconds; // bytes/us = MB/s
      if (best == null || rate > best) best = rate;
    }
    return best;
  }
}

/// [bytes] over [elapsed] in MB/s (10^6 bytes per second).
double mbPerSecond(int bytes, Duration elapsed) =>
    elapsed.inMicroseconds == 0 ? 0 : bytes / elapsed.inMicroseconds;

/// The median, or null for an empty list.
double? median(Iterable<double> values) {
  final v = values.toList()..sort();
  if (v.isEmpty) return null;
  final m = v.length ~/ 2;
  return v.length.isOdd ? v[m] : (v[m - 1] + v[m]) / 2;
}

enum BenchRole { sender, receiver }

/// One row of the benchmark CSV (docs/BENCHMARKS.md, "CSV columns").
class BenchResult {
  const BenchResult({
    required this.runId,
    required this.time,
    required this.role,
    required this.direction,
    required this.network,
    required this.fileBytes,
    required this.bufferBytes,
    required this.run,
    required this.ok,
    this.seconds,
    this.avgMBps,
    this.peakMBps,
    this.cpuPercent,
    this.peakRssBytes,
    this.retries = 0,
    this.reason,
    this.wifiBand,
    this.linkMbps,
    this.appVersion = '',
  });

  final String runId;
  final DateTime time;
  final BenchRole role;

  /// `iPhone → Android` or `Android → iPhone`.
  final String direction;

  /// The label the user chose, e.g. `Router 5 GHz`.
  final String network;
  final int fileBytes;

  /// Sender: the upload buffer. Receiver: its write buffer (fixed 1 MB).
  final int bufferBytes;

  /// 1, 2, 3 within a series.
  final int run;
  final bool ok;
  final double? seconds;
  final double? avgMBps;
  final double? peakMBps;
  final double? cpuPercent;
  final int? peakRssBytes;
  final int retries;
  final String? reason;
  final String? wifiBand;
  final int? linkMbps;
  final String appVersion;

  static const csvHeader =
      'run_id,time_utc,role,direction,network,wifi_band,link_mbps,'
      'file_bytes,buffer_bytes,run,result,seconds,avg_MBps,peak_MBps,'
      'cpu_pct,peak_rss_MB,retries,reason,app_version';

  String toCsv() {
    String f(double? v, [int digits = 2]) =>
        v == null ? '' : v.toStringAsFixed(digits);
    String q(String s) =>
        s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    return [
      runId,
      time.toUtc().toIso8601String(),
      role.name,
      q(direction),
      q(network),
      wifiBand ?? '',
      linkMbps?.toString() ?? '',
      '$fileBytes',
      '$bufferBytes',
      '$run',
      ok ? 'ok' : 'failed',
      f(seconds),
      f(avgMBps),
      f(peakMBps),
      f(cpuPercent, 0),
      peakRssBytes == null ? '' : (peakRssBytes! / 1e6).toStringAsFixed(0),
      '$retries',
      q(reason ?? ''),
      q(appVersion),
    ].join(',');
  }
}

/// Median MB/s per (file size, buffer size) of successful sender runs.
Map<(int, int), double> medianByCase(Iterable<BenchResult> results) {
  final groups = <(int, int), List<double>>{};
  for (final r in results) {
    if (r.role != BenchRole.sender || !r.ok || r.avgMBps == null) continue;
    groups.putIfAbsent((r.fileBytes, r.bufferBytes), () => []).add(r.avgMBps!);
  }
  return {for (final e in groups.entries) e.key: median(e.value)!};
}

/// The buffer to use: the best median that is within [tolerance] of the
/// best for every file size measured; ties go to [preferred] (1 MB, the
/// current default). Null without results. Sizes under 100 MB are left
/// out: they finish too fast to tell buffers apart.
int? bestBuffer(
  Iterable<BenchResult> results, {
  double tolerance = 0.05,
  int preferred = 1024 * 1024,
  int minFileBytes = 100 * 1024 * 1024,
}) {
  final medians = medianByCase(results)
    ..removeWhere((k, _) => k.$1 < minFileBytes);
  if (medians.isEmpty) return null;
  final sizes = medians.keys.map((k) => k.$1).toSet();
  final buffers = medians.keys.map((k) => k.$2).toSet();
  final candidates = <int, double>{};
  for (final b in buffers) {
    var ok = true;
    var sum = 0.0;
    for (final s in sizes) {
      final best = medians.entries
          .where((e) => e.key.$1 == s)
          .map((e) => e.value)
          .reduce((a, c) => a > c ? a : c);
      final mine = medians[(s, b)];
      if (mine == null || mine < best * (1 - tolerance)) ok = false;
      sum += mine ?? 0;
    }
    if (ok) candidates[b] = sum;
  }
  if (candidates.isEmpty) {
    // None is close everywhere: the highest total wins.
    final totals = <int, double>{};
    for (final e in medians.entries) {
      totals[e.key.$2] = (totals[e.key.$2] ?? 0) + e.value;
    }
    return totals.entries.reduce((a, c) => a.value >= c.value ? a : c).key;
  }
  if (candidates.containsKey(preferred)) return preferred;
  return candidates.entries.reduce((a, c) => a.value >= c.value ? a : c).key;
}
