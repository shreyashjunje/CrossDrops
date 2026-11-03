import 'package:crossdrop/core/discovery/peer_list.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:flutter_test/flutter_test.dart';

const _own = '00000000-0000-4000-8000-000000000000';
const _a = 'aaaaaaaa-0000-4000-8000-000000000001';
const _b = 'bbbbbbbb-0000-4000-8000-000000000002';

Map<String, String> _txt(
  String id, {
  String name = 'Phone',
  String platform = 'android',
  String v = '2',
}) => {'v': v, 'id': id, 'n': name, 'p': platform, 'fp': '0123456789abcdef'};

void main() {
  late PeerList list;

  setUp(() => list = PeerList(ownDeviceId: _own));

  List<PeerChange> resolve(
    String service,
    String id, {
    List<String> hosts = const ['192.168.1.10'],
    int port = 4000,
    String name = 'Phone',
    String platform = 'android',
    String v = '2',
  }) => list.resolved(
    service,
    hostAddresses: hosts,
    port: port,
    attributes: _txt(id, name: name, platform: platform, v: v),
  );

  test('a new device is added', () {
    final changes = resolve('svcA', _a, platform: 'ios');
    expect(changes, [isA<PeerAdded>()]);
    final peer = (changes.single as PeerAdded).peer;
    expect(peer.deviceId, _a);
    expect(peer.host, '192.168.1.10');
    expect(peer.port, 4000);
    expect(peer.platform, DevicePlatform.ios);
    expect(peer.fingerprintHint, '0123456789abcdef');
    expect(peer.isSupported, isTrue);
    expect(list.peers.keys, [_a]);
  });

  test('the same record again changes nothing', () {
    resolve('svcA', _a);
    expect(resolve('svcA', _a), isEmpty);
  });

  test('a new name, IP or port is an update', () {
    resolve('svcA', _a);
    expect(resolve('svcA', _a, name: 'Renamed'), [isA<PeerUpdated>()]);
    expect(resolve('svcA', _a, name: 'Renamed', hosts: ['192.168.1.99']), [
      isA<PeerUpdated>(),
    ]);
    final changes = resolve(
      'svcA',
      _a,
      name: 'Renamed',
      hosts: ['192.168.1.99'],
      port: 5000,
    );
    final peer = (changes.single as PeerUpdated).peer;
    expect(peer.name, 'Renamed');
    expect(peer.host, '192.168.1.99');
    expect(peer.port, 5000);
  });

  test('lost removes the device', () {
    resolve('svcA', _a);
    final changes = list.lost('svcA');
    expect(changes.single, isA<PeerRemoved>());
    expect(changes.single.deviceId, _a);
    expect(list.peers, isEmpty);
  });

  test('lost for an unknown service changes nothing', () {
    expect(list.lost('nobody'), isEmpty);
  });

  test('two services for one device: removed only when both are lost', () {
    resolve('svcA', _a);
    expect(resolve('svcA (2)', _a, hosts: ['10.0.0.5']), [isA<PeerUpdated>()]);
    expect(list.lost('svcA'), isEmpty);
    expect(list.peers.keys, [_a]);
    expect(list.lost('svcA (2)'), [isA<PeerRemoved>()]);
  });

  test('a service that now points to another device moves over', () {
    resolve('svc', _a);
    final changes = resolve('svc', _b);
    expect(changes, [isA<PeerRemoved>(), isA<PeerAdded>()]);
    expect(changes[0].deviceId, _a);
    expect(changes[1].deviceId, _b);
    expect(list.peers.keys, [_b]);
  });

  test('several devices are tracked independently', () {
    resolve('svcA', _a);
    resolve('svcB', _b, hosts: ['192.168.1.11']);
    expect(list.peers.keys, unorderedEquals([_a, _b]));
    list.lost('svcA');
    expect(list.peers.keys, [_b]);
  });

  group('ignored records', () {
    test('own device id, and sawSelf turns true', () {
      expect(list.sawSelf, isFalse);
      expect(resolve('mine', _own), isEmpty);
      expect(list.peers, isEmpty);
      expect(list.sawSelf, isTrue);
    });

    test('bad TXT', () {
      expect(
        list.resolved(
          'svc',
          hostAddresses: ['192.168.1.10'],
          port: 4000,
          attributes: {'v': '2', 'id': 'nope'},
        ),
        isEmpty,
      );
    });

    test('bad TXT for a known service removes the device', () {
      resolve('svc', _a);
      final changes = list.resolved(
        'svc',
        hostAddresses: ['192.168.1.10'],
        port: 4000,
        attributes: {'garbage': 'x'},
      );
      expect(changes, [isA<PeerRemoved>()]);
    });

    test('no local IPv4 address', () {
      expect(resolve('svc', _a, hosts: []), isEmpty);
      expect(resolve('svc', _a, hosts: ['fe80::1%wlan0']), isEmpty);
      expect(resolve('svc', _a, hosts: ['8.8.8.8']), isEmpty);
      expect(resolve('svc', _a, hosts: ['127.0.0.1']), isEmpty);
      expect(list.peers, isEmpty);
    });

    test('picks the first local IPv4 among several addresses', () {
      final changes = resolve(
        'svc',
        _a,
        hosts: ['fe80::1', '8.8.8.8', '172.20.10.2', '192.168.1.3'],
      );
      expect((changes.single as PeerAdded).peer.host, '172.20.10.2');
    });

    test('bad port', () {
      expect(resolve('svc', _a, port: 0), isEmpty);
      expect(resolve('svc', _a, port: 70000), isEmpty);
    });
  });

  test('a newer protocol version is listed but not supported', () {
    final changes = list.resolved(
      'svc',
      hostAddresses: ['192.168.1.10'],
      port: 4000,
      attributes: {'v': '3', 'id': _a, 'n': 'Future'},
    );
    final peer = (changes.single as PeerAdded).peer;
    expect(peer.isSupported, isFalse);
    expect(peer.platform, isNull);
  });

  test('unreachable removes the device and its services', () {
    resolve('svcA', _a);
    resolve('svcA (2)', _a);
    expect(list.unreachable(_a), [isA<PeerRemoved>()]);
    expect(list.peers, isEmpty);
    expect(list.lost('svcA'), isEmpty);
    expect(list.unreachable(_a), isEmpty);
    // Seen again later: added again.
    expect(resolve('svcA', _a), [isA<PeerAdded>()]);
  });

  test('clear removes everything and resets sawSelf', () {
    resolve('svcA', _a);
    resolve('svcB', _b);
    resolve('mine', _own);
    final changes = list.clear();
    expect(changes.map((c) => c.deviceId), unorderedEquals([_a, _b]));
    expect(changes, everyElement(isA<PeerRemoved>()));
    expect(list.peers, isEmpty);
    expect(list.sawSelf, isFalse);
  });
}
