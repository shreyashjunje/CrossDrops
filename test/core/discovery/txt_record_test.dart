import 'package:crossdrop/core/discovery/txt_record.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = '3f2a9c1b-0d4e-4f5a-8b6c-7d8e9f0a1b2c';
const _fp = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

Map<String, String> _valid() => {
  'v': '1',
  'id': _id,
  'n': "Shreyash's iPhone",
  'p': 'ios',
  'fp': '0123456789abcdef',
};

void main() {
  test('forDevice builds the record with a 16-char fingerprint hint', () {
    final txt = TxtRecord.forDevice(
      identity: const DeviceIdentity(deviceId: _id, deviceName: 'Pixel'),
      platform: DevicePlatform.android,
      fingerprint: _fp,
    );
    expect(txt.encode(), {
      'v': '1',
      'id': _id,
      'n': 'Pixel',
      'p': 'android',
      'fp': '0123456789abcdef',
    });
  });

  test('encode then decode round-trips', () {
    final txt = TxtRecord.decode(_valid());
    expect(txt.version, protocolVersion);
    expect(txt.isSupported, isTrue);
    expect(txt.deviceId, _id);
    expect(txt.name, "Shreyash's iPhone");
    expect(txt.platform, DevicePlatform.ios);
    expect(txt.fingerprintHint, '0123456789abcdef');
    expect(TxtRecord.decode(txt.encode()).encode(), txt.encode());
  });

  test('keys are case-insensitive, id and fp are lowercased', () {
    final txt = TxtRecord.decode({
      'V': '1',
      'ID': _id.toUpperCase(),
      'N': 'A',
      'P': 'android',
      'FP': '0123456789ABCDEF',
    });
    expect(txt.deviceId, _id);
    expect(txt.fingerprintHint, '0123456789abcdef');
  });

  test('unknown keys are ignored', () {
    expect(TxtRecord.decode({..._valid(), 'x': 'y'}).deviceId, _id);
  });

  test('name is sanitized', () {
    final txt = TxtRecord.decode({..._valid(), 'n': ' a\u0000\u202eb\n'});
    expect(txt.name, 'ab');
  });

  test('newer version needs only v, id and n', () {
    final txt = TxtRecord.decode({'v': '2', 'id': _id, 'n': 'Future'});
    expect(txt.version, 2);
    expect(txt.isSupported, isFalse);
    expect(txt.platform, isNull);
    expect(txt.fingerprintHint, isNull);
  });

  group('rejects', () {
    void rejects(String why, Map<String, String> attrs) => test(why, () {
      expect(() => TxtRecord.decode(attrs), throwsA(isA<FormatError>()));
    });

    rejects('empty record', {});
    rejects('missing v', {..._valid()}..remove('v'));
    rejects('v not a number', {..._valid(), 'v': 'one'});
    rejects('v zero', {..._valid(), 'v': '0'});
    rejects('v with sign', {..._valid(), 'v': '+1'});
    rejects('v huge', {..._valid(), 'v': '99999999999999999999'});
    rejects('missing id', {..._valid()}..remove('id'));
    rejects('id not a UUID', {..._valid(), 'id': '../../etc'});
    rejects('missing name', {..._valid()}..remove('n'));
    rejects('name only control characters', {..._valid(), 'n': '\u0001\t'});
    rejects('missing platform', {..._valid()}..remove('p'));
    rejects('unknown platform', {..._valid(), 'p': 'windows'});
    rejects('missing fp', {..._valid()}..remove('fp'));
    rejects('fp too short', {..._valid(), 'fp': '0123'});
    rejects('fp full length', {..._valid(), 'fp': _fp});
    rejects('fp not hex', {..._valid(), 'fp': 'zzzzzzzzzzzzzzzz'});
    rejects('duplicate key in different case', {..._valid(), 'ID': _id});
  });
}
