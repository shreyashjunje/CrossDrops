import 'package:crossdrop/core/protocol/connect_payload.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = '3f2a9c1b-0d4e-4f5a-8b6c-7d8e9f0a1b2c';
const _fp = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

String _query({
  String v = '1',
  String ip = '192.168.1.23',
  String port = '53317',
  String fp = _fp,
  String id = _id,
  String n = 'Pixel%207',
}) => 'v=$v&ip=$ip&port=$port&fp=$fp&id=$id&n=$n';

String _uri([String? query]) => 'crossdrop://connect?${query ?? _query()}';

void main() {
  test('parses a valid payload', () {
    final p = ConnectPayload.parse(_uri());
    expect(p.ip, '192.168.1.23');
    expect(p.port, 53317);
    expect(p.fingerprint, _fp);
    expect(p.deviceId, _id);
    expect(p.name, 'Pixel 7');
  });

  test('toUri round-trips, including spaces and non-ASCII names', () {
    const original = ConnectPayload(
      ip: '172.20.10.1',
      port: 8443,
      fingerprint: _fp,
      deviceId: _id,
      name: "Shreyash's iPhone & café 📱",
    );
    final uri = original.toUri();
    expect(uri, startsWith('crossdrop://connect?v=1&ip=172.20.10.1&port=8443'));
    final parsed = ConnectPayload.parse(uri);
    expect(parsed.ip, original.ip);
    expect(parsed.port, original.port);
    expect(parsed.fingerprint, original.fingerprint);
    expect(parsed.deviceId, original.deviceId);
    expect(parsed.name, original.name);
  });

  test('accepts surrounding whitespace, upper-case scheme, hex and id', () {
    final p = ConnectPayload.parse(
      '  CROSSDROP://connect?${_query(fp: _fp.toUpperCase(), id: _id.toUpperCase())}\n',
    );
    expect(p.fingerprint, _fp);
    expect(p.deviceId, _id);
  });

  test('accepts a trailing slash and ignores unknown parameters', () {
    final p = ConnectPayload.parse(
      'crossdrop://connect/?${_query()}&ssid=Hotspot&future=1',
    );
    expect(p.port, 53317);
  });

  test('accepts every local IPv4 range', () {
    for (final ip in [
      '10.0.0.1',
      '172.16.0.1',
      '172.31.255.254',
      '192.168.0.1',
      '169.254.10.20',
      '100.64.0.1',
      '100.127.255.254',
    ]) {
      expect(ConnectPayload.parse(_uri(_query(ip: ip))).ip, ip);
    }
  });

  test('sanitizes the name', () {
    final p = ConnectPayload.parse(_uri(_query(n: 'A%00B%E2%80%AEC%0A')));
    expect(p.name, 'ABC');
  });

  group('rejects', () {
    void rejects(String why, String raw, ConnectPayloadError error) =>
        test(why, () {
          expect(
            () => ConnectPayload.parse(raw),
            throwsA(
              isA<ConnectPayloadException>().having(
                (e) => e.error,
                'error',
                error,
              ),
            ),
          );
        });

    const not = ConnectPayloadError.notCrossDrop;
    const bad = ConnectPayloadError.invalid;

    // Not a CrossDrop code.
    rejects('empty string', '', not);
    rejects('plain text', 'hello', not);
    rejects('web URL', 'https://example.com/?${_query()}', not);
    rejects('javascript URL', 'javascript:alert(1)', not);
    rejects('wifi QR', 'WIFI:S:Home;T:WPA;P:secret;;', not);
    rejects('other host', 'crossdrop://evil?${_query()}', not);
    rejects('look-alike host', 'crossdrop://соnnect?${_query()}', not);
    rejects('user info', 'crossdrop://a@connect?${_query()}', not);
    rejects('port in authority', 'crossdrop://connect:80?${_query()}', not);
    rejects('extra path', 'crossdrop://connect/x?${_query()}', not);
    rejects('fragment', '${_uri()}#x', not);
    rejects('space inside', 'crossdrop://connect?v=1 &${_query()}', not);
    rejects('newline inside', 'crossdrop://connect?\n${_query()}', not);
    rejects('null byte inside', 'crossdrop://connect?\u0000${_query()}', not);

    // Version.
    rejects(
      'newer version',
      _uri(_query(v: '2')),
      ConnectPayloadError.unsupportedVersion,
    );
    rejects('version zero', _uri(_query(v: '0')), bad);
    rejects('version not a number', _uri(_query(v: 'x')), bad);

    // Shape of the query.
    rejects('too long', '${_uri()}&pad=${'a' * 1024}', bad);
    rejects('bad percent encoding', _uri(_query(n: '%zz')), bad);
    rejects('truncated percent encoding', _uri(_query(n: 'a%2')), bad);
    rejects('invalid UTF-8', _uri(_query(n: '%E2%28')), bad);
    rejects('missing ip', _uri('v=1&port=1&fp=$_fp&id=$_id&n=a'), bad);
    rejects('missing n', _uri('v=1&ip=10.0.0.1&port=1&fp=$_fp&id=$_id'), bad);
    rejects('repeated ip', '${_uri()}&ip=192.168.1.99', bad);
    rejects('repeated v', '${_uri()}&v=1', bad);

    // IP: never a hostname, never outside the local network.
    for (final ip in [
      'localhost',
      'example.com',
      '8.8.8.8',
      '127.0.0.1',
      '0.0.0.0',
      '255.255.255.255',
      '224.0.0.251',
      '172.32.0.1',
      '100.128.0.1',
      '192.168.1.256',
      '192.168.01.1',
      '192.168.1',
      '192.168.1.1.1',
      '0xC0.168.1.1',
      '%5B::1%5D',
      'fe80::1',
      '',
    ]) {
      rejects('ip "$ip"', _uri(_query(ip: ip)), bad);
    }

    // Port.
    for (final port in ['0', '65536', '-1', '+80', '0x50', '080', '', '1e3']) {
      rejects('port "$port"', _uri(_query(port: port)), bad);
    }

    // Fingerprint and id.
    rejects('fp too short', _uri(_query(fp: _fp.substring(1))), bad);
    rejects('fp too long', _uri(_query(fp: '${_fp}0')), bad);
    rejects('fp not hex', _uri(_query(fp: 'g' * 64)), bad);
    rejects('id not a UUID', _uri(_query(id: '..%2F..%2Fetc')), bad);
    rejects('name only control characters', _uri(_query(n: '%01%02')), bad);
    rejects('name empty', _uri(_query(n: '')), bad);
  });

  test('error text never contains the payload', () {
    try {
      ConnectPayload.parse(_uri(_query(ip: '8.8.8.8')));
      fail('should throw');
    } on ConnectPayloadException catch (e) {
      expect(e.toString(), isNot(contains('8.8.8.8')));
      expect(e.toString(), isNot(contains(_fp)));
    }
  });

  group('hotspot Wi-Fi fields', () {
    const wifi = WifiCredentials(
      ssid: 'AndroidShare_1234',
      password: 'p@ss word&=%#?x',
      security: WifiSecurity.wpa3Transition,
    );

    test('round-trip, including characters that need escaping', () {
      const original = ConnectPayload(
        ip: '192.168.49.1',
        port: 40000,
        fingerprint: _fp,
        deviceId: _id,
        name: 'Pixel',
        wifi: wifi,
      );
      final parsed = ConnectPayload.parse(original.toUri());
      expect(parsed.wifi, wifi);
      expect(parsed.ip, '192.168.49.1');
    });

    test('absent outside hotspot mode', () {
      expect(ConnectPayload.parse(_uri()).wifi, isNull);
    });

    test('security defaults to WPA2', () {
      final p = ConnectPayload.parse('${_uri()}&ws=Net&wp=12345678');
      expect(p.wifi!.security, WifiSecurity.wpa2);
    });

    test('accepts a 32-byte name with non-ASCII characters', () {
      final name = '${'a' * 29}é'; // 31 bytes
      final p = ConnectPayload.parse(
        '${_uri()}&ws=${Uri.encodeQueryComponent(name)}&wp=12345678',
      );
      expect(p.wifi!.ssid, name);
    });

    test('toString leaves out the name and password', () {
      final p = ConnectPayload.parse(
        ConnectPayload(
          ip: '192.168.49.1',
          port: 1,
          fingerprint: _fp,
          deviceId: _id,
          name: 'x',
          wifi: wifi,
        ).toUri(),
      );
      expect('${p.wifi}', isNot(contains('AndroidShare')));
      expect('${p.wifi}', isNot(contains('p@ss')));
    });

    void rejects(String why, String extra) => test('rejects $why', () {
      expect(
        () => ConnectPayload.parse('${_uri()}$extra'),
        throwsA(
          isA<ConnectPayloadException>().having(
            (e) => e.error,
            'error',
            ConnectPayloadError.invalid,
          ),
        ),
      );
    });

    rejects('name without password', '&ws=Net');
    rejects('password without name', '&wp=12345678');
    rejects('security alone', '&wsec=wpa2');
    rejects('empty name', '&ws=&wp=12345678');
    rejects('name over 32 bytes', '&ws=${'a' * 33}&wp=12345678');
    rejects('control character in name', '&ws=a%0Ab&wp=12345678');
    rejects('password too short', '&ws=Net&wp=1234567');
    rejects('password too long', '&ws=Net&wp=${'a' * 64}');
    rejects('non-ASCII password', '&ws=Net&wp=12345678%C3%A9');
    rejects('unknown security', '&ws=Net&wp=12345678&wsec=wep');
    rejects('repeated name', '&ws=Net&ws=Other&wp=12345678');
  });

  test('isLocalIPv4 and parseIPv4', () {
    expect(parseIPv4('10.1.2.3'), [10, 1, 2, 3]);
    expect(parseIPv4('1.2.3'), isNull);
    expect(isLocalIPv4([192, 168, 0, 1]), isTrue);
    expect(isLocalIPv4([11, 0, 0, 1]), isFalse);
    expect(isLocalIPv4([1, 2, 3]), isFalse);
  });
}
