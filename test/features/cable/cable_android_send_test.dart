// D-074 end to end: the Android sends to the iPhone over the cable. A real
// SendSession dials through the bridge controller's dialer; the fake cable
// plays Kotlin's dialOut on loopback; a real ReceiveServer plays the
// iPhone. Same protocol, lanes, workers and hashes as Wi-Fi.
import 'dart:io';

import 'package:crossdrop/app/providers.dart';
import 'package:crossdrop/core/cable/cable_link.dart';
import 'package:crossdrop/core/cable/cable_route.dart';
import 'package:crossdrop/core/engine/backoff.dart';
import 'package:crossdrop/core/engine/send_session.dart';
import 'package:crossdrop/core/security/device_credentials.dart';
import 'package:crossdrop/core/storage/database.dart';
import 'package:crossdrop/features/cable/cable_controllers.dart';
import 'package:crossdrop/features/receive/receive_controller.dart';
import 'package:crossdrop/features/receive/receive_host.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/fake_usb_cable.dart';
import '../../support/test_receiver.dart';

// No TestWidgetsFlutterBinding: it mocks HttpClient (every answer 400).
void main() {
  test(
    'many photos and two large videos reach the iPhone byte for byte',
    () async {
      final identity = await DeviceCredentials.generate();
      final me = await testSenderCredentials();
      final src = Directory.systemTemp.createTempSync('cd_cable_android');
      addTearDown(() => src.deleteSync(recursive: true));
      final iphone = await TestReceiver.start(
        identity: identity,
        bodyIdleTimeout: const Duration(seconds: 2),
        dataLanes: 3,
      );
      addTearDown(iphone.close);

      final cable = FakeUsbCable()
        ..reachable = {iphone.port, ...iphone.server.dataPorts};
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final c = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          usbCableProvider.overrideWithValue(cable),
          cableBridgeAvailableProvider.overrideWithValue(true),
          receiveStateProvider.overrideWithValue(const ReceiveState()),
        ],
      );
      addTearDown(c.dispose);
      c.listen(cableBridgeProvider, (_, _) {});
      await c.read(identityProvider.future);
      cable.cableState(
        'connected',
        null,
        CablePeer(port: iphone.port, deviceId: 'ios-1', name: 'iPhone'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(cableDialer, isNotNull);

      final items = <SendItem>[];
      final shas = <String, String>{};
      Future<void> add(String name, int size, int seed) async {
        final path = p.join(src.path, name);
        shas[name] = await writeRandomFile(path, size, seed: seed);
        items.add(SendItem(path: path, name: name, size: size));
      }

      for (var i = 0; i < 80; i++) {
        await add('photo$i.jpg', 250 * 1024 + i, i);
      }
      await add('video0.mp4', 40 * mb, 100);
      await add('video1.mp4', 36 * mb + 7, 101);

      final result = await SendSession(
        host: cableHost,
        port: iphone.port,
        sender: testSender,
        items: items,
        receiverFingerprint: identity.fingerprint,
        credentials: me,
        expectedDeviceId: testDeviceInfo.id,
        backoff: () => Backoff(
          steps: const [Duration(milliseconds: 50)],
          giveUpAfter: const Duration(seconds: 30),
        ),
        pollInterval: const Duration(milliseconds: 50),
      ).run();
      expect(result.phase, SendPhase.done, reason: result.reason);

      expect(iphone.saved, hasLength(items.length));
      final sizes = {for (final i in items) i.name: i.size};
      for (final saved in iphone.saved) {
        final name = p.basename(saved.savedPath);
        expect(await hashFile(saved.savedPath), shas[name], reason: name);
        expect(File(saved.savedPath).lengthSync(), sizes[name], reason: name);
      }
      // Lanes and workers dialed the iPhone's data ports too.
      expect(
        cable.dials.map((d) => d.$2).toSet(),
        containsAll(iphone.server.dataPorts),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
