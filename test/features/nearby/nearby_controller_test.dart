import 'dart:async';

import 'package:crossdrop/app/providers.dart';
import 'package:crossdrop/core/client/peer_check.dart';
import 'package:crossdrop/core/client/upload_client.dart';
import 'package:crossdrop/core/discovery/mdns_backend.dart';
import 'package:crossdrop/core/protocol/connect_payload.dart';
import 'package:crossdrop/core/storage/database.dart';
import 'package:crossdrop/features/nearby/nearby_controller.dart';
import 'package:crossdrop/platform/local_network.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/discovery/fake_mdns_backend.dart';

const _a = 'aaaaaaaa-0000-4000-8000-000000000001';
const _b = 'bbbbbbbb-0000-4000-8000-000000000002';

class _FakeLocalNetwork implements LocalNetwork {
  LocalNetworkStatus answer = LocalNetworkStatus.denied;
  int probes = 0;

  @override
  Future<LocalNetworkStatus> probe() async {
    probes++;
    return answer;
  }

  @override
  Future<void> openSettings() async {}
}

MdnsServiceResolved _peer(String service, String id, String name) =>
    MdnsServiceResolved(
      service,
      hostAddresses: const ['192.168.1.10'],
      port: 4000,
      attributes: {
        'v': '2',
        'id': id,
        'n': name,
        'p': 'ios',
        'fp': '0123456789abcdef',
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMdnsBackend backend;
  late _FakeLocalNetwork localNetwork;
  late AppDatabase db;
  late List<ConnectTarget> checked;
  late Future<ConnectTarget> Function(ConnectTarget) check;

  setUp(() {
    backend = FakeMdnsBackend();
    localNetwork = _FakeLocalNetwork();
    db = AppDatabase(NativeDatabase.memory());
    checked = [];
    check = (t) async => t;
  });

  tearDown(() => db.close());

  ProviderContainer makeContainer({bool ios = true}) {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        mdnsBackendProvider.overrideWithValue(backend),
        localNetworkProvider.overrideWithValue(localNetwork),
        connectivityEventsProvider.overrideWithValue(const Stream.empty()),
        nearbySearchTimeoutProvider.overrideWithValue(
          const Duration(milliseconds: 50),
        ),
        checkLocalNetworkPermissionProvider.overrideWithValue(ios),
        peerCheckProvider.overrideWithValue((t) {
          checked.add(t);
          return check(t);
        }),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Subscribes so the auto-dispose controller stays alive, and waits for
  /// browsing to start.
  Future<NearbyController> open(ProviderContainer c) async {
    c.listen(nearbyControllerProvider, (_, _) {});
    for (var i = 0; i < 100 && !backend.isBrowsing; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(backend.isBrowsing, isTrue);
    return c.read(nearbyControllerProvider.notifier);
  }

  Future<void> settle([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  test('discovered devices appear sorted by name', () async {
    final c = makeContainer();
    await open(c);
    backend.emit(_peer('s1', _a, 'Zed'));
    backend.emit(_peer('s2', _b, 'amy'));
    await settle();
    final names = c
        .read(nearbyControllerProvider)
        .sortedPeers
        .map((p) => p.name);
    expect(names, ['amy', 'Zed']);
  });

  test('a lost device disappears', () async {
    final c = makeContainer();
    await open(c);
    backend.emit(_peer('s1', _a, 'A'));
    await settle();
    backend.emit(const MdnsServiceLost('s1'));
    await settle();
    expect(c.read(nearbyControllerProvider).peers, isEmpty);
  });

  test('iOS: nothing found and probe denied shows the explanation', () async {
    final c = makeContainer();
    await open(c);
    await settle(120);
    final s = c.read(nearbyControllerProvider);
    expect(s.searchedLong, isTrue);
    expect(localNetwork.probes, 1);
    expect(s.permissionDenied, isTrue);
  });

  test('iOS: a device found later clears the denied state', () async {
    final c = makeContainer();
    await open(c);
    await settle(120);
    expect(c.read(nearbyControllerProvider).permissionDenied, isTrue);
    backend.emit(_peer('s1', _a, 'A'));
    await settle();
    final s = c.read(nearbyControllerProvider);
    expect(s.permissionDenied, isFalse);
    expect(s.permission, LocalNetworkStatus.granted);
  });

  test('iOS: no probe when a device is found in time', () async {
    final c = makeContainer();
    await open(c);
    backend.emit(_peer('s1', _a, 'A'));
    await settle(120);
    expect(localNetwork.probes, 0);
    expect(c.read(nearbyControllerProvider).searchedLong, isFalse);
  });

  test('Android: no probe, only the "nothing found" hint', () async {
    final c = makeContainer(ios: false);
    await open(c);
    await settle(120);
    final s = c.read(nearbyControllerProvider);
    expect(s.searchedLong, isTrue);
    expect(localNetwork.probes, 0);
    expect(s.permission, isNull);
  });

  test('refresh restarts browsing with an empty list', () async {
    final c = makeContainer();
    final controller = await open(c);
    backend.emit(_peer('s1', _a, 'A'));
    await settle();
    await controller.refresh();
    expect(backend.browseStarts, 2);
    expect(c.read(nearbyControllerProvider).peers, isEmpty);
    expect(c.read(nearbyControllerProvider).searchedLong, isFalse);
  });

  test('connectToPeer passes id, address and hint', () async {
    final c = makeContainer();
    final controller = await open(c);
    backend.emit(_peer('s1', _a, 'A'));
    await settle();
    final peer = c.read(nearbyControllerProvider).peers[_a]!;
    await controller.connectToPeer(peer);
    expect(checked.single.deviceId, _a);
    expect(checked.single.host, '192.168.1.10');
    expect(checked.single.port, 4000);
    expect(checked.single.fingerprintHint, '0123456789abcdef');
  });

  test('a device that does not answer is removed from the list', () async {
    check = (_) async => throw const UploadException('network', 'refused');
    final c = makeContainer();
    final controller = await open(c);
    backend.emit(_peer('s1', _a, 'A'));
    await settle();
    final peer = c.read(nearbyControllerProvider).peers[_a]!;
    await expectLater(
      controller.connectToPeer(peer),
      throwsA(isA<UploadException>()),
    );
    await settle();
    expect(c.read(nearbyControllerProvider).peers, isEmpty);
  });

  test('a version error keeps the device listed', () async {
    check = (_) async => throw const UploadException('version', 'old');
    final c = makeContainer();
    final controller = await open(c);
    backend.emit(_peer('s1', _a, 'A'));
    await settle();
    final peer = c.read(nearbyControllerProvider).peers[_a]!;
    await expectLater(
      controller.connectToPeer(peer),
      throwsA(isA<UploadException>()),
    );
    await settle();
    expect(c.read(nearbyControllerProvider).peers.keys, [_a]);
  });

  test('connectToQr carries the full fingerprint and id', () async {
    final c = makeContainer();
    final controller = await open(c);
    await controller.connectToQr(
      ConnectPayload(
        ip: '192.168.1.30',
        port: 5555,
        fingerprint: 'a' * 64,
        deviceId: _b,
        name: 'B',
      ),
    );
    expect(checked.single.fingerprint, 'a' * 64);
    expect(checked.single.deviceId, _b);
    expect(checked.single.host, '192.168.1.30');
  });

  test('connectToAddress has no expected id', () async {
    final c = makeContainer();
    final controller = await open(c);
    await controller.connectToAddress('10.0.0.2', 8443);
    expect(checked.single.deviceId, isNull);
    expect(checked.single.port, 8443);
  });

  test('closing the screen stops browsing', () async {
    final c = makeContainer();
    await open(c);
    c.dispose();
    await settle();
    expect(backend.isBrowsing, isFalse);
  });
}
