// D-071 end to end: SendSession against a ReceiveServer with data lanes.
// Large files go through upload worker isolates, striped, and are checked
// by the tree hash. No phones needed.
import 'dart:async';
import 'dart:io';

import 'package:crossdrop/core/client/upload_client.dart';
import 'package:crossdrop/core/engine/backoff.dart';
import 'package:crossdrop/core/engine/send_session.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/device_credentials.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/flaky_proxy.dart';
import '../../support/test_receiver.dart';

/// Counts what went the fast way, and can show the session another info.
class _SpyClient extends UploadClient {
  _SpyClient({
    required super.host,
    required super.port,
    required super.fingerprint,
    required super.credentials,
    required this.spy,
  }) : super(
         connectTimeout: const Duration(seconds: 2),
         stallTimeout: const Duration(seconds: 2),
       );

  final _Spy spy;

  @override
  Future<DeviceInfo> info() async {
    final real = await super.info();
    return spy.info?.call(real) ?? real;
  }

  @override
  Future<FileStatus> putFast(
    UploadTarget t,
    int offset, {
    required List<int> dataPorts,
    int stripes = 1,
    int lane = 0,
    void Function(TransferProgress)? onProgress,
  }) {
    spy.fast.add((file: t.fileId, stripes: stripes, tree: t.treeHash));
    return super.putFast(
      t,
      offset,
      dataPorts: dataPorts,
      stripes: stripes,
      lane: lane,
      onProgress: onProgress,
    );
  }

  @override
  Future<FileStatus> put(
    UploadTarget t,
    int offset, {
    void Function(TransferProgress)? onProgress,
  }) {
    spy.plain.add(t.fileId);
    return super.put(t, offset, onProgress: onProgress);
  }
}

class _Spy {
  final List<({String file, int stripes, bool tree})> fast = [];
  final List<String> plain = [];
  DeviceInfo Function(DeviceInfo real)? info;
}

void main() {
  late DeviceCredentials identity;
  late DeviceCredentials me;
  late Directory src;
  late TestReceiver r;
  late _Spy spy;

  setUpAll(() async {
    identity = await DeviceCredentials.generate();
    me = await testSenderCredentials();
  });

  setUp(() async {
    src = Directory.systemTemp.createTempSync('cd_fast');
    spy = _Spy();
    r = await TestReceiver.start(
      identity: identity,
      bodyIdleTimeout: const Duration(seconds: 2),
      dataLanes: 3,
    );
  });

  tearDown(() async {
    await r.close();
    src.deleteSync(recursive: true);
  });

  SendSession session(List<SendItem> items) => SendSession(
    host: '127.0.0.1',
    port: r.port,
    sender: testSender,
    items: items,
    receiverFingerprint: identity.fingerprint,
    credentials: me,
    expectedDeviceId: testDeviceInfo.id,
    clientFactory: (host, port) => _SpyClient(
      host: host,
      port: port,
      fingerprint: identity.fingerprint,
      credentials: me,
      spy: spy,
    ),
    backoff: () => Backoff(
      steps: const [Duration(milliseconds: 20), Duration(milliseconds: 80)],
      giveUpAfter: const Duration(seconds: 30),
    ),
    pollInterval: const Duration(milliseconds: 50),
  );

  Future<(SendItem, String)> makeFile(String name, int size, int seed) async {
    final path = p.join(src.path, name);
    final sha = await writeRandomFile(path, size, seed: seed);
    return (SendItem(path: path, name: name, size: size), sha);
  }

  Future<void> expectSaved(Map<String, String> shaByName) async {
    expect(r.saved, hasLength(shaByName.length));
    for (final saved in r.saved) {
      final name = p.basename(saved.savedPath);
      expect(await hashFile(saved.savedPath), shaByName[name], reason: name);
    }
  }

  test('one large file: striped over the data ports, tree hash', () async {
    final (item, sha) = await makeFile('big.mov', 40 * mb + 12345, 1);
    final result = await session([item]).run();
    expect(result.phase, SendPhase.done, reason: result.reason);
    expect(spy.fast, [(file: 'f0', stripes: 3, tree: true)]);
    expect(spy.plain, isEmpty);
    await expectSaved({'big.mov': sha});
    expect(r.saved.single.size, item.size);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('large files side by side take one connection each', () async {
    final files = [
      for (var i = 0; i < 3; i++) await makeFile('v$i.mov', 9 * mb + i, i + 2),
    ];
    final small = await makeFile('s.jpg', 2 * mb, 9);
    final result = await session([for (final f in files) f.$1, small.$1]).run();
    expect(result.phase, SendPhase.done, reason: result.reason);
    expect(spy.fast.map((f) => f.file).toSet(), {'f0', 'f1', 'f2'});
    // Below UploadClient.fastMinBytes: the main port.
    expect(spy.plain, ['f3']);
    await expectSaved({
      for (final (item, sha) in files) item.name: sha,
      's.jpg': small.$2,
    });
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('pause and resume in the middle of a fast upload', () async {
    final (item, sha) = await makeFile('big.mov', 48 * mb, 3);
    final s = session([item]);
    var paused = false;
    final sub = s.updates.listen((u) async {
      if (!paused && u.phase == SendPhase.sending && u.sentBytes > 4 * mb) {
        paused = true;
        await s.pause();
        expect(s.snapshot.phase, SendPhase.paused);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        s.resume();
      }
    });
    final result = await s.run();
    await sub.cancel();
    expect(paused, isTrue);
    expect(result.phase, SendPhase.done, reason: result.reason);
    await expectSaved({'big.mov': sha});
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('cancel in the middle of a fast upload', () async {
    final (item, _) = await makeFile('big.mov', 48 * mb, 4);
    final s = session([item]);
    var cancelled = false;
    final sub = s.updates.listen((u) {
      if (!cancelled && u.phase == SendPhase.sending && u.sentBytes > 4 * mb) {
        cancelled = true;
        unawaited(s.cancel());
      }
    });
    final result = await s.run();
    await sub.cancel();
    expect(result.phase, SendPhase.cancelled);
    expect(r.saved, isEmpty);
    await waitFor(() => !r.server.isReceiving);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a drop on a data port: resumes and both sides agree', () async {
    final proxies = [
      for (final port in r.server.dataPorts) await FlakyProxy.start(port),
    ];
    addTearDown(() async {
      for (final proxy in proxies) {
        await proxy.close();
      }
    });
    spy.info = (real) =>
        real.withDataPlane(dataPorts: [for (final x in proxies) x.port]);
    proxies[1].dropAt(6 * mb);
    final (item, sha) = await makeFile('big.mov', 40 * mb, 5);
    final result = await session([item]).run();
    expect(result.phase, SendPhase.done, reason: result.reason);
    expect(proxies[1].drops, 1);
    expect(spy.fast.length, greaterThan(1));
    await expectSaved({'big.mov': sha});
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('data ports that do not answer: the main port takes over', () async {
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = dead.port;
    await dead.close();
    spy.info = (real) => real.withDataPlane(dataPorts: [port]);
    final (item, sha) = await makeFile('big.mov', 10 * mb, 6);
    final result = await session([item]).run();
    expect(result.phase, SendPhase.done, reason: result.reason);
    expect(spy.fast, hasLength(2));
    expect(spy.plain, ['f0']);
    await expectSaved({'big.mov': sha});
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('an older receiver: one connection, plain SHA-256', () async {
    spy.info = (real) => DeviceInfo(
      id: real.id,
      name: real.name,
      platform: real.platform,
      versions: real.versions,
    );
    final (item, sha) = await makeFile('big.mov', 10 * mb, 7);
    final result = await session([item]).run();
    expect(result.phase, SendPhase.done, reason: result.reason);
    expect(spy.fast, isEmpty);
    expect(spy.plain, ['f0']);
    await expectSaved({'big.mov': sha});
  }, timeout: const Timeout(Duration(minutes: 2)));
}
