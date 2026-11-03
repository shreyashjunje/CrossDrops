// Real descriptors through dart:ffi. POSIX only: runs on the Linux CI
// job and on macOS, skipped on Windows.
@TestOn('linux || mac-os')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crossdrop/core/engine/chunked_reader.dart';
import 'package:crossdrop/core/engine/fd_file.dart';
import 'package:crossdrop/core/engine/sha256_isolate.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('cd_fd'));
  tearDown(() => dir.deleteSync(recursive: true));

  Uint8List bytes(int n) =>
      Uint8List.fromList(List.generate(n, (i) => (i * 31 + 7) & 0xff));

  test('reads, writes, truncates and reports length', () {
    final path = p.join(dir.path, 'a.bin');
    final fd = FdFile.openPath(path, write: true);
    final f = FdFile(fd);
    try {
      f.writeAt(0, bytes(5000));
      f.writeAt(5000, bytes(10));
      f.sync();
      expect(f.length(), 5010);
      expect(f.readAt(4995, 100), [...bytes(5000).sublist(4995), ...bytes(10)]);
      f.truncate(100);
      expect(f.length(), 100);
      expect(f.readAt(0, 1000), bytes(100));
      f.setModified(DateTime.utc(2020, 5, 6, 7, 8, 9));
    } finally {
      f.close();
    }
    expect(
      File(path).lastModifiedSync().toUtc(),
      DateTime.utc(2020, 5, 6, 7, 8, 9),
    );
  });

  test('a bad descriptor throws a FileSystemException with errno', () {
    expect(
      () => FdFile(987654).readAt(0, 10),
      throwsA(
        isA<FileSystemException>().having(
          (e) => e.osError?.errorCode,
          'errno',
          9,
        ),
      ),
    );
  });

  test('streams chunks through the worker and hashes in the isolate', () async {
    final path = p.join(dir.path, 'b.bin');
    final data = bytes(3 * 1024 * 1024 + 17);
    File(path).writeAsBytesSync(data);
    final fd = FdFile.openPath(path);
    try {
      final source = FdSource(fd);
      expect(await sourceLength(source), data.length);
      final got = BytesBuilder();
      await for (final c in readSourceChunks(
        source,
        start: 10,
        chunkSize: 1 << 20,
      )) {
        got.add(c);
      }
      expect(got.takeBytes(), data.sublist(10));
      final h = BackgroundFileHash.startSource(source, data.length);
      expect(await h.digest, sha256.convert(data).toString());
    } finally {
      await (await FdWorker.instance).close(fd);
    }
  });

  test('worker writes land in the file', () async {
    final path = p.join(dir.path, 'c.bin');
    final fd = FdFile.openPath(path, write: true);
    final io = await FdWorker.instance;
    await io.writeAt(fd, 0, bytes(4096));
    await io.truncate(fd, 1000);
    await io.sync(fd);
    await io.close(fd);
    expect(File(path).readAsBytesSync(), bytes(1000));
  });
}
