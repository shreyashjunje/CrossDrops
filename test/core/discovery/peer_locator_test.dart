import 'package:crossdrop/core/discovery/mdns_backend.dart';
import 'package:crossdrop/core/discovery/peer_locator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_mdns_backend.dart';

const own = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const peerId = '3f2a9c1b-0d4e-4f5a-8b6c-7d8e9f0a1b2c';

MdnsServiceResolved resolved(String id, int port) => MdnsServiceResolved(
  'CrossDrop-${id.substring(0, 8)}',
  hostAddresses: const ['192.168.1.23'],
  port: port,
  attributes: {
    'v': '2',
    'id': id,
    'n': 'Pixel',
    'p': 'android',
    'fp': '0123456789abcdef',
  },
);

void main() {
  test('finds the device by id at its new port', () async {
    final backend = FakeMdnsBackend();
    final result = locatePeer(backend, deviceId: peerId, ownDeviceId: own);
    await Future<void>.delayed(Duration.zero);
    backend.emit(resolved('11111111-1111-4111-8111-111111111111', 1000));
    backend.emit(resolved(peerId, 53999));
    expect(await result, (host: '192.168.1.23', port: 53999));
    expect(backend.isBrowsing, isFalse);
  });

  test('null when the device does not show up', () async {
    final backend = FakeMdnsBackend();
    final result = await locatePeer(
      backend,
      deviceId: peerId,
      ownDeviceId: own,
      timeout: const Duration(milliseconds: 50),
    );
    expect(result, isNull);
    expect(backend.isBrowsing, isFalse);
  });

  test('null when browsing fails', () async {
    final backend = FakeMdnsBackend()..failNextBrowse = true;
    expect(
      await locatePeer(backend, deviceId: peerId, ownDeviceId: own),
      isNull,
    );
  });
}
