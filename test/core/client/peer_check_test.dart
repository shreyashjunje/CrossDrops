import 'dart:io';

import 'package:crossdrop/core/client/peer_check.dart';
import 'package:crossdrop/core/client/upload_client.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/ephemeral_identity.dart';
import 'package:crossdrop/core/server/receive_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _id = '3f2a9c1b-0d4e-4f5a-8b6c-7d8e9f0a1b2c';

void main() {
  late EphemeralIdentity identity;

  setUpAll(() async => identity = await EphemeralIdentity.generate());

  Future<ReceiveServer> start(Directory root, {List<int>? versions}) =>
      ReceiveServer.start(
        info: DeviceInfo(
          id: _id,
          name: 'Pixel',
          platform: 'android',
          versions: versions ?? const [protocolVersion],
        ),
        securityContext: identity.serverContext(),
        tempDir: p.join(root.path, 'tmp'),
        saveDir: p.join(root.path, 'save'),
        address: InternetAddress.loopbackIPv4,
      );

  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('cd_peer'));
  tearDown(() => root.deleteSync(recursive: true));

  test('returns the target with id and name', () async {
    final server = await start(root);
    addTearDown(server.close);
    final t = await checkPeer(
      ConnectTarget(host: '127.0.0.1', port: server.port),
    );
    expect(t.deviceId, _id);
    expect(t.name, 'Pixel');
    expect(t.port, server.port);
  });

  test('accepts the expected id and keeps the fingerprint', () async {
    final server = await start(root);
    addTearDown(server.close);
    final t = await checkPeer(
      ConnectTarget(
        host: '127.0.0.1',
        port: server.port,
        deviceId: _id,
        fingerprint: 'a' * 64,
      ),
    );
    expect(t.fingerprint, 'a' * 64);
  });

  test('another device at the address is refused', () async {
    final server = await start(root);
    addTearDown(server.close);
    await expectLater(
      checkPeer(
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
      checkPeer(ConnectTarget(host: '127.0.0.1', port: server.port)),
      throwsA(isA<UploadException>().having((e) => e.code, 'code', 'version')),
    );
  });

  test('nothing listening is a network error', () async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    await expectLater(
      checkPeer(
        ConnectTarget(host: '127.0.0.1', port: port),
        timeout: const Duration(seconds: 2),
      ),
      throwsA(isA<UploadException>().having((e) => e.code, 'code', 'network')),
    );
  });
}
