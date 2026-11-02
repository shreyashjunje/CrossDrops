import 'dart:math';

/// Retry delays after a connection failure (ARCHITECTURE.md, "Wi-Fi drops
/// mid-transfer"): 1, 2, 4, 8 s, then 8 s again, each with ±20 % jitter,
/// until [giveUpAfter] passes without progress (D-019).
class Backoff {
  Backoff({
    this.steps = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
    ],
    this.giveUpAfter = const Duration(minutes: 2),
    this.jitter = 0.2,
    Random? random,
    Duration Function()? clock,
  }) : _random = random ?? Random(),
       _clock = clock ?? _stopwatchClock();

  final List<Duration> steps;
  final Duration giveUpAfter;

  /// Fraction of each delay added or removed at random, so two phones
  /// don't retry in lockstep.
  final double jitter;
  final Random _random;
  final Duration Function() _clock;

  int _attempt = 0;
  Duration? _streakStart;

  /// Failures since the last [reset].
  int get attempts => _attempt;

  /// Call when bytes moved: the next failure starts from 1 s again.
  void reset() {
    _attempt = 0;
    _streakStart = null;
  }

  /// The delay before the next try, or null to give up.
  Duration? next() {
    final now = _clock();
    final start = _streakStart ??= now;
    if (now - start >= giveUpAfter) return null;
    final base = steps[min(_attempt, steps.length - 1)];
    _attempt++;
    final factor = 1 + jitter * (2 * _random.nextDouble() - 1);
    final delay = base * factor;
    // Never wait past the deadline.
    final left = giveUpAfter - (now - start);
    return delay < left ? delay : left;
  }

  static Duration Function() _stopwatchClock() {
    final w = Stopwatch()..start();
    return () => w.elapsed;
  }
}
