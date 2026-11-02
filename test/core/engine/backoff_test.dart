import 'package:crossdrop/core/engine/backoff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Duration now;
  Backoff make({double jitter = 0}) =>
      Backoff(jitter: jitter, clock: () => now);

  setUp(() => now = Duration.zero);

  test('1, 2, 4, 8 then 8 again', () {
    final b = make();
    final delays = <int>[];
    for (var i = 0; i < 6; i++) {
      final d = b.next()!;
      delays.add(d.inSeconds);
      now += d;
    }
    expect(delays, [1, 2, 4, 8, 8, 8]);
  });

  test('gives up after 2 minutes without progress', () {
    final b = make();
    var tries = 0;
    Duration? d;
    while ((d = b.next()) != null) {
      now += d!;
      tries++;
    }
    expect(now, const Duration(minutes: 2));
    // 1+2+4+8 = 15 s, then 8 s steps up to 120 s.
    expect(tries, 4 + 14);
  });

  test('progress resets the delay and the deadline', () {
    final b = make();
    now += b.next()!;
    now += b.next()!;
    now = const Duration(minutes: 5);
    b.reset();
    expect(b.next(), const Duration(seconds: 1));
    expect(b.attempts, 1);
  });

  test('jitter stays within ±20 %', () {
    final b = make(jitter: 0.2);
    for (var i = 0; i < 200; i++) {
      b.reset();
      final d = b.next()!;
      expect(d.inMilliseconds, inInclusiveRange(800, 1200));
    }
  });

  test('never waits past the deadline', () {
    final b = Backoff(
      jitter: 0,
      giveUpAfter: const Duration(seconds: 3),
      clock: () => now,
    );
    now += b.next()!; // 1 s
    now += b.next()!; // 2 s -> 3 s total
    expect(b.next(), isNull);
  });
}
