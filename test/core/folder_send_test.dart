// D-075 end to end: a whole folder through SendSession to ReceiveServer on
// loopback. The receiver rebuilds the folder under its save folder, keeps
// it across a restart, and nothing can climb out of it.
import 'dart:io';

import 'package:crossdrop/core/engine/backoff.dart';
import 'package:crossdrop/core/engine/send_session.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/device_credentials.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/test_receiver.dart';

void main() {
  late DeviceCredentials identity;
  late DeviceCredentials me;
  late Directory src;
  late TestReceiver r;
  var count = 0;

  setUpAll(() async {
    identity = await DeviceCredentials.generate();
    me = await testSenderCredentials();
  });

  setUp(() async {
    src = Directory.systemTemp.createTempSync('cd_folder');
    r = await TestReceiver.start(identity: identity);
  });

  tearDown(() async {
    await r.close();
    src.deleteSync(recursive: true);
  });

  Future<(SendItem, String)> file(
    String name,
    int size, {
    String? folder,
    String kind = FileKind.file,
  }) async {
    final n = count++;
    final path = p.join(src.path, '$n-$name');
    final sha = await writeRandomFile(path, size, seed: n);
    return (
      SendItem(path: path, name: name, size: size, kind: kind, folder: folder),
      sha,
    );
  }

  SendSession session(List<SendItem> items) => SendSession(
    host: '127.0.0.1',
    port: r.port,
    sender: testSender,
    items: items,
    receiverFingerprint: identity.fingerprint,
    credentials: me,
    expectedDeviceId: testDeviceInfo.id,
    backoff: () => Backoff(
      steps: const [Duration(milliseconds: 50)],
      giveUpAfter: const Duration(seconds: 10),
    ),
    pollInterval: const Duration(milliseconds: 50),
  );

  test('the folder arrives as a folder, byte for byte', () async {
    final files = [
      await file('a.jpg', 3000, folder: 'Trip', kind: FileKind.photo),
      await file('b.mp4', 5000, folder: 'Trip/Day 1', kind: FileKind.video),
      await file('a.jpg', 4000, folder: 'Trip/Day 1', kind: FileKind.photo),
      await file('notes.txt', 10, folder: 'Trip/Day 1/Notes'),
    ];
    final result = await session([for (final f in files) f.$1]).run();
    expect(result.phase, SendPhase.done, reason: result.reason);

    final expected = {
      p.join(r.saveDir, 'Trip', 'a.jpg'): files[0].$2,
      p.join(r.saveDir, 'Trip', 'Day 1', 'b.mp4'): files[1].$2,
      p.join(r.saveDir, 'Trip', 'Day 1', 'a.jpg'): files[2].$2,
      p.join(r.saveDir, 'Trip', 'Day 1', 'Notes', 'notes.txt'): files[3].$2,
    };
    expect(r.saved.map((s) => s.savedPath).toSet(), expected.keys.toSet());
    for (final MapEntry(:key, :value) in expected.entries) {
      expect(await hashFile(key), value, reason: key);
    }
  });

  test('a folder path cannot leave the save folder', () async {
    final (item, sha) = await file('x.bin', 100, folder: '../../../etc/..');
    final result = await session([item]).run();
    expect(result.phase, SendPhase.done, reason: result.reason);
    final saved = r.saved.single.savedPath;
    expect(p.isWithin(r.saveDir, saved), isTrue, reason: saved);
    expect(saved, p.join(r.saveDir, 'etc', 'x.bin'));
    expect(await hashFile(saved), sha);
  });

  test('the receiver keeps the folder across a restart', () async {
    final (item, sha) = await file('big.bin', 6 * mb, folder: 'Backup/2026');
    final s = session([item]);
    var restarted = false;
    final sub = s.updates.listen((u) async {
      if (!restarted && u.sentBytes > mb) {
        restarted = true;
        await r.restart();
      }
    });
    final result = await s.run();
    await sub.cancel();
    expect(restarted, isTrue);
    expect(result.phase, SendPhase.done, reason: result.reason);
    final saved = r.saved.single.savedPath;
    expect(saved, p.join(r.saveDir, 'Backup', '2026', 'big.bin'));
    expect(await hashFile(saved), sha);
  });
}
