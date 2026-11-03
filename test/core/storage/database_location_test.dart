import 'dart:io';

import 'package:crossdrop/core/storage/database_location.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late String docs;
  late String support;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cd_dbloc');
    docs = p.join(root.path, 'Documents');
    support = p.join(root.path, 'Support');
    Directory(docs).createSync();
  });
  tearDown(() => root.deleteSync(recursive: true));

  void write(String dir, String name, String text) {
    Directory(dir).createSync(recursive: true);
    File(p.join(dir, name)).writeAsStringSync(text);
  }

  test('moves the database and its side files', () async {
    write(docs, 'crossdrop.sqlite', 'db');
    write(docs, 'crossdrop.sqlite-wal', 'wal');
    write(docs, 'crossdrop.sqlite-shm', 'shm');
    write(docs, 'other.txt', 'not ours');

    final moved = await moveDatabaseFiles(
      fromDir: docs,
      toDir: support,
      name: 'crossdrop',
    );

    expect(moved, isTrue);
    expect(File(p.join(support, 'crossdrop.sqlite')).readAsStringSync(), 'db');
    expect(
      File(p.join(support, 'crossdrop.sqlite-wal')).readAsStringSync(),
      'wal',
    );
    expect(File(p.join(support, 'crossdrop.sqlite-shm')).existsSync(), isTrue);
    expect(File(p.join(docs, 'crossdrop.sqlite')).existsSync(), isFalse);
    expect(File(p.join(docs, 'other.txt')).existsSync(), isTrue);
  });

  test('never overwrites a database already in the new place', () async {
    write(docs, 'crossdrop.sqlite', 'old');
    write(support, 'crossdrop.sqlite', 'new');

    final moved = await moveDatabaseFiles(
      fromDir: docs,
      toDir: support,
      name: 'crossdrop',
    );

    expect(moved, isFalse);
    expect(File(p.join(support, 'crossdrop.sqlite')).readAsStringSync(), 'new');
  });

  test('does nothing on a fresh install', () async {
    expect(
      await moveDatabaseFiles(fromDir: docs, toDir: support, name: 'crossdrop'),
      isFalse,
    );
    expect(Directory(support).existsSync(), isFalse);
  });

  test('finishes a move that stopped after the side files', () async {
    // Crash after -wal moved but before the main file.
    write(support, 'crossdrop.sqlite-wal', 'wal');
    write(docs, 'crossdrop.sqlite', 'db');

    expect(
      await moveDatabaseFiles(fromDir: docs, toDir: support, name: 'crossdrop'),
      isTrue,
    );
    expect(File(p.join(support, 'crossdrop.sqlite')).readAsStringSync(), 'db');
    expect(
      File(p.join(support, 'crossdrop.sqlite-wal')).readAsStringSync(),
      'wal',
    );
  });
}
