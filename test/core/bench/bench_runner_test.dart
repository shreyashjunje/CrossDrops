// The benchmark runner against a real ReceiveServer on loopback, with the
// discarding store of benchmark builds. No phones needed.
import 'dart:io';

import 'package:crossdrop/core/bench/bench.dart';
import 'package:crossdrop/core/bench/bench_runner.dart';
import 'package:crossdrop/core/bench/bench_stats.dart';
import 'package:crossdrop/core/bench/bench_store.dart';
import 'package:crossdrop/core/engine/send_session.dart';
import 'package:crossdrop/core/security/device_credentials.dart';
import 'package:crossdrop/core/server/file_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/test_receiver.dart';

void main() {
  late DeviceCredentials identity;
  late DeviceCredentials me;
  late Directory src;
  late TestReceiver r;

  setUpAll(() async {
    identity = await DeviceCredentials.generate();
    me = await testSenderCredentials();
  });

  setUp(() async {
    src = Directory.systemTemp.createTempSync('cd_bench_src');
    r = await TestReceiver.start(
      identity: identity,
      store: (r) => BenchDiscardingStore(FolderStore(r.saveDir)),
    );
  });

  tearDown(() async {
    await r.close();
    src.deleteSync(recursive: true);
  });

  BenchRunner runner() => BenchRunner(
    direction: 'PC → PC',
    network: 'loopback',
    pause: Duration.zero,
    fileFor: (size) => ensureBenchFile(src.path, size),
    newSession:
        ({
          required String path,
          required String name,
          required int size,
          required int chunkSize,
        }) => SendSession(
          host: '127.0.0.1',
          port: r.port,
          sender: testSender,
          items: [SendItem(path: path, name: name, size: size)],
          receiverFingerprint: identity.fingerprint,
          credentials: me,
          chunkSize: chunkSize,
        ),
  );

  test('runs every case; files are verified, then discarded', () async {
    final cases = planCases(
      sizes: [2 * 1024 * 1024, 5 * 1024 * 1024],
      buffers: [256 * 1024, 1024 * 1024],
      repeats: 2,
    );
    expect(cases, hasLength(8));
    // Buffers alternate within a repeat.
    expect(cases.take(2).map((c) => c.bufferBytes), [256 * 1024, 1024 * 1024]);

    final results = await runner().run(cases).toList();
    expect(results, hasLength(8));
    for (final res in results) {
      expect(res.ok, isTrue, reason: '${res.reason}');
      expect(res.avgMBps, greaterThan(0));
      expect(res.seconds, greaterThan(0));
      expect(res.role, BenchRole.sender);
    }
    // Verified and "saved" eight times, but nothing left on disk.
    expect(r.saved, hasLength(8));
    expect(r.saved.map((s) => s.savedPath).toSet(), {
      BenchDiscardingStore.discarded,
    });
    final left = Directory(r.saveDir).existsSync()
        ? Directory(r.saveDir).listSync()
        : const <FileSystemEntity>[];
    expect(left, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a refused offer is a failed result, and the series goes on', () async {
    r.decider = (_) async => false;
    final results = await runner()
        .run(
          planCases(sizes: [1024 * 1024], buffers: [1024 * 1024], repeats: 2),
        )
        .toList();
    expect(results.map((x) => x.ok), [false, false]);
    expect(results.first.reason, isNotEmpty);
  });

  test('the discarding store keeps every other file', () async {
    final res = await runner().runOne(
      const BenchCase(1024 * 1024, 1024 * 1024, 1),
    );
    expect(res.ok, isTrue);
    final normal = p.join(src.path, 'photo.jpg');
    File(normal).writeAsBytesSync(List.filled(1000, 7));
    final client = clientFor(r, me);
    addTearDown(client.close);
    final target = await client.offerFile(normal, name: 'photo.jpg');
    await client.transfer(target);
    expect(File(p.join(r.saveDir, 'photo.jpg')).existsSync(), isTrue);
  });
}
