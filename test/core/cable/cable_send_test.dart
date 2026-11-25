// D-073 end to end: SendSession → ReceiveServer through the iPhone's cable
// link and a fake Android bridge on loopback. Same protocol, lanes, workers
// and hashes as Wi-Fi; only the sockets come through the cable dialer.
import 'dart:async';
import 'dart:io';

import 'package:crossdrop/core/cable/cable_link.dart';
import 'package:crossdrop/core/cable/cable_route.dart';
import 'package:crossdrop/core/engine/backoff.dart';
import 'package:crossdrop/core/engine/send_session.dart';
import 'package:crossdrop/core/security/device_credentials.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/fake_cable_bridge.dart';
import '../../support/test_receiver.dart';

void main() {
  late DeviceCredentials identity;
  late DeviceCredentials me;
  late Directory src;
  late TestReceiver r;
  late CableLink link;

  setUpAll(() async {
    identity = await DeviceCredentials.generate();
    me = await testSenderCredentials();
  });

  setUp(() async {
    src = Directory.systemTemp.createTempSync('cd_cable');
    r = await TestReceiver.start(
      identity: identity,
      bodyIdleTimeout: const Duration(seconds: 2),
      dataLanes: 3,
    );
    link = CableLink(ports: const [0]);
    expect(await link.start(), isTrue);
  });

  tearDown(() async {
    await link.dispose();
    await r.close();
    src.deleteSync(recursive: true);
  });

  Future<FakeCableBridge> plugIn() async {
    final connected = link.changes.firstWhere((p) => p != null);
    final bridge = await FakeCableBridge.connect(
      link.port!,
      receivePort: r.port,
      allowedPorts: {r.port, ...r.server.dataPorts},
    );
    await connected.timeout(const Duration(seconds: 5));
    return bridge;
  }

  SendSession session(List<SendItem> items, {PeerLocator? locate}) =>
      SendSession(
        host: cableHost,
        port: r.port,
        sender: testSender,
        items: items,
        locate: locate,
        receiverFingerprint: identity.fingerprint,
        credentials: me,
        expectedDeviceId: testDeviceInfo.id,
        backoff: () => Backoff(
          steps: const [
            Duration(milliseconds: 50),
            Duration(milliseconds: 200),
          ],
          giveUpAfter: const Duration(seconds: 30),
        ),
        pollInterval: const Duration(milliseconds: 50),
      );

  Future<Map<String, String>> makeFiles(
    List<SendItem> items,
    String prefix,
    int count,
    int size,
  ) async {
    final shas = <String, String>{};
    for (var i = 0; i < count; i++) {
      final name = '$prefix$i.bin';
      final path = p.join(src.path, name);
      shas[name] = await writeRandomFile(path, size + i, seed: i + size);
      items.add(SendItem(path: path, name: name, size: size + i));
    }
    return shas;
  }

  Future<void> expectSaved(
    Map<String, String> shas,
    List<SendItem> items,
  ) async {
    expect(r.saved, hasLength(shas.length));
    final sizes = {for (final i in items) i.name: i.size};
    for (final saved in r.saved) {
      final name = p.basename(saved.savedPath);
      expect(await hashFile(saved.savedPath), shas[name], reason: name);
      expect(File(saved.savedPath).lengthSync(), sizes[name], reason: name);
    }
  }

  test(
    'many photos and two large videos arrive byte for byte over the cable',
    () async {
      final bridge = await plugIn();
      addTearDown(bridge.unplug);
      final items = <SendItem>[];
      final shas = {
        ...await makeFiles(items, 'photo', 120, 300 * 1024),
        ...await makeFiles(items, 'video', 2, 40 * mb),
      };
      final watch = Stopwatch()..start();
      final result = await session(items).run();
      expect(result.phase, SendPhase.done, reason: result.reason);
      await expectSaved(shas, items);
      // Lanes and workers used the cable too: data ports were dialed.
      expect(
        bridge.dials.map((d) => d.port).toSet(),
        containsAll(r.server.dataPorts),
      );
      // ignore: avoid_print
      print(
        'cable, 122 files ${(36 + 80)} MB: ${watch.elapsedMilliseconds} ms',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'unplugged in the middle, plugged in again: it resumes and finishes',
    () async {
      var bridge = await plugIn();
      final items = <SendItem>[];
      final shas = {
        ...await makeFiles(items, 'video', 1, 48 * mb),
        ...await makeFiles(items, 'photo', 20, 200 * 1024),
      };
      final s = session(items);
      var unplugged = false;
      final sub = s.updates.listen((u) {
        if (!unplugged &&
            u.phase == SendPhase.sending &&
            u.sentBytes > 8 * mb) {
          unplugged = true;
          bridge.unplug();
          Timer(const Duration(milliseconds: 500), () async {
            bridge = await plugIn();
          });
        }
      });
      final result = await s.run();
      await sub.cancel();
      bridge.unplug();
      expect(unplugged, isTrue);
      expect(result.phase, SendPhase.done, reason: result.reason);
      await expectSaved(shas, items);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'unplugged for good: it finds the receiver on Wi-Fi and finishes there',
    () async {
      final bridge = await plugIn();
      final items = <SendItem>[];
      final shas = {
        ...await makeFiles(items, 'video', 1, 48 * mb),
        ...await makeFiles(items, 'photo', 20, 200 * 1024),
      };
      var plugged = true;
      // Like SendController._locator: the cable while plugged, else
      // discovery (here the receiver's loopback address stands in for Wi-Fi).
      final s = session(
        items,
        locate: () async => plugged
            ? (host: cableHost, port: r.port)
            : (host: '127.0.0.1', port: r.port),
      );
      var dialsAtUnplug = -1;
      final sub = s.updates.listen((u) {
        if (plugged && u.phase == SendPhase.sending && u.sentBytes > 8 * mb) {
          plugged = false;
          dialsAtUnplug = bridge.dials.length;
          bridge.unplug();
        }
      });
      final result = await s.run();
      await sub.cancel();
      expect(dialsAtUnplug, greaterThan(0));
      expect(result.phase, SendPhase.done, reason: result.reason);
      await expectSaved(shas, items);
      // Nothing more went through the cable after it was pulled.
      expect(bridge.dials, hasLength(dialsAtUnplug));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
