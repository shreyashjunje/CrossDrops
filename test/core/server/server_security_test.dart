import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crossdrop/core/client/upload_client.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/device_credentials.dart';
import 'package:crossdrop/core/server/receive_server.dart';
import 'package:crossdrop/core/storage/transfer_repository.dart';
import 'package:crossdrop/core/storage/trust_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_receiver.dart';

void main() {
  late DeviceCredentials receiver;
  late DeviceCredentials alice;
  late DeviceCredentials mallory;
  late TestReceiver r;
  late HttpClient http;

  setUpAll(() async {
    receiver = await DeviceCredentials.generate();
    alice = await DeviceCredentials.generate();
    mallory = await DeviceCredentials.generate();
  });

  setUp(() async {
    r = await TestReceiver.start(identity: receiver);
    http = HttpClient()..badCertificateCallback = (_, _, _) => true;
  });

  tearDown(() async {
    http.close(force: true);
    await r.close();
  });

  Future<(int, Map<String, Object?>)> send(
    String method,
    String path, {
    Object? json,
    String? token,
    Map<String, String> headers = const {},
  }) async {
    final req = await http.openUrl(
      method,
      Uri.parse('https://127.0.0.1:${r.port}$path'),
    );
    if (token != null) req.headers.set('authorization', 'Bearer $token');
    headers.forEach(req.headers.set);
    if (json != null) {
      final bytes = utf8.encode(jsonEncode(json));
      req.headers.contentType = ContentType.json;
      req.contentLength = bytes.length;
      req.add(bytes);
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return (res.statusCode, jsonDecode(text) as Map<String, Object?>);
  }

  Map<String, Object?> offer({String name = 'a.txt'}) => SessionOffer(
    sender: testSender,
    files: [FileOffer(fileId: 'f1', name: name, size: 3)],
  ).toJson();

  Future<String> tokenFor(DeviceCredentials who) =>
      authenticateRaw(r.port, who, receiverFingerprint: receiver.fingerprint);

  TrustedDevice trusted(DeviceCredentials who, {bool autoAccept = false}) =>
      TrustedDevice(
        fingerprint: who.fingerprint,
        deviceId: testSender.id,
        name: testSender.name,
        platform: 'ios',
        autoAccept: autoAccept,
        firstSeen: DateTime(2026),
        lastSeen: DateTime(2026),
      );

  group('authentication', () {
    test('/v1/info needs no token; sessions do', () async {
      expect((await send('GET', '/v1/info')).$1, 200);
      final (code, body) = await send('POST', '/v1/sessions', json: offer());
      expect(code, 401);
      expect(body['error'], ErrorCodes.authRequired);
      expect((await send('GET', '/v1/sessions/abc', token: 'x' * 43)).$1, 401);
    });

    test(
      'a correct proof gets a token that opens the session routes',
      () async {
        final token = await tokenFor(alice);
        final (code, _) = await send(
          'POST',
          '/v1/sessions',
          json: offer(),
          token: token,
        );
        expect(code, 200);
      },
    );

    test('a signature by another key is refused', () async {
      await expectLater(
        authenticateRaw(
          r.port,
          alice,
          receiverFingerprint: receiver.fingerprint,
          sign: mallory.sign,
        ),
        throwsA(
          isA<HttpException>().having((e) => e.message, 'm', '401 auth_failed'),
        ),
      );
    });

    test(
      'a proof made for another receiver is refused (no relaying)',
      () async {
        final elsewhere = await DeviceCredentials.generate();
        await expectLater(
          authenticateRaw(
            r.port,
            alice,
            receiverFingerprint: elsewhere.fingerprint,
          ),
          throwsA(
            isA<HttpException>().having(
              (e) => e.message,
              'm',
              '401 auth_failed',
            ),
          ),
        );
      },
    );

    test('an unknown fingerprint can authenticate, but its offer waits for '
        'the prompt with a pairing code', () async {
      final offers = <IncomingOffer>[];
      r.decider = (o) async {
        offers.add(o);
        return false;
      };
      final client = clientFor(r, mallory);
      addTearDown(client.close);
      final created = await client.offer(
        SessionOffer(
          sender: testSender, // claims to be "Test sender"
          files: const [FileOffer(fileId: 'f1', name: 'x', size: 1)],
        ),
      );
      expect(created.trusted, isFalse);
      await waitFor(() => offers.isNotEmpty);
      final o = offers.single;
      expect(o.senderFingerprint, mallory.fingerprint);
      expect(o.trust.isTrusted, isFalse);
      // Both phones show the same code.
      expect(o.pairingCode, client.pairingCode);
      expect(o.pairingCode, matches(RegExp(r'^\d{6}$')));
      await waitFor(
        () => r.server.sessions.single.status == SessionStatus.rejected,
      );
    });

    test('each authentication gives a fresh code', () async {
      final codes = <String>{};
      for (var i = 0; i < 5; i++) {
        final c = clientFor(r, alice);
        await c
            .offer(
              SessionOffer(
                sender: testSender,
                files: const [FileOffer(fileId: 'f1', name: 'x', size: 1)],
              ),
            )
            .catchError((_) => const SessionCreated(sessionId: '', status: ''));
        codes.add(c.pairingCode!);
        c.close();
      }
      expect(codes.length, greaterThan(1));
    });

    test('tokens die with the server; the client re-authenticates', () async {
      final client = clientFor(r, alice);
      addTearDown(client.close);
      final created = await client.offer(
        SessionOffer(
          sender: testSender,
          files: const [FileOffer(fileId: 'f1', name: 'x', size: 0)],
        ),
      );
      await r.restart();
      final status = await client.sessionStatus(created.sessionId);
      expect(status.sessionId, created.sessionId);
    });
  });

  group('sessions belong to their sender', () {
    test("another device cannot see, feed or cancel Alice's session", () async {
      final a = await tokenFor(alice);
      final m = await tokenFor(mallory);
      final (_, body) = await send(
        'POST',
        '/v1/sessions',
        json: offer(),
        token: a,
      );
      final sid = body['sessionId']! as String;
      for (final (method, path) in [
        ('GET', '/v1/sessions/$sid'),
        ('DELETE', '/v1/sessions/$sid'),
        ('GET', '/v1/sessions/$sid/files/f1'),
        ('POST', '/v1/sessions/$sid/files/f1/complete'),
      ]) {
        final (code, err) = await send(
          method,
          path,
          token: m,
          json: method == 'POST' ? {'sha256': '0' * 64} : null,
        );
        expect(code, 404, reason: '$method $path');
        expect(err['error'], ErrorCodes.notFound);
      }
      await expectLater(
        WebSocket.connect(
          'wss://127.0.0.1:${r.port}/v1/sessions/$sid/events',
          headers: {'authorization': 'Bearer $m'},
          customClient: http,
        ),
        throwsA(isA<WebSocketException>()),
      );
      // Alice still owns it.
      expect((await send('GET', '/v1/sessions/$sid', token: a)).$1, 200);
    });

    test(
      'a session stored before Phase 4 (no fingerprint) is not restored',
      () async {
        final rowId = await r.repo.createSession(
          sessionId: 'old',
          direction: TransferDirection.receive,
          peer: testSender,
          status: SessionStatus.paused,
          files: const [],
        );
        await r.restart();
        expect(r.server.sessions.where((s) => s.sessionId == 'old'), isEmpty);
        final stored = await r.repo.find('old', TransferDirection.receive);
        expect(stored!.rowId, rowId);
        expect(stored.status, SessionStatus.failed);
      },
    );
  });

  group('trust and the Receiving switch', () {
    test(
      'receiving off: untrusted offers get 403, trusted ones go through',
      () async {
        r.acceptsUntrusted = false;
        r.trustLookup = (fp, _) async => fp == alice.fingerprint
            ? PeerTrust(trusted: trusted(alice))
            : PeerTrust.unknown;
        final (code, body) = await send(
          'POST',
          '/v1/sessions',
          json: offer(),
          token: await tokenFor(mallory),
        );
        expect(code, 403);
        expect(body['error'], ErrorCodes.receivingOff);
        expect(
          r.events.whereType<OfferRefused>().single.reason,
          ErrorCodes.receivingOff,
        );
        final (ok, created) = await send(
          'POST',
          '/v1/sessions',
          json: offer(),
          token: await tokenFor(alice),
        );
        expect(ok, 200);
        expect(created['trusted'], isTrue);
        await waitFor(
          () =>
              r.server.sessions.any((s) => s.status == SessionStatus.accepted),
        );
      },
    );

    test('trusted without auto-accept still asks', () async {
      var asked = 0;
      r.decider = (_) async {
        asked++;
        return true;
      };
      r.trustLookup = (fp, _) async => PeerTrust(trusted: trusted(alice));
      await send(
        'POST',
        '/v1/sessions',
        json: offer(),
        token: await tokenFor(alice),
      );
      await waitFor(() => asked == 1);
      await waitFor(
        () => r.server.sessions.any((s) => s.status == SessionStatus.accepted),
      );
    });

    test('auto-accept skips the prompt only for that fingerprint', () async {
      var asked = 0;
      r.decider = (_) async {
        asked++;
        return false;
      };
      r.trustLookup = (fp, _) async => fp == alice.fingerprint
          ? PeerTrust(trusted: trusted(alice, autoAccept: true))
          : PeerTrust(lookalike: trusted(alice, autoAccept: true));
      final (_, a) = await send(
        'POST',
        '/v1/sessions',
        json: offer(),
        token: await tokenFor(alice),
      );
      await waitFor(
        () => r.server.sessions.any(
          (s) =>
              s.sessionId == a['sessionId'] &&
              s.status == SessionStatus.accepted,
        ),
      );
      expect(asked, 0);

      // Same name and id as Alice, different key: prompted, with a warning.
      final offers = <IncomingOffer>[];
      r.decider = (o) async {
        offers.add(o);
        return false;
      };
      await send(
        'POST',
        '/v1/sessions',
        json: offer(),
        token: await tokenFor(mallory),
      );
      await waitFor(() => offers.isNotEmpty);
      expect(offers.single.trust.isTrusted, isFalse);
      expect(offers.single.trust.lookalike?.fingerprint, alice.fingerprint);
    });
  });

  group('limits', () {
    test('offers are rate-limited per address', () async {
      await r.close();
      r = await TestReceiver.start(
        identity: receiver,
        limits: const ServerLimits(offerBurst: 3, authBurst: 1000),
      );
      r.decider = (_) => Completer<bool>().future;
      final codes = <int>[];
      for (final who in [alice, mallory, receiver, alice]) {
        // Different senders from the same address share the bucket.
        final other = who == receiver
            ? await DeviceCredentials.generate()
            : who;
        final (code, body) = await send(
          'POST',
          '/v1/sessions',
          json: offer(),
          token: await tokenFor(other),
        );
        codes.add(code);
        if (code == 429) {
          expect(body['error'], ErrorCodes.rateLimited);
          expect(body['retryAfter'], greaterThan(0));
        }
      }
      expect(codes.take(3).every((c) => c != 429), isTrue, reason: '$codes');
      expect(codes.last, 429);
    });

    test('authentication is rate-limited per address', () async {
      await r.close();
      r = await TestReceiver.start(
        identity: receiver,
        limits: const ServerLimits(authBurst: 4),
      );
      // Each authentication costs two requests (challenge and proof).
      await tokenFor(alice);
      await tokenFor(alice);
      await expectLater(
        tokenFor(alice),
        throwsA(
          isA<HttpException>().having(
            (e) => e.message,
            'm',
            '429 rate_limited',
          ),
        ),
      );
    });

    test('oversized headers get 431', () async {
      final (code, body) = await send(
        'GET',
        '/v1/info',
        headers: {'x-junk': 'a' * (20 * 1024)},
      );
      expect(code, 431);
      expect(body['error'], ErrorCodes.headersTooLarge);
    });

    test('oversized auth bodies get 413', () async {
      final (code, body) = await send(
        'POST',
        '/v1/auth/challenge',
        json: {'commit': 'a' * (17 * 1024)},
      );
      expect(code, 413);
      expect(body['error'], ErrorCodes.bodyTooLarge);
    });
  });

  test('an UploadClient pinned to another fingerprint never reaches the '
      'server', () async {
    final client = UploadClient(
      host: '127.0.0.1',
      port: r.port,
      fingerprint: mallory.fingerprint,
      credentials: alice,
      connectTimeout: const Duration(seconds: 2),
      stallTimeout: const Duration(seconds: 2),
    );
    addTearDown(client.close);
    await expectLater(
      client.info(),
      throwsA(
        isA<UploadException>().having((e) => e.code, 'code', pinMismatchCode),
      ),
    );
  });
}
