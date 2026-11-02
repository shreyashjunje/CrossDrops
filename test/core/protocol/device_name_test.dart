import 'dart:convert';

import 'package:crossdrop/core/protocol/device_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps a normal name', () {
    expect(sanitizeDeviceName("Shreyash's iPhone"), "Shreyash's iPhone");
  });

  test('removes control and bidi characters and collapses spaces', () {
    expect(sanitizeDeviceName('a\u0000b\u202ec\r\n  d\t'), 'abc d');
  });

  test('cuts to 63 UTF-8 bytes without splitting characters', () {
    final long = sanitizeDeviceName('é' * 40); // 80 bytes
    expect(utf8.encode(long).length, lessThanOrEqualTo(maxDeviceNameBytes));
    expect(long, 'é' * 31);
    expect(sanitizeDeviceName('📱' * 20), '📱' * 15); // 4 bytes each
  });

  test('returns empty when nothing is left', () {
    expect(sanitizeDeviceName('\u0001\u0002 '), '');
  });
}
