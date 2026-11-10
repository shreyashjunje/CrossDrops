import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crossdrop/core/engine/chunked_reader.dart';
import 'package:crossdrop/core/engine/sha256_isolate.dart';
import 'package:crossdrop/core/engine/tree_hash.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The definition, written out: SHA-256 over the SHA-256 of each 1 MB.
String reference(Uint8List data) {
  final leaves = BytesBuilder();
  for (var at = 0; at < data.length; at += treeLeafBytes) {
    final end = min(at + treeLeafBytes, data.length);
    leaves.add(sha256.convert(Uint8List.sublistView(data, at, end)).bytes);
  }
  return sha256.convert(leaves.takeBytes()).toString();
}

Uint8List randomBytes(int n, {int seed = 3}) {
  final rnd = Random(seed);
  return Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('cd_tree'));
  tearDown(() => dir.deleteSync(recursive: true));

  const mb = treeLeafBytes;
  final sizes = [0, 1, mb - 1, mb, mb + 1, 3 * mb, 5 * mb + 4321];

  test('an empty file: SHA-256 of nothing', () async {
    final h = await TreeHasher.spawn();
    expect(await h.close(), sha256.convert(const []).toString());
  });

  test('add: any chunking and any number of workers give the root', () async {
    for (final size in sizes) {
      final data = randomBytes(size);
      for (final (workers, step) in [(1, 700001), (3, mb), (3, 65536 + 7)]) {
        final h = await TreeHasher.spawn(workers: workers);
        for (var at = 0; at < size; at += step) {
          await h.add(Uint8List.sublistView(data, at, min(at + step, size)));
        }
        expect(
          await h.close(),
          reference(data),
          reason: '$size bytes, $workers workers, chunks of $step',
        );
      }
    }
  });

  test('addSourcePrefix: the workers read the file themselves', () async {
    for (final size in sizes) {
      final data = randomBytes(size, seed: 4);
      final path = p.join(dir.path, 'f$size');
      File(path).writeAsBytesSync(data);
      for (final workers in [1, 3]) {
        final h = await TreeHasher.spawn(workers: workers);
        await h.addSourcePrefix(PathSource(path), size);
        expect(await h.close(), reference(data), reason: '$size, $workers');
        await h.exited;
      }
      File(path).deleteSync(); // fails on Windows if a worker kept it open
    }
  });

  test('one changed bit anywhere changes the root', () async {
    final data = randomBytes(3 * mb + 10);
    final good = reference(data);
    for (final at in [0, mb, 3 * mb + 9]) {
      final bad = Uint8List.fromList(data)..[at] ^= 1;
      final h = await TreeHasher.spawn(workers: 3);
      await h.add(bad);
      expect(await h.close(), isNot(good));
    }
  });

  test('a file shorter than said fails the hash', () async {
    final path = p.join(dir.path, 'short');
    File(path).writeAsBytesSync(randomBytes(mb + 5));
    final h = await TreeHasher.spawn(workers: 3);
    await h.addSourcePrefix(PathSource(path), 3 * mb);
    await expectLater(h.close(), throwsA(isA<StateError>()));
    await h.exited;
  });

  test('abort: later adds are ignored and the workers leave', () async {
    final h = await TreeHasher.spawn(workers: 3);
    await h.add(randomBytes(2 * mb));
    h.abort();
    await h.add(randomBytes(mb));
    expect(h.close, throwsA(isA<StateError>()));
    await h.exited.timeout(const Duration(seconds: 5));
  });

  test('BackgroundFileHash with tree: the same root, file released', () async {
    final data = randomBytes(40 * mb, seed: 5);
    final path = p.join(dir.path, 'big');
    File(path).writeAsBytesSync(data);
    final h = BackgroundFileHash.startSource(
      PathSource(path),
      data.length,
      tree: true,
    );
    expect(await h.digest, reference(data));
    await h.abort();
    File(path).deleteSync();
  });

  test('more than one worker only from 32 MB', () {
    expect(TreeHasher.workersFor(treeParallelMinBytes - 1), 1);
    expect(TreeHasher.workersFor(treeParallelMinBytes), 3);
  });
}
