import 'dart:io';

import 'package:crossdrop/app/providers.dart';
import 'package:crossdrop/core/cable/cable_link.dart';
import 'package:crossdrop/core/storage/database.dart';
import 'package:crossdrop/features/cable/cable_controllers.dart';
import 'package:crossdrop/features/receive/receive_controller.dart';
import 'package:crossdrop/features/receive/receive_host.dart';
import 'package:crossdrop/features/usb_import/usb_import_controller.dart';
import 'package:crossdrop/platform/usb_camera.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_cable_bridge.dart';
import '../../support/fake_usb_camera.dart';

/// The receive state a test sets.
class _Receive extends Notifier<ReceiveState> {
  @override
  ReceiveState build() =>
      const ReceiveState(port: 5000, dataPorts: [5001, 5002]);

  void set(ReceiveState s) => state = s;
}

final _receive = NotifierProvider<_Receive, ReceiveState>(_Receive.new);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Android bridge', () {
    late FakeUsbCamera camera;
    late AppDatabase db;
    late ProviderContainer c;
    late String deviceId;
    late String name;

    setUp(() async {
      camera = FakeUsbCamera();
      db = AppDatabase(NativeDatabase.memory());
      c = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          usbCameraProvider.overrideWithValue(camera),
          cableReceiveAvailableProvider.overrideWithValue(true),
          receiveStateProvider.overrideWith((ref) => ref.watch(_receive)),
        ],
      );
      final me = await c.read(identityProvider.future);
      deviceId = me.deviceId;
      name = me.deviceName;
      c.listen(cableReceiveProvider, (_, _) {});
      await _settle();
    });

    tearDown(() async {
      c.dispose();
      await db.close();
    });

    test('starts with the receive and data ports while plugged in', () {
      final call = camera.cableCalls.single!;
      expect(call.port, 5000);
      expect(call.ports, [5000, 5001, 5002]);
      expect((call.deviceId, call.name), (deviceId, name));
    });

    test('new ports update it; the same state does not restart it', () async {
      c.read(_receive.notifier).set(const ReceiveState(port: 6000));
      await _settle();
      c.read(_receive.notifier).set(const ReceiveState(port: 6000));
      await _settle();
      expect(camera.cableCalls, hasLength(2));
      expect(camera.cableCalls.last!.ports, [6000]);
    });

    test('Receiving off or the server stopped: it stops', () async {
      c
          .read(_receive.notifier)
          .set(const ReceiveState(port: 5000, receivingOff: true));
      await _settle();
      expect(camera.cableCalls.last, isNull);
      c.read(_receive.notifier).set(const ReceiveState(port: 5000));
      await _settle();
      expect(camera.cableCalls.last, isNotNull);
      c.read(_receive.notifier).set(const ReceiveState());
      await _settle();
      expect(camera.cableCalls.last, isNull);
    });

    test('unplugged: it stops; plugged in again: it starts', () async {
      camera.unplug(FakeUsbCamera.iphone.id);
      await _settle();
      expect(camera.cableCalls.last, isNull);
      expect(c.read(cableReceiveProvider), isNull);
      camera.plug(FakeUsbCamera.iphone);
      await _settle();
      expect(camera.cableCalls.last, isNotNull);
    });

    test('bridge states show; a refused start is not asked again', () async {
      camera.cableState('connected');
      await _settle();
      expect(c.read(cableReceiveProvider)?.connected, isTrue);

      camera.unplug(FakeUsbCamera.iphone.id);
      await _settle();
      camera.cableErrors.add(UsbCameraErrors.permissionDenied);
      camera.plug(FakeUsbCamera.iphone);
      await _settle();
      expect(c.read(cableReceiveProvider)?.code, 'permission_denied');
      final calls = camera.cableCalls.length;
      // The same state again (a receive update): no new prompt.
      c
          .read(_receive.notifier)
          .set(const ReceiveState(port: 5000, dataPorts: [5001, 5002]));
      await _settle();
      expect(camera.cableCalls.length, calls);
    });
  });

  group('iPhone link', () {
    test(
      'shows the phone on the cable while its bridge is connected',
      () async {
        late CableLink link;
        final c = ProviderContainer(
          overrides: [
            cableSendAvailableProvider.overrideWithValue(true),
            cableLinkFactoryProvider.overrideWithValue(
              () => link = CableLink(ports: const [0]),
            ),
          ],
        );
        addTearDown(c.dispose);
        final changes = <CablePeer?>[];
        c.listen(cablePeerProvider, (_, next) => changes.add(next));
        await _settle();
        final bridge = await FakeCableBridge.connect(
          link.port!,
          receivePort: 7000,
        );
        await _settle();
        expect(c.read(cablePeerProvider)?.port, 7000);
        bridge.unplug();
        await _settle();
        expect(c.read(cablePeerProvider), isNull);
        expect(changes.map((p) => p?.name), ['Pixel', null]);
      },
    );

    test('off on Android', () {
      final c = ProviderContainer(
        overrides: [cableSendAvailableProvider.overrideWithValue(false)],
      );
      addTearDown(c.dispose);
      expect(c.read(cablePeerProvider), isNull);
    });
  });

  test('loopback only: the link is not reachable from the network', () async {
    final link = CableLink(ports: const [0]);
    addTearDown(link.dispose);
    await link.start();
    final addresses = await NetworkInterface.list();
    for (final i in addresses) {
      for (final a in i.addresses.where(
        (a) => a.type == InternetAddressType.IPv4,
      )) {
        await expectLater(
          Socket.connect(a, link.port!, timeout: const Duration(seconds: 1)),
          throwsA(isA<SocketException>()),
          reason: a.address,
        );
      }
    }
  });
}
