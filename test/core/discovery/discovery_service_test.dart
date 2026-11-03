import 'package:crossdrop/core/discovery/discovery_service.dart';
import 'package:crossdrop/core/discovery/mdns_backend.dart';
import 'package:crossdrop/core/discovery/peer_list.dart';
import 'package:crossdrop/core/discovery/txt_record.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_mdns_backend.dart';

const _own = '00000000-0000-4000-8000-000000000000';
const _a = 'aaaaaaaa-0000-4000-8000-000000000001';

MdnsServiceResolved _resolved(String service, String id) => MdnsServiceResolved(
  service,
  hostAddresses: const ['192.168.1.10'],
  port: 4000,
  attributes: {
    'v': '2',
    'id': id,
    'n': 'Phone',
    'p': 'ios',
    'fp': '0123456789abcdef',
  },
);

void main() {
  test('serviceNameFor uses the first 8 characters of the id', () {
    expect(serviceNameFor(_a), 'CrossDrop-aaaaaaaa');
  });

  group('PeerBrowser', () {
    late FakeMdnsBackend backend;
    late PeerBrowser browser;
    late List<PeerChange> changes;

    setUp(() {
      backend = FakeMdnsBackend();
      browser = PeerBrowser(backend, ownDeviceId: _own);
      changes = [];
      browser.changes.listen(changes.add);
    });

    tearDown(() => browser.dispose());

    test('streams add and remove events from mDNS', () async {
      await browser.start();
      backend.emit(_resolved('svc', _a));
      await pumpEventQueue();
      expect(changes, [isA<PeerAdded>()]);
      expect(browser.peers.keys, [_a]);

      backend.emit(const MdnsServiceLost('svc'));
      await pumpEventQueue();
      expect(changes.last, isA<PeerRemoved>());
      expect(browser.peers, isEmpty);
    });

    test('start twice browses once', () async {
      await browser.start();
      await browser.start();
      expect(backend.browseStarts, 1);
    });

    test('stop clears the list with remove events', () async {
      await browser.start();
      backend.emit(_resolved('svc', _a));
      await pumpEventQueue();
      await browser.stop();
      await pumpEventQueue();
      expect(changes.last, isA<PeerRemoved>());
      expect(browser.peers, isEmpty);
      expect(backend.isBrowsing, isFalse);
    });

    test('restart browses again from an empty list', () async {
      await browser.start();
      backend.emit(_resolved('svc', _a));
      await pumpEventQueue();
      await browser.restart();
      expect(backend.browseStarts, 2);
      expect(browser.peers, isEmpty);
      backend.emit(_resolved('svc', _a));
      await pumpEventQueue();
      expect(browser.peers.keys, [_a]);
    });

    test('markUnreachable removes the device', () async {
      await browser.start();
      backend.emit(_resolved('svc', _a));
      await pumpEventQueue();
      browser.markUnreachable(_a);
      await pumpEventQueue();
      expect(changes.last, isA<PeerRemoved>());
    });

    test('sawSelf reflects our own advertisement', () async {
      await browser.start();
      backend.emit(_resolved('mine', _own));
      await pumpEventQueue();
      expect(browser.sawSelf, isTrue);
      expect(changes, isEmpty);
    });

    test('a failed start can be retried', () async {
      backend.failNextBrowse = true;
      await expectLater(browser.start(), throwsStateError);
      expect(browser.isRunning, isFalse);
      await browser.start();
      expect(browser.isRunning, isTrue);
    });
  });

  group('Advertiser', () {
    final txt = TxtRecord.forDevice(
      identity: const DeviceIdentity(deviceId: _a, deviceName: 'Pixel'),
      platform: DevicePlatform.android,
      fingerprint: 'f' * 64,
    );

    test('advertises name, port and TXT', () async {
      final backend = FakeMdnsBackend();
      final ad = Advertiser(backend);
      await ad.start(txt: txt, port: 4321);
      expect(ad.isAdvertising, isTrue);
      expect(backend.current!.serviceName, 'CrossDrop-aaaaaaaa');
      expect(backend.current!.port, 4321);
      expect(backend.current!.attributes, txt.encode());
    });

    test('restart re-registers the same service', () async {
      final backend = FakeMdnsBackend();
      final ad = Advertiser(backend);
      await ad.start(txt: txt, port: 4321);
      await ad.restart();
      expect(backend.advertisements, hasLength(3));
      expect(backend.advertisements[1], isNull);
      expect(backend.advertisements[2]!.port, 4321);
    });

    test('restart and stop do nothing when not advertising', () async {
      final backend = FakeMdnsBackend();
      final ad = Advertiser(backend);
      await ad.restart();
      await ad.stop();
      expect(backend.advertisements, isEmpty);
    });
  });
}
