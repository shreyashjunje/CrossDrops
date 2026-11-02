/// Megabytes as 10^6 bytes, matching the MB/s figures in BENCHMARKS.md.
String formatMegabytes(int bytes) => '${(bytes / 1e6).toStringAsFixed(1)} MB';

/// MB below 1 GB, GB above (10^9 bytes).
String formatSize(int bytes) => bytes >= 1e9
    ? '${(bytes / 1e9).toStringAsFixed(2)} GB'
    : formatMegabytes(bytes);

String formatSpeed(double bytesPerSecond) =>
    '${(bytesPerSecond / 1e6).toStringAsFixed(1)} MB/s';

String formatDuration(Duration d) =>
    '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';

/// "about 3 min left", "12 s left"; empty while there is no estimate.
String formatTimeLeft(Duration? eta) {
  if (eta == null) return '';
  final s = eta.inSeconds;
  if (s < 60) return '${s < 1 ? 1 : s} s left';
  if (s < 3600) {
    final m = (s / 60).round();
    return 'about $m min left';
  }
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  return 'about $h h $m min left';
}
