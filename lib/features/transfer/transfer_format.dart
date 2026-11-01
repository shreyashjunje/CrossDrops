/// Megabytes as 10^6 bytes, matching the MB/s figures in BENCHMARKS.md.
String formatMegabytes(int bytes) => '${(bytes / 1e6).toStringAsFixed(1)} MB';

String formatSpeed(double bytesPerSecond) =>
    '${(bytesPerSecond / 1e6).toStringAsFixed(1)} MB/s';

String formatDuration(Duration d) =>
    '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';
