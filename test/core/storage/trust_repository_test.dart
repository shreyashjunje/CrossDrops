import 'package:crossdrop/core/storage/database.dart';
import 'package:crossdrop/core/storage/settings_repository.dart';
import 'package:crossdrop/core/storage/trust_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _fpA = 'aa00000000000000000000000000000000000000000000000000000000000000';
const _fpB = 'bb00000000000000000000000000000000000000000000000000000000000000';
const _idA = '0000000a-0000-4000-8000-000000000000';
const _idB = '0000000b-0000-4000-8000-000000000000';

void main() {
  late AppDatabase db;
  late TrustRepository repo;
  var now = DateTime(2026, 11, 2, 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = TrustRepository(db, clock: () => now);
  });
  tearDown(() => db.close());

  Future<TrustedDevice> trustA() => repo.trust(
    fingerprint: _fpA,
    deviceId: _idA,
    name: "Mom's iPhone",
    platform: 'ios',
  );

  test('trust stores a device; check finds it by fingerprint only', () async {
    final d = await trustA();
    expect(d.autoAccept, isFalse);
    expect(d.firstSeen, now);
    final t = await repo.check(fingerprint: _fpA, name: 'Other name');
    expect(t.isTrusted, isTrue);
    expect(t.trusted!.name, "Mom's iPhone");
  });

  test('an unknown fingerprint is not trusted', () async {
    await trustA();
    final t = await repo.check(fingerprint: _fpB, deviceId: _idB, name: 'X');
    expect(t.isTrusted, isFalse);
    expect(t.lookalike, isNull);
  });

  test(
    'same name, different fingerprint: not trusted, flagged as lookalike',
    () async {
      await trustA();
      final t = await repo.check(
        fingerprint: _fpB,
        deviceId: _idB,
        name: "  mom's IPHONE ",
      );
      expect(t.isTrusted, isFalse);
      expect(t.lookalike?.fingerprint, _fpA);
    },
  );

  test('same device id, different fingerprint: lookalike', () async {
    await trustA();
    final t = await repo.check(fingerprint: _fpB, deviceId: _idA, name: 'Z');
    expect(t.isTrusted, isFalse);
    expect(t.lookalike?.fingerprint, _fpA);
  });

  test(
    'trusting again keeps autoAccept and firstSeen, updates labels',
    () async {
      final first = await trustA();
      await repo.setAutoAccept(_fpA, true);
      now = now.add(const Duration(days: 1));
      final again = await repo.trust(
        fingerprint: _fpA,
        deviceId: _idB,
        name: 'Renamed',
        platform: 'ios',
      );
      expect(again.autoAccept, isTrue);
      expect(again.firstSeen, first.firstSeen);
      expect(again.lastSeen, now);
      expect(again.name, 'Renamed');
      expect(again.deviceId, _idB);
    },
  );

  test('touch updates lastSeen of trusted devices only', () async {
    await trustA();
    now = now.add(const Duration(hours: 1));
    await repo.touch(_fpA, name: 'New label');
    await repo.touch(_fpB);
    final d = await repo.find(_fpA);
    expect(d!.lastSeen, now);
    expect(d.name, 'New label');
    expect(await repo.find(_fpB), isNull);
  });

  test('remove forgets the device', () async {
    await trustA();
    await repo.remove(_fpA);
    expect((await repo.check(fingerprint: _fpA)).isTrusted, isFalse);
    expect(await repo.all(), isEmpty);
  });

  test('refuses an invalid fingerprint', () {
    expect(
      () => repo.trust(
        fingerprint: 'nope',
        deviceId: _idA,
        name: 'n',
        platform: 'ios',
      ),
      throwsArgumentError,
    );
  });

  group('SettingsRepository', () {
    test('receiving is on by default and can be switched', () async {
      final s = SettingsRepository(db);
      expect(await s.receivingEnabled(), isTrue);
      await s.setReceivingEnabled(false);
      expect(await s.receivingEnabled(), isFalse);
      await s.setReceivingEnabled(true);
      expect(await s.receivingEnabled(), isTrue);
    });
  });
}
