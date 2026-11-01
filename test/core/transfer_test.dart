// End-to-end tests: UploadClient sends to ReceiveServer in the same process,
// over real HTTPS on loopback. No phones needed.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crossdrop/core/client/upload_client.dart';
import 'package:crossdrop/core/engine/chunked_reader.dart';
import 'package:crossdrop/core/security/ephemeral_identity.dart';
import 'package:crossdrop/core/server/receive_server.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const int mb = 1024 * 1024;
const int fileSize = 50 * mb;

/// Peak RSS growth allowed during a 50 MB transfer. Loading the file into
/// memory on either side would add at least 50 MB.
const int maxRssGrowth = 40 * mb;

void main() {
  late EphemeralIdentity identity;
  late Directory root;
  late String sourcePath;
  late String sourceSha;
  late ReceiveServer server;
  late List<ReceiveEvent> events;
  late StreamSubscription<ReceiveEvent> eventSub;

  setUpAll(() async {
    identity = await EphemeralIdentity.generate();
    root = Directory.systemTemp.createTempSync('cd_transfer');
    sourcePath = p.join(root.path, 'source.bin');
    sourceSha = await _writeRandomFile(sourcePath, fileSize);
  });

  tearDownAll(() => root.deleteSync(recursive: true));

  setUp(() async {
    final run = root.createTempSync('run');
    server = await ReceiveServer.start(
      securityContext: identity.serverContext(),
      tempDir: p.join(run.path, 'tmp'),
      saveDir: p.join(run.path, 'save'),
      address: InternetAddress.loopbackIPv4,
    );
    events = [];
    eventSub = server.events.listen(events.add);
  });

  tearDown(() async {
    await eventSub.cancel();
    await server.close();
  });

  UploadClient newClient() =>
      UploadClient(host: '127.0.0.1', port: server.port);

  String savedPath() => events.whereType<FileSaved>().single.savedPath;

  test('sends a 50 MB file and the hashes match', () async {
    final client = newClient();
    addTearDown(client.close);
    final progress = <TransferProgress>[];

    final target = await client.offerFile(sourcePath, name: 'video.mp4');
    final sha = await client.transfer(target, onProgress: progress.add);

    expect(sha, sourceSha);
    expect(await _hashFile(savedPath()), sourceSha);
    expect(p.basename(savedPath()), 'video.mp4');
    expect(progress.last.sentBytes, fileSize);
    expect(progress.last.fraction, 1);
    expect(progress.last.bytesPerSecond, greaterThan(0));
    final status = await client.fileStatus(target);
    expect(status.status, 'saved');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('memory stays flat while sending 50 MB', () async {
    final client = newClient();
    addTearDown(client.close);

    // Warm up code paths and isolates so they don't count as growth.
    final warm = p.join(root.path, 'warm.bin');
    await _writeRandomFile(warm, 2 * mb);
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
    expect(events.whereType<FileSaved>(), isEmpty);

    // A new client (as after a reconnect) asks where to continue.
    final second = newClient();
    addTearDown(second.close);
    // Wait until the receiver has noticed the drop and flushed: poll
    // until receivedBytes stops changing.
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
    expect(await _hashFile(savedPath()), sourceSha);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// Writes [size] pseudo-random bytes in 1 MB chunks and returns the SHA-256.
Future<String> _writeRandomFile(String path, int size) async {
  final sink = File(path).openWrite();
  final out = _DigestSink();
  final hash = sha256.startChunkedConversion(out);
  final rnd = Random(42);
  for (var written = 0; written < size; written += mb) {
    final n = min(mb, size - written);
    final chunk = Uint8List(n);
    for (var i = 0; i < n; i += 4) {
      final v = rnd.nextInt(1 << 32);
      for (var j = 0; j < 4 && i + j < n; j++) {
        chunk[i + j] = (v >> (8 * j)) & 0xff;
      }
    }
    sink.add(chunk);
    hash.add(chunk);
  }
  await sink.close();
  hash.close();
  return out.value.toString();
}

Future<String> _hashFile(String path) async {
  final out = _DigestSink();
  final hash = sha256.startChunkedConversion(out);
  await for (final chunk in readFileChunks(path)) {
    hash.add(chunk);
  }
  hash.close();
  return out.value.toString();
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
