import 'package:crossdrop/features/nearby/manual_address_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('host: local IPv4 literals only', () {
    expect(validateManualHost('192.168.1.23'), isNull);
    expect(validateManualHost(' 10.0.0.5 '), isNull);
    expect(validateManualHost('172.20.10.1'), isNull);
    expect(validateManualHost('8.8.8.8'), isNotNull);
    expect(validateManualHost('localhost'), isNotNull);
    expect(validateManualHost('192.168.1'), isNotNull);
    expect(validateManualHost('192.168.1.300'), isNotNull);
    expect(validateManualHost(''), isNotNull);
  });

  test('port: 1 to 65535, digits only', () {
    expect(validateManualPort('8443'), isNull);
    expect(validateManualPort(' 1 '), isNull);
    expect(validateManualPort('65535'), isNull);
    expect(validateManualPort('0'), isNotNull);
    expect(validateManualPort('65536'), isNotNull);
    expect(validateManualPort('-1'), isNotNull);
    expect(validateManualPort('080'), isNotNull);
    expect(validateManualPort('0x50'), isNotNull);
    expect(validateManualPort(''), isNotNull);
  });
}
