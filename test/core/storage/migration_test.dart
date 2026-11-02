import 'dart:io';

import 'package:crossdrop/core/storage/database.dart';
import 'package:crossdrop/core/storage/settings_repository.dart';
import 'package:crossdrop/core/storage/trust_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('a Phase 3 database (schema 2) upgrades to 3 and keeps its rows', () async {
    final dir = Directory.systemTemp.createTempSync('cd_migrate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File(p.join(dir.path, 'db.sqlite'));

    // Build a schema-2 database: today's schema minus what version 3 adds.
    var db = AppDatabase(NativeDatabase(file));
    await db.customSelect('SELECT 1').get(); // opens and creates
    await db.customStatement('DROP TABLE trusted_devices');
    await db.customStatement('DROP TABLE settings');
    await db.customStatement(
      'ALTER TABLE sessions DROP COLUMN peer_fingerprint',
    );
    await db.customStatement(
      "INSERT INTO sessions (session_id, direction, peer_device_id, peer_name, "
      "peer_platform, status, total_bytes, created_at, updated_at) "
      "VALUES ('s1', 'send', 'id', 'n', 'ios', 'paused', 1, 0, 0)",
    );
    await db.customStatement('PRAGMA user_version = 2');
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final row = await (db.select(db.transferSessions)).getSingle();
    expect(row.sessionId, 's1');
    expect(row.peerFingerprint, isNull);
    expect(await TrustRepository(db).all(), isEmpty);
    expect(await SettingsRepository(db).receivingEnabled(), isTrue);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 3);
  });
}
