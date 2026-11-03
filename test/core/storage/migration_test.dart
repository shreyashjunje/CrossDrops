import 'dart:io';

import 'package:crossdrop/core/media/format_plan.dart';
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
    expect(version.read<int>('user_version'), 5);
  });

  test(
    'a Phase 4 database (schema 3) upgrades to 4 and keeps settings',
    () async {
      final dir = Directory.systemTemp.createTempSync('cd_migrate4');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File(p.join(dir.path, 'db.sqlite'));

      var db = AppDatabase(NativeDatabase(file));
      await db.customSelect('SELECT 1').get();
      await db.customStatement(
        'ALTER TABLE settings DROP COLUMN convert_heic_to_jpeg',
      );
      await db.customStatement(
        'ALTER TABLE settings DROP COLUMN send_live_photo_video',
      );
      await db.customStatement(
        'ALTER TABLE settings DROP COLUMN onboarding_done',
      );
      await db.customStatement(
        'INSERT INTO settings (slot, receiving_enabled) VALUES (1, 0)',
      );
      await db.customStatement('PRAGMA user_version = 3');
      await db.close();

      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final settings = SettingsRepository(db);
      expect(await settings.receivingEnabled(), isFalse);
      expect(await settings.formatSettings(), const FormatSettings());
      await settings.setConvertHeicToJpeg(true);
      expect((await settings.formatSettings()).convertHeicToJpeg, isTrue);
      expect(await settings.receivingEnabled(), isFalse);
    },
  );
  test(
    'a Phase 5 database (schema 4) upgrades to 5: introduction not shown yet',
    () async {
      final dir = Directory.systemTemp.createTempSync('cd_migrate5');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File(p.join(dir.path, 'db.sqlite'));

      var db = AppDatabase(NativeDatabase(file));
      await db.customSelect('SELECT 1').get();
      await db.customStatement(
        'ALTER TABLE settings DROP COLUMN onboarding_done',
      );
      await db.customStatement(
        'INSERT INTO settings (slot, receiving_enabled, convert_heic_to_jpeg) '
        'VALUES (1, 0, 1)',
      );
      await db.customStatement('PRAGMA user_version = 4');
      await db.close();

      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final settings = SettingsRepository(db);
      expect(await settings.watchOnboardingDone().first, isFalse);
      expect(await settings.receivingEnabled(), isFalse);
      expect((await settings.formatSettings()).convertHeicToJpeg, isTrue);
      await settings.setOnboardingDone(true);
      expect(await settings.watchOnboardingDone().first, isTrue);
      expect(await settings.receivingEnabled(), isFalse);
    },
  );
}
