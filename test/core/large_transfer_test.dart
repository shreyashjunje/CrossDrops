// A 2 GB transfer with a drop past the 1 GB mark, checking that memory stays
// flat on both sides. Needs about 4 GB of free disk space and a few
// minutes, so it is skipped by default:
//
//   flutter test --run-skipped --tags large
@Tags(['large'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crossdrop/core/client/upload_client.dart';
import 'package:crossdrop/core/engine/backoff.dart';
import 'package:crossdrop/core/engine/send_session.dart';
import 'package:crossdrop/core/security/ephemeral_identity.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/flaky_proxy.dart';
import '../support/test_receiver.dart';

const int size = 2 * 1024 * mb;

/// Both sides run in this process, so a full copy of the file in memory on
/// either side would show up as gigabytes.
const int maxRssGrowth = 200 * mb;

void main() {
  test(
    '2 GB with a drop at 1.2 GB: resumes, hashes match, memory flat',
    () async {
      final identity = await EphemeralIdentity.generate();
      final src = Directory.systemTemp.createTempSync('cd_large');
      addTearDown(() => src.deleteSync(recursive: true));
      final path = p.join(src.path, 'big.mov');
      final sha = await _writeLargeFile(path, size);

      final r = await TestReceiver.start(identity: identity);
      addTearDown(r.close);
      final proxy = await FlakyProxy.start(r.port);
      addTearDown(proxy.close);
      proxy.dropAt(1200 * mb);

      final s = SendSession(
        host: '127.0.0.1',
        port: proxy.port,
        sender: testSender,
        items: [SendItem(path: path, name: 'big.mov', size: size)],
        clientFactory: (h, port) => UploadClient(host: h, port: port),
        backoff: () => Backoff(
          steps: const [Duration(milliseconds: 100)],
          giveUpAfter: const Duration(minutes: 1),
        ),
      );

      final baseline = ProcessInfo.currentRss;
      var peak = baseline;
      final sampler = Timer.periodic(const Duration(milliseconds: 50), (_) {
        peak = max(peak, ProcessInfo.currentRss);
      });
      final watch = Stopwatch()..start();
      final result = await s.run();
      watch.stop();
      sampler.cancel();

      expect(result.phase, SendPhase.done, reason: result.reason);
      expect(proxy.drops, 1);
      expect(await hashFile(r.saved.single.savedPath), sha);
      final growth = peak - baseline;
      // ignore: avoid_print
      print(
        '2 GB: ${watch.elapsed.inSeconds} s, '
        '${(size / 1e6 / watch.elapsed.inMilliseconds * 1000).round()} MB/s, '
        'RSS growth ${growth ~/ mb} MB',
      );
      expect(growth, lessThan(maxRssGrowth));
    },
    tags: ['large'],
  );
}

/// Writes [length] bytes fast: one random 1 MB block, with each block's
/// index stamped into its first 8 bytes so no two blocks are alike.
Future<String> _writeLargeFile(String path, int length) async {
  final rnd = Random(9);
  final block = Uint8List.fromList(List.generate(mb, (_) => rnd.nextInt(256)));
  final out = DigestSink();
  final hash = sha256.startChunkedConversion(out);
  final sink = File(path).openWrite();
  for (var i = 0; i * mb < length; i++) {
    final n = min(mb, length - i * mb);
    final chunk = Uint8List.fromList(block.sublist(0, n));
    final stamp = ByteData.sublistView(chunk, 0, min(8, n));
    if (n >= 8) stamp.setUint64(0, i);
    sink.add(chunk);
    hash.add(chunk);
    if (i % 64 == 0) await sink.flush();
  }
  await sink.close();
  hash.close();
  return out.value.toString();
}
