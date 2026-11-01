import 'dart:collection';

/// Transfer speed as a moving average over the last [window]
/// (ARCHITECTURE.md: 3 seconds).
class SpeedMeter {
  SpeedMeter({
    this.window = const Duration(seconds: 3),
    Duration Function()? clock,
  }) : _clock = clock ?? Stopwatch().elapsedFn();

  final Duration window;
  final Duration Function() _clock;
  final Queue<(Duration, int)> _samples = Queue();

  /// Records that [totalBytes] have been transferred so far.
  void add(int totalBytes) {
    final now = _clock();
    _samples.addLast((now, totalBytes));
    // Keep one sample at or before the window start so the average covers
    // the whole window.
    while (_samples.length > 2 && now - _samples.elementAt(1).$1 >= window) {
      _samples.removeFirst();
    }
  }

  /// Bytes per second over the window, or 0 before there are two samples.
  double get bytesPerSecond {
    if (_samples.length < 2) return 0;
    final (t0, b0) = _samples.first;
    final (t1, b1) = _samples.last;
    final micros = (t1 - t0).inMicroseconds;
    if (micros <= 0) return 0;
    return (b1 - b0) * Duration.microsecondsPerSecond / micros;
  }

  /// Megabytes (10^6 bytes) per second, as shown in the UI and benchmarks.
  double get megabytesPerSecond => bytesPerSecond / 1e6;

  void reset() => _samples.clear();
}

extension on Stopwatch {
  Duration Function() elapsedFn() {
    start();
    return () => elapsed;
  }
}
