import 'dart:io';

import 'package:crossdrop/core/client/peer_check.dart';
import 'package:crossdrop/core/client/upload_client.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/device_credentials.dart';
import 'package:crossdrop/core/server/receive_server.dart';
import 'package:crossdrop/core/storage/database.dart';
import 'package:crossdrop/core/storage/transfer_repository.dart';
import 'package:crossdrop/core/storage/trust_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _id = '3f2a9c1b-0d4e-4f5a-8b6c-7d8e9f0a1b2c';

void main() {
  late DeviceCredentials identity;
  late DeviceCredentials other;
  late DeviceCredentials me;

  setUpAll(() async {
    identity = await DeviceCredentials.generate();
    other = await DeviceCredentials.generate();
    me = await DeviceCredentials.generate();
  });

  Future<ConnectTarget> check(
    ConnectTarget t, {
    ReceiverTrustLookup? trustLookup,
    Duration timeout = const Duration(seconds: 5),
  }) =>
      checkPeer(t, credentials: me, trustLookup: trustLookup, timeout: timeout);

  Future<ReceiveServer> start(Directory root, {List<int>? versions}) =>
      ReceiveServer.start(
        info: DeviceInfo(
          id: _id,
          name: 'Pixel',
          platform: 'android',
          versions: versions ?? const [protocolVersion],
        ),
        credentials: identity,
        tempDir: p.join(root.path, 'tmp'),
        saveDir: p.join(root.path, 'save'),
        repository: TransferRepository(AppDatabase(NativeDatabase.memory())),
        decider: (_) async => true,
        address: InternetAddress.loopbackIPv4,
      );

  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('cd_peer'));
  tearDown(() => root.deleteSync(recursive: true));

  test('first contact: learns the fingerprint, id and name', () async {
    final server = await start(root);
    addTearDown(server.close);
    final t = await check(ConnectTarget(host: '127.0.0.1', port: server.port));
    expect(t.deviceId, _id);
    expect(t.name, 'Pixel');
    expect(t.port, server.port);
    expect(t.fingerprint, identity.fingerprint);
    expect(t.pinSource, PinSource.firstContact);
    expect(t.trust.isTrusted, isFalse);
  });

  test('nearby list: the TXT hint must match the real fingerprint', () async {
    final server = await start(root);
    addTearDown(server.close);
    final ok = await check(
      ConnectTarget(
        host: '127.0.0.1',
        port: server.port,
        deviceId: _id,
        fingerprintHint: identity.fingerprint.substring(0, 16),
      ),
    );
    expect(ok.fingerprint, identity.fingerprint);
    await expectLater(
      check(
        ConnectTarget(
          host: '127.0.0.1',
          port: server.port,
          deviceId: _id,
          fingerprintHint: other.fingerprint.substring(0, 16),
        ),
      ),
      throwsA(
        isA<UploadException>().having(
          (e) => e.code,
          'code',
          'identity_mismatch',
        ),
      ),
    );
  });

  test('QR: connects when the TLS fingerprint matches the QR', () async {
    final server = await start(root);
    addTearDown(server.close);
    final t = await check(
      ConnectTarget(
        host: '127.0.0.1',
        port: server.port,
        deviceId: _id,
        fingerprint: identity.fingerprint,
      ),
    );
    expect(t.fingerprint, identity.fingerprint);
    expect(t.pinSource, PinSource.qr);
  });

  test(
    'QR: a tampered fingerprint fails and is never retried unpinned',
    () async {
      final server = await start(root);
      addTearDown(server.close);
      await expectLater(
        check(
          ConnectTarget(
            host: '127.0.0.1',
            port: server.port,
            deviceId: _id,
            fingerprint: other.fingerprint,
          ),
        ),
        throwsA(
          isA<UploadException>().having((e) => e.code, 'code', pinMismatchCode),
        ),
      );
    },
  );

  test('reports trust and lookalikes from the lookup', () async {
    final server = await start(root);
    addTearDown(server.close);
    final known = TrustedDevice(
      fingerprint: other.fingerprint,
      deviceId: _id,
      name: 'Pixel',
      platform: 'android',
      autoAccept: false,
      firstSeen: DateTime(2026),
      lastSeen: DateTime(2026),
    );
    String? askedFp;
    final t = await check(
      ConnectTarget(host: '127.0.0.1', port: server.port),
      trustLookup: ({required fingerprint, deviceId, name}) async {
        askedFp = fingerprint;
        return PeerTrust(lookalike: known);
      },
    );
    expect(askedFp, identity.fingerprint);
    expect(t.trust.isTrusted, isFalse);
    expect(t.trust.lookalike?.name, 'Pixel');
  });

  test('another device at the address is refused', () async {
    final server = await start(root);
    addTearDown(server.close);
    await expectLater(
      check(
        ConnectTarget(
          host: '127.0.0.1',
          port: server.port,
          deviceId: 'bbbbbbbb-0000-4000-8000-000000000002',
        ),
      ),
      throwsA(
        isA<UploadException>().having(
          (e) => e.code,
          'code',
          'identity_mismatch',
        ),
      ),
    );
  });

  test('no common version is refused', () async {
    final server = await start(root, versions: const [7]);
    addTearDown(server.close);
    await expectLater(
      check(ConnectTarget(host: '127.0.0.1', port: server.port)),
      throwsA(isA<UploadException>().having((e) => e.code, 'code', 'version')),
    );
  });

  test('nothing listening is a network error', () async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    await expectLater(
      check(
        ConnectTarget(host: '127.0.0.1', port: port),
        timeout: const Duration(seconds: 2),
      ),
      throwsA(isA<UploadException>().having((e) => e.code, 'code', 'network')),
    );
  });
}
