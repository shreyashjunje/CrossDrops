import 'package:crossdrop/core/engine/speed_meter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Duration now;
  SpeedMeter meter() => SpeedMeter(clock: () => now);

  setUp(() => now = Duration.zero);

  test('is zero with fewer than two samples', () {
    final m = meter();
    expect(m.bytesPerSecond, 0);
    m.add(100);
    expect(m.bytesPerSecond, 0);
  });

  test('computes a steady rate', () {
    final m = meter();
    for (var i = 0; i <= 10; i++) {
      now = Duration(milliseconds: 500 * i);
      m.add(i * 5000000); // 10 MB/s
    }
    expect(m.megabytesPerSecond, closeTo(10, 1e-9));
  });

  test('only averages the last 3 seconds', () {
    final m = meter();
    // 10 s at 1 MB/s, then 3 s at 20 MB/s.
    var bytes = 0;
    for (var i = 1; i <= 10; i++) {
      now = Duration(seconds: i);
      bytes += 1000000;
      m.add(bytes);
    }
    for (var i = 1; i <= 30; i++) {
      now = Duration(seconds: 10, milliseconds: 100 * i);
      bytes += 2000000;
      m.add(bytes);
    }
    expect(m.megabytesPerSecond, closeTo(20, 0.01));
  });

  test('reset clears samples', () {
    final m = meter()..add(0);
    now = const Duration(seconds: 1);
    m.add(1000);
    m.reset();
    expect(m.bytesPerSecond, 0);
  });
}
