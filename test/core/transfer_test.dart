// End-to-end tests: UploadClient sends to ReceiveServer in the same process,
// over real HTTPS on loopback. No phones needed.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crossdrop/core/client/upload_client.dart';
import 'package:crossdrop/core/security/device_credentials.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/test_receiver.dart';

const int fileSize = 50 * mb;

/// Peak RSS growth allowed during a 50 MB transfer. Loading the file into
/// memory on either side would add at least 50 MB.
const int maxRssGrowth = 40 * mb;

void main() {
  late DeviceCredentials identity;
  late DeviceCredentials me;
  late Directory root;
  late String sourcePath;
  late String sourceSha;
  late TestReceiver r;

  setUpAll(() async {
    identity = await DeviceCredentials.generate();
    me = await testSenderCredentials();
    root = Directory.systemTemp.createTempSync('cd_transfer');
    sourcePath = p.join(root.path, 'source.bin');
    sourceSha = await writeRandomFile(sourcePath, fileSize);
  });

  tearDownAll(() => root.deleteSync(recursive: true));

  setUp(() async => r = await TestReceiver.start(identity: identity));
  tearDown(() => r.close());

  UploadClient newClient() => clientFor(r, me);

  String savedPath() => r.saved.single.savedPath;

  test('sends a 50 MB file and the hashes match', () async {
    final client = newClient();
    addTearDown(client.close);
    final progress = <TransferProgress>[];

    final target = await client.offerFile(sourcePath, name: 'video.mp4');
    final sha = await client.transfer(target, onProgress: progress.add);

    expect(sha, sourceSha);
    expect(await hashFile(savedPath()), sourceSha);
    expect(p.basename(savedPath()), 'video.mp4');
    expect(progress.last.sentBytes, fileSize);
    expect(progress.last.fraction, 1);
    expect(progress.last.bytesPerSecond, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 2)));

  for (final kb in [256, 4096]) {
    test('a $kb KB buffer writes in $kb KB steps', () async {
      final client = clientFor(r, me, chunkSize: kb * 1024);
      addTearDown(client.close);
      final progress = <TransferProgress>[];
      final target = await client.offerFile(sourcePath);
      expect(
        await client.transfer(target, onProgress: progress.add),
        sourceSha,
      );
      expect(progress.first.sentBytes, kb * 1024);
      expect(progress.length, (fileSize / (kb * 1024)).ceil());
    }, timeout: const Timeout(Duration(minutes: 2)));
  }

  test('memory stays flat while sending 50 MB', () async {
    final client = newClient();
    addTearDown(client.close);

    // Warm up code paths and isolates so they don't count as growth.
    final warm = p.join(root.path, 'warm.bin');
    await writeRandomFile(warm, 2 * mb);
    await client.transfer(await client.offerFile(warm));

    final baseline = ProcessInfo.currentRss;
    var peak = baseline;
    final sampler = Timer.periodic(const Duration(milliseconds: 10), (_) {
      peak = max(peak, ProcessInfo.currentRss);
    });
    try {
      final target = await client.offerFile(sourcePath);
      await client.transfer(
        target,
        onProgress: (_) => peak = max(peak, ProcessInfo.currentRss),
      );
    } finally {
      sampler.cancel();
    }
    final growth = peak - baseline;
    // Printed so the number can be tracked, not only pass/fail.
    // ignore: avoid_print
    print('RSS growth during 50 MB transfer: ${growth ~/ mb} MB');
    expect(growth, lessThan(maxRssGrowth));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('resumes with offset=N after the transfer is killed halfway', () async {
    final first = newClient();
    final target = await first.offerFile(sourcePath);

    // Kill the upload once about half has been sent.
    final killed = first.transfer(
      target,
      onProgress: (pr) {
        if (pr.sentBytes >= fileSize ~/ 2) first.cancel();
      },
    );
    await expectLater(
      killed,
      throwsA(
        isA<UploadException>().having((e) => e.isCancelled, 'cancelled', true),
      ),
    );
    first.close();
    expect(r.saved, isEmpty);

    // A new client (as after a reconnect) asks where to continue.
    final second = newClient();
    addTearDown(second.close);
    var received = -1;
    for (var i = 0; i < 50; i++) {
      final now = (await second.fileStatus(target)).receivedBytes;
      if (now == received) break;
      received = now;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(received, greaterThan(0));
    expect(received, lessThan(fileSize));

    final resumed = <TransferProgress>[];
    final sha = await second.transfer(target, onProgress: resumed.add);

    // Only the missing bytes were sent: first chunk starts right after N.
    expect(resumed.first.sentBytes, greaterThan(received));
    expect(resumed.first.sentBytes - received, lessThanOrEqualTo(mb));
    expect(resumed.last.sentBytes, fileSize);
    expect(sha, sourceSha);
    expect(await hashFile(savedPath()), sourceSha);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
