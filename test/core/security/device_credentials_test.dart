import 'dart:convert';

import 'package:basic_utils/basic_utils.dart';
import 'package:crossdrop/core/security/device_credentials.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:crossdrop/core/security/fingerprint.dart';
import 'package:crossdrop/core/security/secret_store.dart';
import 'package:crossdrop/core/storage/database.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DeviceCredentials a;
  late DeviceCredentials b;

  setUpAll(() async {
    a = await DeviceCredentials.generate();
    b = await DeviceCredentials.generate();
  });

  group('fingerprint', () {
    test('is the SHA-256 of the certificate DER, lowercase hex', () {
      final der = CryptoUtils.getBytesFromPEMString(a.certificatePem);
      expect(a.fingerprint, sha256.convert(der).toString());
      expect(isValidFingerprint(a.fingerprint), isTrue);
      expect(
        certificateFingerprint(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('differs between two generated identities', () {
      expect(a.fingerprint, isNot(b.fingerprint));
    });

    test('isValidFingerprint refuses other shapes', () {
      expect(isValidFingerprint(a.fingerprint.toUpperCase()), isFalse);
      expect(isValidFingerprint(a.fingerprint.substring(1)), isFalse);
      expect(isValidFingerprint('${a.fingerprint}0'), isFalse);
    });

    test('fingerprintsEqual', () {
      expect(fingerprintsEqual(a.fingerprint, a.fingerprint), isTrue);
      expect(fingerprintsEqual(a.fingerprint, b.fingerprint), isFalse);
      expect(fingerprintsEqual(a.fingerprint, ''), isFalse);
    });

    test('shortFingerprint groups the first 16 characters', () {
      expect(
        shortFingerprint('0123456789abcdef${'0' * 48}'),
        '0123 4567 89ab cdef',
      );
    });
  });

  group('DeviceCredentials', () {
    test('key is ECDSA P-256 and the certificate is self-signed SHA-256', () {
      final data = X509Utils.x509CertificateFromPem(a.certificatePem);
      expect(
        data.tbsCertificate!.subjectPublicKeyInfo.parameterReadableName,
        'prime256v1',
      );
      expect(data.signatureAlgorithmReadableName, 'ecdsaWithSHA256');
      // No personal data in a certificate every peer sees.
      expect(data.tbsCertificate!.subject, {'2.5.4.3': 'CrossDrop'});
    });

    test('signatures verify with the certificate key only', () {
      final msg = utf8.encode('hello');
      final sig = a.sign(msg);
      expect(PeerCertificate.parse(a.certificateDer).verify(msg, sig), isTrue);
      expect(
        PeerCertificate.parse(a.certificateDer)
            .verify(utf8.encode('hellO'), sig),
        isFalse,
      );
      expect(PeerCertificate.parse(b.certificateDer).verify(msg, sig), isFalse);
      expect(
        PeerCertificate.parse(a.certificateDer).verify(msg, [1, 2, 3]),
        isFalse,
      );
    });

    test('fromPem round-trips and keeps the fingerprint', () {
      final again = DeviceCredentials.fromPem(
        certificatePem: a.certificatePem,
        privateKeyPem: a.privateKeyPem,
      );
      expect(again.fingerprint, a.fingerprint);
    });

    test('fromPem refuses a key that does not match the certificate', () {
      expect(
        () => DeviceCredentials.fromPem(
          certificatePem: a.certificatePem,
          privateKeyPem: b.privateKeyPem,
        ),
        throwsFormatException,
      );
      expect(
        () => DeviceCredentials.fromPem(
          certificatePem: a.certificatePem,
          privateKeyPem: 'garbage',
        ),
        throwsFormatException,
      );
    });

    test('PeerCertificate.parse refuses garbage and oversized input', () {
      expect(() => PeerCertificate.parse([]), throwsFormatException);
      expect(() => PeerCertificate.parse([1, 2, 3]), throwsFormatException);
      expect(
        () => PeerCertificate.parse(List.filled(maxCertificateBytes + 1, 0)),
        throwsFormatException,
      );
      expect(
        PeerCertificate.parse(a.certificateDer).fingerprint,
        a.fingerprint,
      );
    });
  });

  group('CredentialRepository', () {
    late AppDatabase db;
    late MemorySecretStore secrets;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      secrets = MemorySecretStore();
    });
    tearDown(() => db.close());

    test('creates once, then loads the same identity', () async {
      final repo = CredentialRepository(db, secrets);
      final first = await repo.loadOrCreate();
      final second = await repo.loadOrCreate();
      expect(second.fingerprint, first.fingerprint);
      // The private key is in the secret store, not the database.
      final row = await db.select(db.identity).getSingle();
      expect(row.certificate, first.certificatePem);
      expect(row.certificate, isNot(contains('PRIVATE KEY')));
      expect(
        secrets.values[CredentialRepository.privateKeyName],
        first.privateKeyPem,
      );
    });

    test('a wiped database (reinstall) gives a new identity even if the '
        'Keychain kept the old key', () async {
      final old = await CredentialRepository(db, secrets).loadOrCreate();
      await db.close();
      db = AppDatabase(NativeDatabase.memory());
      final fresh = await CredentialRepository(db, secrets).loadOrCreate();
      expect(fresh.fingerprint, isNot(old.fingerprint));
      expect(
        secrets.values[CredentialRepository.privateKeyName],
        fresh.privateKeyPem,
      );
    });

    test('a lost key gives a new identity', () async {
      final old = await CredentialRepository(db, secrets).loadOrCreate();
      secrets.values.clear();
      final fresh = await CredentialRepository(db, secrets).loadOrCreate();
      expect(fresh.fingerprint, isNot(old.fingerprint));
    });

    test('a key that does not match gives a new identity', () async {
      final old = await CredentialRepository(db, secrets).loadOrCreate();
      secrets.values[CredentialRepository.privateKeyName] = b.privateKeyPem;
      final fresh = await CredentialRepository(db, secrets).loadOrCreate();
      expect(fresh.fingerprint, isNot(old.fingerprint));
      expect(fresh.fingerprint, isNot(b.fingerprint));
    });
  });
}
