import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:crossdrop/core/security/device_credentials.dart';
import 'package:crossdrop/core/security/pinning.dart';
import 'package:flutter_test/flutter_test.dart';

/// A server on loopback that counts the requests that reach it.
class _Server {
  _Server(this.http) {
    http.listen((r) async {
      requests++;
      await r.drain<void>();
      r.response.write('ok');
      await r.response.close();
    });
  }

  final HttpServer http;
  int requests = 0;

  static Future<_Server> start(SecurityContext context) async => _Server(
    await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context),
  );

  Uri get url => Uri.parse('https://127.0.0.1:${http.port}/v1/info');
}

Future<String> _get(HttpClient client, Uri url) async {
  try {
    final req = await client.putUrl(url);
    req.add(utf8.encode('secret file bytes'));
    final res = await req.close();
    return await res.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

void main() {
  late DeviceCredentials receiver;
  late DeviceCredentials other;
  late _Server server;

  setUpAll(() async {
    receiver = await DeviceCredentials.generate();
    other = await DeviceCredentials.generate();
    server = await _Server.start(receiver.serverContext());
  });

  tearDownAll(() => server.http.close(force: true));

  test('connects when the fingerprint matches', () async {
    final before = server.requests;
    final body = await _get(
      pinnedHttpClient(fingerprint: receiver.fingerprint),
      server.url,
    );
    expect(body, 'ok');
    expect(server.requests, before + 1);
  });

  test('a wrong certificate fails in the handshake; nothing is sent', () async {
    final before = server.requests;
    var mismatches = 0;
    await expectLater(
      _get(
        pinnedHttpClient(
          fingerprint: other.fingerprint,
          onMismatch: () => mismatches++,
        ),
        server.url,
      ),
      throwsA(anyOf(isA<HandshakeException>(), isA<PinMismatchException>())),
    );
    expect(server.requests, before);
    expect(mismatches, greaterThan(0));
  });

  test(
    'an attacker leaf followed by the pinned certificate is refused',
    () async {
      // The attacker cannot sign as the receiver, so it presents its own leaf
      // (claiming the receiver as issuer) and appends the receiver's public
      // certificate, hoping the pin check looks at the wrong one.
      final pair = CryptoUtils.generateEcKeyPair();
      final key = pair.privateKey as ECPrivateKey;
      final csr = X509Utils.generateEccCsrPem(
        {'CN': 'leaf'},
        key,
        pair.publicKey as ECPublicKey,
      );
      final leaf = X509Utils.generateSelfSignedCertificate(
        key,
        csr,
        30,
        issuer: {'CN': 'CrossDrop'},
      );
      final context = SecurityContext(withTrustedRoots: false)
        ..useCertificateChainBytes(
          utf8.encode('$leaf\n${receiver.certificatePem}'),
        )
        ..usePrivateKeyBytes(
          utf8.encode(CryptoUtils.encodeEcPrivateKeyToPem(key)),
        );
      final evil = await _Server.start(context);
      addTearDown(() => evil.http.close(force: true));

      await expectLater(
        _get(pinnedHttpClient(fingerprint: receiver.fingerprint), evil.url),
        throwsA(anyOf(isA<HandshakeException>(), isA<PinMismatchException>())),
      );
      expect(evil.requests, 0);
    },
  );

  test('refuses a malformed pin instead of connecting unpinned', () {
    expect(() => pinnedHttpClient(fingerprint: 'abc'), throwsArgumentError);
  });

  test(
    'probeFingerprint reads the server fingerprint and sends nothing',
    () async {
      final before = server.requests;
      final fp = await probeFingerprint('127.0.0.1', server.http.port);
      expect(fp, receiver.fingerprint);
      expect(server.requests, before);
    },
  );

  test('server refuses TLS below 1.3', () {
    expect(
      receiver.serverContext().minimumTlsProtocolVersion,
      TlsProtocolVersion.tls1_3,
    );
  });
}
