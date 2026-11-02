import 'package:crossdrop/features/transfer/transfer_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatSize switches to GB at 10^9 bytes', () {
    expect(formatSize(999999999), '1000.0 MB');
    expect(formatSize(2000000000), '2.00 GB');
  });

  test('formatTimeLeft', () {
    expect(formatTimeLeft(null), '');
    expect(formatTimeLeft(Duration.zero), '1 s left');
    expect(formatTimeLeft(const Duration(seconds: 42)), '42 s left');
    expect(formatTimeLeft(const Duration(seconds: 150)), 'about 3 min left');
    expect(
      formatTimeLeft(const Duration(hours: 1, minutes: 5)),
      'about 1 h 5 min left',
    );
  });
}
