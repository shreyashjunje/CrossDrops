import 'package:crossdrop/core/engine/progress_tracker.dart';
import 'package:crossdrop/core/engine/speed_meter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Duration now;
  late ProgressTracker t;

  setUp(() {
    now = Duration.zero;
    t = ProgressTracker({
      'a': 1000,
      'b': 3000,
    }, meter: SpeedMeter(clock: () => now));
  });

  test('totals and fraction', () {
    t.set('a', 500);
    expect(t.totalBytes, 4000);
    expect(t.doneBytes, 500);
    expect(t.fraction, 0.125);
    t.set('a', 1000);
    t.set('b', 1000);
    expect(t.doneBytes, 2000);
    expect(t.bytesOf('b'), 1000);
  });

  test('speed and time left', () {
    expect(t.eta, isNull);
    t.set('a', 0);
    now = const Duration(seconds: 1);
    t.set('a', 1000);
    expect(t.bytesPerSecond, 1000);
    expect(t.eta, const Duration(seconds: 3));
  });

  test('values are clamped and unknown files ignored', () {
    t.set('a', 5000);
    t.set('b', -3);
    t.set('zzz', 10);
    expect(t.doneBytes, 1000);
  });

  test('going backwards resets the speed', () {
    t.set('a', 0);
    now = const Duration(seconds: 1);
    t.set('a', 800);
    t.set('a', 0); // hash mismatch restart
    expect(t.doneBytes, 0);
    expect(t.bytesPerSecond, 0);
  });

  test('drop counts a failed file as finished for the total', () {
    t.drop('b');
    expect(t.doneBytes, 3000);
  });

  test('empty session is complete', () {
    expect(ProgressTracker({}).fraction, 1);
  });
}
