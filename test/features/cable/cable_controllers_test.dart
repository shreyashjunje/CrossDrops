import 'dart:io';

import 'package:crossdrop/app/providers.dart';
import 'package:crossdrop/core/cable/cable_link.dart';
import 'package:crossdrop/core/cable/cable_route.dart';
import 'package:crossdrop/core/storage/database.dart';
import 'package:crossdrop/features/cable/cable_controllers.dart';
import 'package:crossdrop/features/receive/receive_controller.dart';
import 'package:crossdrop/features/receive/receive_host.dart';
import 'package:crossdrop/platform/usb_cable.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_cable_bridge.dart';
import '../../support/fake_usb_cable.dart';

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
    late FakeUsbCable camera;
    late AppDatabase db;
    late ProviderContainer c;
    late String deviceId;
    late String name;

    setUp(() async {
      camera = FakeUsbCable();
      db = AppDatabase(NativeDatabase.memory());
      c = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          usbCableProvider.overrideWithValue(camera),
          cableBridgeAvailableProvider.overrideWithValue(true),
          receiveStateProvider.overrideWith((ref) => ref.watch(_receive)),
        ],
      );
      final me = await c.read(identityProvider.future);
      deviceId = me.deviceId;
      name = me.deviceName;
      c.listen(cableBridgeProvider, (_, _) {});
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

    test(
      'Receiving off: it keeps running for sending, with no ports',
      () async {
        c
            .read(_receive.notifier)
            .set(const ReceiveState(port: 5000, receivingOff: true));
        await _settle();
        final off = camera.cableCalls.last!;
        expect(off.port, isNull);
        expect(off.ports, isEmpty);
        c.read(_receive.notifier).set(const ReceiveState(port: 5000));
        await _settle();
        expect(camera.cableCalls.last!.port, 5000);
        // Server stopped: still running, nothing to dial here.
        c.read(_receive.notifier).set(const ReceiveState());
        await _settle();
        expect(camera.cableCalls.last!.ports, isEmpty);
      },
    );

    test('the iPhone receives: this phone dials it; then it stops', () async {
      final echo = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(echo.close);
      echo.listen((s) => s.cast<List<int>>().pipe(s).catchError((_) {}));
      camera.reachable = {echo.port};
      const iphone = CablePeer(port: 1, deviceId: 'ios-1', name: 'iPhone');
      camera.cableState('connected', null, iphone);
      await _settle();
      expect(c.read(cablePeerProvider), iphone);
      final s = await dialCable(echo.port, const Duration(seconds: 5));
      s.write('hi');
      expect(String.fromCharCodes(await s.first), 'hi');
      s.destroy();
      expect(camera.dials.single.$2, echo.port);
      // A refused port fails at once.
      await expectLater(
        dialCable(2, const Duration(seconds: 5)),
        throwsA(isA<SocketException>()),
      );
      // The iPhone stops receiving: nothing to dial.
      camera.cableState(
        'connected',
        null,
        const CablePeer(port: null, deviceId: 'ios-1', name: 'iPhone'),
      );
      await _settle();
      expect(cableDialer, isNull);
      camera.cableState('connected', null, iphone);
      await _settle();
      expect(cableDialer, isNotNull);
      camera.unplug(FakeUsbCable.iphone.id);
      camera.cableState('stopped', 'unplugged');
      await _settle();
      expect(cableDialer, isNull);
    });

    test('unplugged: it stops; plugged in again: it starts', () async {
      camera.unplug(FakeUsbCable.iphone.id);
      await _settle();
      expect(camera.cableCalls.last, isNull);
      expect(c.read(cableBridgeProvider), isNull);
      camera.plug(FakeUsbCable.iphone);
      await _settle();
      expect(camera.cableCalls.last, isNotNull);
    });

    test('bridge states show; a refused start is not asked again', () async {
      camera.cableState('connected');
      await _settle();
      expect(c.read(cableBridgeProvider)?.connected, isTrue);

      camera.unplug(FakeUsbCable.iphone.id);
      await _settle();
      camera.cableErrors.add(UsbCableErrors.permissionDenied);
      camera.plug(FakeUsbCable.iphone);
      await _settle();
      expect(c.read(cableBridgeProvider)?.code, 'permission_denied');
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
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final c = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            receiveStateProvider.overrideWith((ref) => ref.watch(_receive)),
            cableLinkAvailableProvider.overrideWithValue(true),
            cableLinkFactoryProvider.overrideWithValue(
              () => link = CableLink(ports: const [0]),
            ),
          ],
        );
        addTearDown(c.dispose);
        final me = await c.read(identityProvider.future);
        final changes = <CablePeer?>[];
        c.listen(cablePeerProvider, (_, next) => changes.add(next));
        await _settle();
        final bridge = await FakeCableBridge.connect(
          link.port!,
          receivePort: 7000,
        );
        await _settle();
        expect(c.read(cablePeerProvider)?.port, 7000);
        // The iPhone answered with its own hello: it receives on 5000.
        expect(bridge.hellos.single.port, 5000);
        expect(bridge.hellos.single.deviceId, me.deviceId);
        // Receiving turned off: a new hello without a port.
        c
            .read(_receive.notifier)
            .set(const ReceiveState(port: 5000, receivingOff: true));
        await _settle();
        expect(bridge.hellos.last.port, isNull);
        bridge.unplug();
        await _settle();
        expect(c.read(cablePeerProvider), isNull);
        expect(changes.map((p) => p?.name), ['Pixel', null]);
      },
    );

    test('off on Android', () {
      final c = ProviderContainer(
        overrides: [cableLinkAvailableProvider.overrideWithValue(false)],
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
