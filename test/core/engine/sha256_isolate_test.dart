import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crossdrop/core/engine/chunked_reader.dart';
import 'package:crossdrop/core/engine/sha256_isolate.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late String path;
  late Uint8List data;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cd_hash');
    path = p.join(dir.path, 'data.bin');
    final rnd = Random(1);
    data = Uint8List.fromList(
      List.generate(3 * 1024 * 1024 + 123, (_) => rnd.nextInt(256)),
    );
    File(path).writeAsBytesSync(data);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('empty input gives the SHA-256 of nothing', () async {
    final h = await Sha256Isolate.spawn();
    expect(await h.close(), sha256.convert(const []).toString());
  });

  test('chunks give the same digest as one-shot hashing', () async {
    final h = await Sha256Isolate.spawn(maxInFlight: 2);
    await for (final c in readFileChunks(path, chunkSize: 300000)) {
      await h.add(c);
    }
    expect(await h.close(), sha256.convert(data).toString());
  });

  test('file prefix plus chunks matches the whole file (resume)', () async {
    const offset = 1500000;
    final h = await Sha256Isolate.spawn();
    await h.addFilePrefix(path, offset);
    await for (final c in readFileChunks(path, start: offset)) {
      await h.add(c);
    }
    expect(await h.close(), sha256.convert(data).toString());
  });

  test('missing prefix file surfaces an error', () async {
    final h = await Sha256Isolate.spawn();
    await h.addFilePrefix(p.join(dir.path, 'nope'), 10);
    await expectLater(h.close(), throwsA(anything));
  });

  test('readFileChunks honors start, end and chunk size', () async {
    final chunks = await readFileChunks(
      path,
      start: 10,
      end: 1000,
      chunkSize: 256,
    ).toList();
    expect(chunks.every((c) => c.length <= 256), isTrue);
    expect(chunks.expand((c) => c).toList(), data.sublist(10, 1000));
  });
}
