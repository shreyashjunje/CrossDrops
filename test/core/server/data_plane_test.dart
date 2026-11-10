// D-071 on the receiver: data lane isolates, striped uploads and the tree
// hash, over raw HTTPS. No phones needed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crossdrop/core/engine/tree_hash.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/device_credentials.dart';
import 'package:crossdrop/core/server/receive_server.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_receiver.dart';

const int kb = 1024;

void main() {
  late DeviceCredentials identity;
  late DeviceCredentials sender;
  late TestReceiver r;
  late HttpClient http;
  String? token;

  setUpAll(() async {
    identity = await DeviceCredentials.generate();
    sender = await testSenderCredentials();
  });

  Future<void> start({int lanes = ReceiveServer.maxParallelUploads}) async {
    r = await TestReceiver.start(
      identity: identity,
      bodyIdleTimeout: const Duration(seconds: 2),
      dataLanes: lanes,
    );
    token = null;
  }

  setUp(() {
    http = HttpClient()..badCertificateCallback = (_, _, _) => true;
  });

  tearDown(() async {
    http.close(force: true);
    await r.close();
  });

  Future<String> auth() async => token ??= await authenticateRaw(
    r.port,
    sender,
    receiverFingerprint: identity.fingerprint,
  );

  Future<(int, Map<String, Object?>)> send(
    String method,
    String path, {
    int? port,
    Object? json,
    List<int>? bytes,
    int? declared,
    bool authenticated = true,
  }) async {
    final req = await http.openUrl(
      method,
      Uri.parse('https://127.0.0.1:${port ?? r.port}$path'),
    );
    if (authenticated) {
      req.headers.set('authorization', 'Bearer ${await auth()}');
    }
    if (json != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(json));
    } else if (bytes != null) {
      req.contentLength = declared ?? bytes.length;
      req.add(bytes);
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return (res.statusCode, jsonDecode(text) as Map<String, Object?>);
  }

  /// Offers one file and waits until the receiver accepted.
  Future<String> offer(int size) async {
    final (code, body) = await send(
      'POST',
      '/v1/sessions',
      json: SessionOffer(
        sender: testSender,
        files: [FileOffer(fileId: 'f1', name: 'a.bin', size: size)],
      ).toJson(),
    );
    expect(code, 200, reason: '$body');
    final sid = body['sessionId']! as String;
    await waitFor(() => r.events.whereType<SessionStateChanged>().isNotEmpty);
    return sid;
  }

  Future<int> receivedBytes(String sid) async {
    final (_, body) = await send('GET', '/v1/sessions/$sid/files/f1');
    return body['receivedBytes']! as int;
  }

  /// Sends [sent] of [declared] bytes on a raw socket to [port], then
  /// drops it: a Wi-Fi drop mid-upload.
  Future<void> partialPut(
    int port,
    String path,
    List<int> sent,
    int declared,
  ) async {
    final socket = await SecureSocket.connect(
      '127.0.0.1',
      port,
      onBadCertificate: (_) => true,
    );
    socket.write(
      'PUT $path HTTP/1.1\r\nhost: 127.0.0.1\r\n'
      'authorization: Bearer ${await auth()}\r\n'
      'content-length: $declared\r\n'
      'content-type: application/octet-stream\r\n\r\n',
    );
    socket.add(sent);
    await socket.flush();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    socket.destroy();
  }

  Uint8List randomBytes(int n) {
    final rnd = Random(11);
    return Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));
  }

  String shaOf(List<int> data) => sha256.convert(data).toString();

  String treeOf(Uint8List data) {
    final leaves = BytesBuilder();
    for (var at = 0; at < data.length; at += treeLeafBytes) {
      final end = min(at + treeLeafBytes, data.length);
      leaves.add(sha256.convert(Uint8List.sublistView(data, at, end)).bytes);
    }
    return shaOf(leaves.takeBytes());
  }

  Future<void> expectSaved(Uint8List data) async {
    await waitFor(() => r.saved.isNotEmpty);
    expect(await File(r.saved.single.savedPath).readAsBytes(), data);
  }

  /// The bytes connection [s] carries of [data] from [offset].
  Uint8List stripeBytes(Uint8List data, int offset, StripeSpec s) {
    final out = BytesBuilder();
    for (final range in s.ranges(offset, data.length)) {
      out.add(Uint8List.sublistView(data, range.start, range.end));
    }
    return out.takeBytes();
  }

  String stripePath(String sid, int offset, StripeSpec s) =>
      '/v1/sessions/$sid/files/f1?offset=$offset&stripe=${s.index}'
      '&stripes=${s.count}&block=${s.block}';

  group('data lanes', () {
    setUp(start);

    test('info lists the data ports, stripes and the tree hash', () async {
      final (_, body) = await send('GET', '/v1/info', authenticated: false);
      final info = DeviceInfo.fromJson(body);
      expect(info.dataPorts, hasLength(ReceiveServer.maxParallelUploads));
      expect(info.dataPorts.toSet(), isNot(contains(r.port)));
      expect(info.stripes, ReceiveServer.maxStripes);
      expect(info.treeHash, isTrue);
    });

    test('a file sent to a data port is saved unchanged', () async {
      final data = randomBytes(3 * mb + 123);
      final sid = await offer(data.length);
      final port = r.server.dataPorts.first;
      final (code, body) = await send(
        'PUT',
        '/v1/sessions/$sid/files/f1?offset=0',
        port: port,
        bytes: data,
      );
      expect(code, 200, reason: '$body');
      expect(body['receivedBytes'], data.length);
      final (done, _) = await send(
        'POST',
        '/v1/sessions/$sid/files/f1/complete',
        json: {'sha256': shaOf(data)},
      );
      expect(done, 200);
      await expectSaved(data);
    });

    test('a data port takes only authenticated uploads', () async {
      final sid = await offer(10);
      final port = r.server.dataPorts.first;
      final path = '/v1/sessions/$sid/files/f1?offset=0';
      final (noToken, body) = await send(
        'PUT',
        path,
        port: port,
        bytes: List.filled(10, 1),
        authenticated: false,
      );
      expect(noToken, 401);
      expect(body['error'], ErrorCodes.authRequired);
      final (get, _) = await send('GET', '/v1/info', port: port);
      expect(get, 404);
      final (unknown, _) = await send(
        'PUT',
        '/v1/sessions/nope/files/f1?offset=0',
        port: port,
        bytes: [1],
      );
      expect(unknown, 404);
      expect(await receivedBytes(sid), 0);
    });

    test('more bytes than offered are refused on a data port too', () async {
      final sid = await offer(100);
      final (code, body) = await send(
        'PUT',
        '/v1/sessions/$sid/files/f1?offset=0',
        port: r.server.dataPorts.first,
        bytes: List.filled(101, 7),
      );
      expect(code, 413);
      expect(body['error'], ErrorCodes.tooManyBytes);
    });

    test('a drop keeps what arrived; another port resumes', () async {
      final data = randomBytes(4 * mb);
      final sid = await offer(data.length);
      final ports = r.server.dataPorts;
      await partialPut(
        ports[0],
        '/v1/sessions/$sid/files/f1?offset=0',
        data.sublist(0, 2 * mb + 500),
        data.length,
      );
      late int kept;
      await waitFor(() => !r.server.isReceiving);
      kept = await receivedBytes(sid);
      expect(kept, greaterThan(0));
      expect(kept, lessThanOrEqualTo(2 * mb + 500));
      final (code, _) = await send(
        'PUT',
        '/v1/sessions/$sid/files/f1?offset=$kept',
        port: ports[1],
        bytes: data.sublist(kept),
      );
      expect(code, 200);
      final (done, _) = await send(
        'POST',
        '/v1/sessions/$sid/files/f1/complete',
        json: {'sha256': shaOf(data)},
      );
      expect(done, 200);
      await expectSaved(data);
    });

    test('closing the server ends an upload on a data port', () async {
      final data = randomBytes(mb);
      final sid = await offer(data.length);
      final socket = await SecureSocket.connect(
        '127.0.0.1',
        r.server.dataPorts.first,
        onBadCertificate: (_) => true,
      );
      socket.done.ignore();
      socket.write(
        'PUT /v1/sessions/$sid/files/f1?offset=0 HTTP/1.1\r\n'
        'host: 127.0.0.1\r\nauthorization: Bearer ${await auth()}\r\n'
        'content-length: ${data.length}\r\n\r\n',
      );
      socket.add(data.sublist(0, 300 * kb));
      await socket.flush();
      await waitFor(() => r.server.isReceiving);
      await r.server.close().timeout(const Duration(seconds: 10));
      expect(r.server.isReceiving, isFalse);
      socket.destroy();
    });
  });

  for (final lanes in [0, 3]) {
    group('striped uploads, ${lanes == 0 ? 'main port' : 'data ports'}', () {
      setUp(() => start(lanes: lanes));

      int portFor(int i) => lanes == 0 ? r.port : r.server.dataPorts[i];

      test('three connections, one file, bytes in order', () async {
        final data = randomBytes(1 * mb + 77);
        final sid = await offer(data.length);
        final replies = await Future.wait([
          for (var i = 0; i < 3; i++)
            () {
              final s = StripeSpec(index: i, count: 3, block: 64 * kb);
              return send(
                'PUT',
                stripePath(sid, 0, s),
                port: portFor(i),
                bytes: stripeBytes(data, 0, s),
              );
            }(),
        ]);
        for (final (code, body) in replies) {
          expect(code, 200, reason: '$body');
          expect(body['receivedBytes'], data.length);
        }
        final (done, _) = await send(
          'POST',
          '/v1/sessions/$sid/files/f1/complete',
          json: {'sha256': shaOf(data)},
        );
        expect(done, 200);
        await expectSaved(data);
      });

      test('resumed from an offset in the middle of a block', () async {
        final data = randomBytes(1 * mb);
        final sid = await offer(data.length);
        const head = 100 * kb + 3;
        final (first, _) = await send(
          'PUT',
          '/v1/sessions/$sid/files/f1?offset=0',
          bytes: data.sublist(0, head),
          declared: head,
        );
        // A PUT may bring less than the rest; the file is just not done.
        expect(first, 200);
        expect(await receivedBytes(sid), head);
        final replies = await Future.wait([
          for (var i = 0; i < 2; i++)
            () {
              final s = StripeSpec(index: i, count: 2, block: 64 * kb);
              return send(
                'PUT',
                stripePath(sid, head, s),
                port: portFor(i),
                bytes: stripeBytes(data, head, s),
              );
            }(),
        ]);
        expect([for (final (code, _) in replies) code], [200, 200]);
        final (done, _) = await send(
          'POST',
          '/v1/sessions/$sid/files/f1/complete',
          json: {'sha256': shaOf(data)},
        );
        expect(done, 200);
        await expectSaved(data);
      });

      test(
        'a missing connection: a whole prefix is kept, resume works',
        () async {
          final data = randomBytes(1 * mb);
          final sid = await offer(data.length);
          // Connections 0 and 2 come, 1 never does.
          final replies = await Future.wait([
            for (final i in [0, 2])
              () {
                final s = StripeSpec(index: i, count: 3, block: 64 * kb);
                return send(
                  'PUT',
                  stripePath(sid, 0, s),
                  port: portFor(i),
                  bytes: stripeBytes(data, 0, s),
                ).then<(int, Map<String, Object?>)?>(
                  (v) => v,
                  // The server may close before the reply is read.
                  onError: (Object _) => null,
                );
              }(),
          ]);
          for (final reply in replies) {
            if (reply == null) continue;
            expect(reply.$1, 400);
            expect(reply.$2['error'], ErrorCodes.incomplete);
          }
          await waitFor(() => !r.server.isReceiving);
          // Only block 0 could be written before connection 1's turn.
          final kept = await receivedBytes(sid);
          expect(kept, 64 * kb);
          final (code, _) = await send(
            'PUT',
            '/v1/sessions/$sid/files/f1?offset=$kept',
            bytes: data.sublist(kept),
          );
          expect(code, 200);
          final (done, _) = await send(
            'POST',
            '/v1/sessions/$sid/files/f1/complete',
            json: {'sha256': shaOf(data)},
          );
          expect(done, 200);
          await expectSaved(data);
        },
      );

      test('a connection that drops ends the upload at a prefix', () async {
        final data = randomBytes(2 * mb);
        final sid = await offer(data.length);
        const s0 = StripeSpec(index: 0, count: 2, block: 64 * kb);
        const s1 = StripeSpec(index: 1, count: 2, block: 64 * kb);
        final whole = send(
          'PUT',
          stripePath(sid, 0, s0),
          port: portFor(0),
          bytes: stripeBytes(data, 0, s0),
        ).then<int?>((v) => v.$1, onError: (Object _) => null);
        final part = stripeBytes(data, 0, s1);
        await partialPut(
          portFor(1),
          stripePath(sid, 0, s1),
          part.sublist(0, 300 * kb),
          part.length,
        );
        expect(await whole, anyOf(isNull, 400));
        await waitFor(() => !r.server.isReceiving);
        final kept = await receivedBytes(sid);
        expect(kept, greaterThan(0));
        expect(kept, lessThan(data.length));
        final (code, _) = await send(
          'PUT',
          '/v1/sessions/$sid/files/f1?offset=$kept',
          bytes: data.sublist(kept),
        );
        expect(code, 200);
        final (done, _) = await send(
          'POST',
          '/v1/sessions/$sid/files/f1/complete',
          json: {'sha256': shaOf(data)},
        );
        expect(done, 200);
        await expectSaved(data);
      });

      test('bad stripe requests are refused before any byte', () async {
        final data = randomBytes(1 * mb);
        final sid = await offer(data.length);
        final base = '/v1/sessions/$sid/files/f1?offset=0';
        Future<int> put(String query, int length) async => (await send(
          'PUT',
          '$base$query',
          port: portFor(0),
          bytes: Uint8List(length),
        )).$1;

        const ok = StripeSpec(index: 0, count: 2, block: 64 * kb);
        final share = ok.share(data.length);
        // Too many connections, a block out of range, an index out of range.
        expect(await put('&stripe=0&stripes=4&block=65536', share), 400);
        expect(await put('&stripe=0&stripes=2&block=100', share), 400);
        expect(await put('&stripe=2&stripes=2&block=65536', share), 400);
        expect(await put('&stripe=0&stripes=2', share), 400);
        // A length that is not this connection's share (hard rule 6).
        expect(await put('&stripe=0&stripes=2&block=65536', share + 1), 400);
        // Fewer bytes left than one block each.
        expect(await put('&stripe=0&stripes=3&block=4194304', 1), 400);
        expect(await receivedBytes(sid), 0);
      });
    });
  }

  group('tree hash', () {
    setUp(() => start(lanes: 0));

    Future<String> upload(Uint8List data, {required bool tree}) async {
      final sid = await offer(data.length);
      final (code, _) = await send(
        'PUT',
        '/v1/sessions/$sid/files/f1?offset=0${tree ? '&hash=tree' : ''}',
        bytes: data,
      );
      expect(code, 200);
      return sid;
    }

    test('an upload with hash=tree is checked by the root', () async {
      final data = randomBytes(2 * mb + 99);
      final sid = await upload(data, tree: true);
      final (code, _) = await send(
        'POST',
        '/v1/sessions/$sid/files/f1/complete',
        json: {'sha256t': treeOf(data)},
      );
      expect(code, 200);
      await expectSaved(data);
    });

    test('a wrong root resets the file', () async {
      final data = randomBytes(2 * mb);
      final sid = await upload(data, tree: true);
      final (code, body) = await send(
        'POST',
        '/v1/sessions/$sid/files/f1/complete',
        // The plain SHA-256 is not the root.
        json: {'sha256t': shaOf(data)},
      );
      expect(code, 422);
      expect(body['error'], ErrorCodes.hashMismatch);
      expect(await receivedBytes(sid), 0);
    });

    test('the other kind of hash is computed from the file', () async {
      final data = randomBytes(mb + 5);
      var sid = await upload(data, tree: true);
      var (code, _) = await send(
        'POST',
        '/v1/sessions/$sid/files/f1/complete',
        json: {'sha256': shaOf(data)},
      );
      expect(code, 200);
      await expectSaved(data);

      await r.close();
      await start(lanes: 0);
      sid = await upload(data, tree: false);
      (code, _) = await send(
        'POST',
        '/v1/sessions/$sid/files/f1/complete',
        json: {'sha256t': treeOf(data)},
      );
      expect(code, 200);
      await expectSaved(data);
    });
  });
}
