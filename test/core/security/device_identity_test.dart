import 'dart:math';

import 'package:crossdrop/core/security/device_identity.dart';
import 'package:crossdrop/core/storage/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('newDeviceId', () {
    test('is a lowercase UUID v4', () {
      for (var i = 0; i < 100; i++) {
        final id = newDeviceId();
        expect(isValidDeviceId(id), isTrue, reason: id);
        expect(id[14], '4');
        expect('89ab'.contains(id[19]), isTrue);
      }
    });

    test('differs between calls', () {
      final ids = {for (var i = 0; i < 1000; i++) newDeviceId(Random(i))};
      expect(ids.length, 1000);
    });
  });

  test('isValidDeviceId rejects other shapes', () {
    expect(isValidDeviceId(''), isFalse);
    expect(isValidDeviceId('not-a-uuid'), isFalse);
    expect(isValidDeviceId('0123456789abcdef0123456789abcdef'), isFalse);
    expect(isValidDeviceId('12345678-1234-4234-8234-1234567890AB'), isFalse);
    expect(isValidDeviceId('12345678-1234-4234-8234-1234567890ab '), isFalse);
  });

  test('defaultDeviceName', () {
    const id = 'ab12cd34-0000-4000-8000-000000000000';
    expect(defaultDeviceName(id, DevicePlatform.ios), 'iPhone');
    expect(defaultDeviceName(id, DevicePlatform.android), 'Android AB12');
  });

  group('IdentityRepository', () {
    late AppDatabase db;
    late IdentityRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = IdentityRepository(db, platform: DevicePlatform.android);
    });

    tearDown(() => db.close());

    test('creates the identity once and returns it afterwards', () async {
      final first = await repo.loadOrCreate();
      final second = await repo.loadOrCreate();
      expect(isValidDeviceId(first.deviceId), isTrue);
      expect(first.deviceName, startsWith('Android '));
      expect(second.deviceId, first.deviceId);
      expect(await db.select(db.identity).get(), hasLength(1));
    });

    test('rename keeps the id and stores a sanitized name', () async {
      final before = await repo.loadOrCreate();
      final after = await repo.rename('  My\u0000 Phone\n ');
      expect(after.deviceId, before.deviceId);
      expect(after.deviceName, 'My Phone');
      expect((await repo.loadOrCreate()).deviceName, 'My Phone');
    });

    test('rename rejects an empty name', () async {
      await repo.loadOrCreate();
      expect(() => repo.rename(' \u200b\t'), throwsArgumentError);
    });
  });
}
