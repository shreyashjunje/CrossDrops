import 'dart:io';

import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/storage/database.dart';
import 'package:crossdrop/core/storage/partial_cleanup.dart';
import 'package:crossdrop/core/storage/transfer_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const peer = SenderInfo(
  id: '11111111-1111-4111-8111-111111111111',
  name: 'iPhone',
  platform: 'ios',
);

void main() {
  late AppDatabase db;
  late DateTime now;
  late TransferRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime(2026, 11, 2, 12);
    repo = TransferRepository(db, clock: () => now);
  });

  tearDown(() => db.close());

  Future<int> receiveSession(String sid, {int files = 2}) => repo.createSession(
    sessionId: sid,
    direction: TransferDirection.receive,
    peer: peer,
    status: SessionStatus.offered,
    files: [
      for (var i = 0; i < files; i++)
        StoredFile.fromOffer(
          FileOffer(
            fileId: 'f$i',
            name: 'IMG_$i.HEIC',
            size: 100 + i,
            kind: FileKind.photo,
          ),
          tempPath: '/tmp/$sid/f$i.part',
        ),
    ],
  );

  test('stores a session with files in manifest order', () async {
    await receiveSession('s1', files: 3);
    final s = (await repo.find('s1', TransferDirection.receive))!;
    expect(s.peer.name, 'iPhone');
    expect(s.status, SessionStatus.offered);
    expect(s.totalBytes, 100 + 101 + 102);
    expect(s.files.map((f) => f.fileId), ['f0', 'f1', 'f2']);
    expect(s.files.first.kind, FileKind.photo);
    expect(s.files.first.status, FileTransferStatus.pending);
    expect(await repo.find('s1', TransferDirection.send), isNull);
  });

  test('the same session id may exist once per direction', () async {
    await receiveSession('s1');
    await repo.createSession(
      sessionId: 's1',
      direction: TransferDirection.send,
      peer: peer,
      status: SessionStatus.offered,
      files: const [],
    );
    await expectLater(receiveSession('s1'), throwsA(anything));
  });

  test('updates checkpoints and statuses', () async {
    final row = await receiveSession('s1');
    await repo.updateSession(row, status: SessionStatus.transferring);
    await repo.updateFile(
      row,
      'f0',
      transferredBytes: 64,
      status: FileTransferStatus.receiving,
      hashAttempts: 1,
    );
    final s = (await repo.find('s1', TransferDirection.receive))!;
    expect(s.status, SessionStatus.transferring);
    expect(s.files.first.transferredBytes, 64);
    expect(s.files.first.status, FileTransferStatus.receiving);
    expect(s.files.first.hashAttempts, 1);
    expect(s.transferredBytes, 64);
    expect(s.finishedAt, isNull);
  });

  test('terminal status sets finishedAt and leaves unfinished()', () async {
    final a = await receiveSession('a');
    await receiveSession('b');
    await repo.updateSession(
      a,
      status: SessionStatus.cancelled,
      reason: 'receiver',
    );
    final a2 = (await repo.find('a', TransferDirection.receive))!;
    expect(a2.finishedAt, now);
    expect(a2.reason, 'receiver');
    expect((await repo.unfinished()).map((s) => s.sessionId), ['b']);
    expect(await repo.unfinished(TransferDirection.send), isEmpty);
  });

  group('migration', () {
    test('a version 1 database gains the transfer tables', () async {
      final dir = Directory.systemTemp.createTempSync('cd_db');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File(p.join(dir.path, 'v1.sqlite'));
      // What Phase 2 shipped: only the identity table, user_version 1.
      final v1 = NativeDatabase(
        file,
        setup: (raw) {
          raw.execute(
            'CREATE TABLE identity (slot INTEGER NOT NULL DEFAULT 1, '
            'device_id TEXT NOT NULL, device_name TEXT NOT NULL, '
            'certificate TEXT NULL, PRIMARY KEY (slot))',
          );
          raw.execute(
            "INSERT INTO identity (device_id, device_name) VALUES ('id', 'n')",
          );
          raw.execute('PRAGMA user_version = 1');
        },
      );
      await v1.ensureOpen(_NoUser());
      await v1.close();

      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);
      final r = TransferRepository(upgraded);
      await r.createSession(
        sessionId: 's',
        direction: TransferDirection.receive,
        peer: peer,
        status: SessionStatus.offered,
        files: const [],
      );
      expect(await r.unfinished(), hasLength(1));
      final id = await upgraded.select(upgraded.identity).getSingle();
      expect(id.deviceName, 'n');
    });
  });

  group('PartialCleanup', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('cd_cleanup'));
    tearDown(() => temp.deleteSync(recursive: true));

    void makePart(String sid) {
      Directory(p.join(temp.path, sid)).createSync();
      File(p.join(temp.path, sid, 'f0.part')).writeAsStringSync('x');
    }

    test('expires sessions idle for 24 h and deletes their parts', () async {
      final old = await receiveSession('old');
      makePart('old');
      now = now.add(const Duration(hours: 25));
      await receiveSession('fresh');
      makePart('fresh');

      final deleted = await PartialCleanup(
        repository: repo,
        incomingTemp: temp.path,
        clock: () => now,
      ).run();

      expect(deleted, 1);
      expect(Directory(p.join(temp.path, 'old')).existsSync(), isFalse);
      expect(Directory(p.join(temp.path, 'fresh')).existsSync(), isTrue);
      final s = (await repo.find('old', TransferDirection.receive))!;
      expect(s.status, SessionStatus.failed);
      expect(s.reason, expiredReason);
      expect(old, isNonZero);
    });

    test('expired parts outside the folder go through deletePart', () async {
      final rowId = await receiveSession('gone', files: 3);
      await repo.updateFile(rowId, 'f0', tempPath: 'content://media/9');
      await repo.updateFile(rowId, 'f1', status: FileTransferStatus.saved);
      now = now.add(const Duration(hours: 25));
      final deleted = <String>[];

      await PartialCleanup(
        repository: repo,
        incomingTemp: temp.path,
        deletePart: (loc) async => deleted.add(loc),
        clock: () => now,
      ).run();

      // The saved file is not touched; the stored location is used.
      expect(deleted, ['content://media/9', '/tmp/gone/f2.part']);
    });

    test('keeps recent orphans, deletes old ones', () async {
      makePart('orphan');
      final cleanup = PartialCleanup(
        repository: repo,
        incomingTemp: temp.path,
        clock: () => now,
      );
      // Written just now (real clock is earlier than the fake one + 24 h).
      now = DateTime.now();
      expect(await cleanup.run(), 0);
      now = DateTime.now().add(const Duration(hours: 25));
      expect(await cleanup.run(), 1);
    });

    test('a missing temp folder is fine', () async {
      final cleanup = PartialCleanup(
        repository: repo,
        incomingTemp: p.join(temp.path, 'nope'),
      );
      expect(await cleanup.run(), 0);
    });
  });
}

class _NoUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
