import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crossdrop/core/protocol/events.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/device_credentials.dart';
import 'package:crossdrop/core/engine/chunked_reader.dart';
import 'package:crossdrop/core/server/file_store.dart';
import 'package:crossdrop/core/server/receive_server.dart';
import 'package:crossdrop/core/storage/transfer_repository.dart';
import 'package:crossdrop/core/storage/trust_repository.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/test_receiver.dart';

void main() {
  late DeviceCredentials identity;
  late DeviceCredentials defaultSender;
  late DeviceCredentials sender;
  late TestReceiver r;
  late HttpClient http;
  String? token;

  setUpAll(() async {
    identity = await DeviceCredentials.generate();
    defaultSender = await testSenderCredentials();
  });

  /// Sends the following requests as another device.
  Future<void> actAs(DeviceCredentials who) async {
    sender = who;
    token = null;
  }

  /// A token for [sender] at the current server (servers forget tokens
  /// when they restart).
  Future<String> auth() async => token ??= await authenticateRaw(
    r.port,
    sender,
    receiverFingerprint: identity.fingerprint,
  );

  /// The auth header line for raw sockets.
  Future<String> authLine() async =>
      'authorization: Bearer ${await auth()}\r\n';

  setUp(() async {
    r = await TestReceiver.start(
      identity: identity,
      bodyIdleTimeout: const Duration(seconds: 2),
    );
    http = HttpClient()..badCertificateCallback = (_, _, _) => true;
    sender = defaultSender;
    token = null;
  });

  tearDown(() async {
    http.close(force: true);
    await r.close();
  });

  Uri url(String path) => Uri.parse('https://127.0.0.1:${r.port}$path');

  Future<(int, Map<String, Object?>)> send(
    String method,
    String path, {
    Object? json,
    List<int>? bytes,
    bool chunked = false,
    bool authenticated = true,
  }) async {
    Future<(int, Map<String, Object?>)> once() async {
      final req = await http.openUrl(method, url(path));
      if (authenticated) {
        req.headers.set('authorization', 'Bearer ${await auth()}');
      }
      if (json != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(json));
      } else if (bytes != null) {
        if (!chunked) req.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      return (res.statusCode, jsonDecode(text) as Map<String, Object?>);
    }

    final first = await once();
    if (!authenticated || first.$2['error'] != ErrorCodes.authRequired) {
      return first;
    }
    token = null; // the server restarted
    return once();
  }

  Map<String, Object?> offerJson(
    List<FileOffer> files, {
    SenderInfo sender = testSender,
  }) => SessionOffer(sender: sender, files: files).toJson();

  Future<SessionStatus> statusOf(String sid) async {
    final (_, body) = await send('GET', '/v1/sessions/$sid');
    return SessionStatusReply.fromJson(body).status;
  }

  /// Offers files and waits until the (auto-accepting) receiver accepts.
  Future<String> createSession(
    String name,
    int size, {
    List<FileOffer>? files,
    SenderInfo sender = testSender,
  }) async {
    final (code, body) = await send(
      'POST',
      '/v1/sessions',
      json: offerJson(
        files ?? [FileOffer(fileId: 'f1', name: name, size: size)],
        sender: sender,
      ),
    );
    expect(code, 200, reason: '$body');
    expect(body['status'], 'offered');
    final sid = body['sessionId']! as String;
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (await statusOf(sid) == SessionStatus.offered) {
      if (DateTime.now().isAfter(end)) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return sid;
  }

  Future<List<SessionEvent>> collectEvents(
    String sid,
    int count, {
    Future<void> Function()? during,
  }) async {
    final ws = await WebSocket.connect(
      'wss://127.0.0.1:${r.port}/v1/sessions/$sid/events',
      headers: {'authorization': 'Bearer ${await auth()}'},
      customClient: http,
    );
    final got = <SessionEvent>[];
    final done = Completer<void>();
    ws.listen(
      (m) {
        final e = SessionEvent.fromJson(jsonDecode(m as String));
        if (e != null) got.add(e);
        if (got.length >= count && !done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    await during?.call();
    await done.future.timeout(const Duration(seconds: 10));
    await ws.close();
    return got;
  }

  /// Sends [sent] of [declared] bytes on a raw TLS socket, then drops it:
  /// a Wi-Fi drop mid-upload.
  Future<void> partialPut(String path, List<int> sent, int declared) async {
    final socket = await SecureSocket.connect(
      '127.0.0.1',
      r.port,
      onBadCertificate: (_) => true,
    );
    final authHeader = await authLine();
    socket.write(
      'PUT $path HTTP/1.1\r\nhost: 127.0.0.1\r\n$authHeader'
      'content-length: $declared\r\n'
      'content-type: application/octet-stream\r\n\r\n',
    );
    socket.add(sent);
    await socket.flush();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    socket.destroy();
  }

  Uint8List randomBytes(int n) {
    final rnd = Random(7);
    return Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));
  }

  String shaOf(List<int> data) => sha256.convert(data).toString();

  test('isListening: true while serving, a probe does not hurt it', () async {
    // Review M6: the app probes after iOS may have reclaimed the socket.
    expect(await r.server.isListening(), isTrue);
    expect(await r.server.isListening(), isTrue);
    final (code, _) = await send('GET', '/v1/info');
    expect(code, 200);
  });

  test('isListening: false once the socket is gone', () async {
    final port = r.port;
    await r.server.close();
    expect(await r.server.isListening(), isFalse);
    // Nothing answers on the old port either.
    await expectLater(
      Socket.connect('127.0.0.1', port, timeout: const Duration(seconds: 2)),
      throwsA(isA<SocketException>()),
    );
    // tearDown closes again; the server must allow that.
  });

  test('GET /v1/info returns id, name, platform and versions', () async {
    final (code, body) = await send('GET', '/v1/info');
    expect(code, 200);
    final info = DeviceInfo.fromJson(body);
    expect(info.id, testDeviceInfo.id);
    expect(info.versions, supportedVersions);
  });

  group('offer and accept', () {
    test('POST returns offered; bytes are refused until Accept', () async {
      final decision = Completer<bool>();
      r.decider = (_) => decision.future;
      final (code, body) = await send(
        'POST',
        '/v1/sessions',
        json: offerJson([const FileOffer(fileId: 'f1', name: 'a', size: 3)]),
      );
      expect(code, 200);
      expect(body['status'], 'offered');
      final sid = body['sessionId']! as String;
      expect(r.events.whereType<SessionOffered>().single.sessionId, sid);

      final (put, err) = await send(
        'PUT',
        '/v1/sessions/$sid/files/f1?offset=0',
        bytes: [1, 2, 3],
      );
      expect(put, 403);
      expect(err['error'], ErrorCodes.notAccepted);

      final events = collectEvents(
        sid,
        1,
        during: () async => decision.complete(true),
      );
      expect((await events).single, isA<AcceptedEvent>());
      expect(await statusOf(sid), SessionStatus.accepted);
    });

    test('decline sends rejected and closes the session', () async {
      r.decider = (_) async => false;
      final sid = await createSession('a', 3);
      expect(await statusOf(sid), SessionStatus.rejected);
      final events = await collectEvents(sid, 1);
      expect((events.single as RejectedEvent).reason, RejectReasons.declined);
      final (code, body) = await send(
        'PUT',
        '/v1/sessions/$sid/files/f1?offset=0',
        bytes: [1, 2, 3],
      );
      expect(code, 410);
      expect(body['error'], ErrorCodes.sessionClosed);
    });

    test('no answer within the accept timeout rejects with timeout', () async {
      await r.close();
      r = await TestReceiver.start(
        identity: identity,
        acceptTimeout: const Duration(milliseconds: 200),
        decider: (_) => Completer<bool>().future,
      );
      final sid = await createSession('a', 3);
      final reply = SessionStatusReply.fromJson(
        (await send('GET', '/v1/sessions/$sid')).$2,
      );
      expect(reply.status, SessionStatus.rejected);
      expect(reply.reason, RejectReasons.timeout);
    });

    test('not enough free space is refused before the prompt', () async {
      r.freeBytes = 10 * mb;
      var asked = false;
      r.decider = (_) async => asked = true;
      final (code, body) = await send(
        'POST',
        '/v1/sessions',
        json: offerJson([
          FileOffer(fileId: 'f1', name: 'big.mov', size: 20 * mb),
        ]),
      );
      expect(code, 507);
      expect(body['error'], ErrorCodes.noSpace);
      expect(body['neededBytes'], 20 * mb);
      expect(asked, isFalse);
      expect(r.events.whereType<OfferRefused>().single.reason, 'no_space');
    });

    test('sizes that wrap a 64-bit sum never reach the prompt', () async {
      // Review H2: 4 * 2^62 + 1 KB summed to 1 KB and passed the space
      // check; after Accept the sender could fill the disk.
      r.freeBytes = 1000 * mb;
      var asked = false;
      r.decider = (_) async => asked = true;
      final (code, body) = await send(
        'POST',
        '/v1/sessions',
        json: offerJson([
          for (var i = 0; i < 4; i++)
            FileOffer(fileId: 'f$i', name: 'x$i', size: 1 << 62),
          const FileOffer(fileId: 'f4', name: 'small', size: 1024),
        ]),
      );
      expect(code, 400);
      expect(body['error'], ErrorCodes.badRequest);
      expect(asked, isFalse);
      expect(r.server.sessions, isEmpty);
    });

    test('the prompt and history show names as they will be saved', () async {
      // Review L8: a RIGHT-TO-LEFT OVERRIDE made an .exe look like .jpg.
      IncomingOffer? asked;
      r.decider = (o) async {
        asked = o;
        return false;
      };
      final (_, body) = await send(
        'POST',
        '/v1/sessions',
        json: offerJson(
          [
            const FileOffer(
              fileId: 'f1',
              name: 'x/photo\u202Egpj.exe',
              size: 1,
            ),
          ],
          sender: const SenderInfo(
            id: 'a',
            name: 'Pixel\u202E\u0000',
            platform: 'android',
          ),
        ),
      );
      final sid = body['sessionId']! as String;
      await waitFor(() => asked != null);
      expect(asked!.files.single.name, 'photogpj.exe');
      expect(asked!.sender.name, 'Pixel');
      final offered = r.events.whereType<SessionOffered>().single;
      expect(offered.files.single.name, 'photogpj.exe');
      final stored = await r.repo.find(sid, TransferDirection.receive);
      expect(stored!.files.single.name, 'photogpj.exe');
    });

    test('free space is checked again when the user accepts', () async {
      r.freeBytes = 1000 * mb;
      final decision = Completer<bool>();
      r.decider = (_) => decision.future;
      final (_, body) = await send(
        'POST',
        '/v1/sessions',
        json: offerJson([
          FileOffer(fileId: 'f1', name: 'big.mov', size: 500 * mb),
        ]),
      );
      final sid = body['sessionId']! as String;
      r.freeBytes = 100 * mb; // filled up while the prompt was open
      decision.complete(true);
      await waitFor(() => r.server.sessions.single.status.isTerminal);
      final reply = SessionStatusReply.fromJson(
        (await send('GET', '/v1/sessions/$sid')).$2,
      );
      expect(reply.status, SessionStatus.rejected);
      expect(reply.reason, RejectReasons.noSpace);
    });

    test('one unfinished session per sender', () async {
      await createSession('a', 10);
      final (code, body) = await send(
        'POST',
        '/v1/sessions',
        json: offerJson([const FileOffer(fileId: 'f1', name: 'b', size: 1)]),
      );
      expect(code, 409);
      expect(body['error'], ErrorCodes.senderBusy);
      // Claiming another id does not help: the sender is its fingerprint.
      final (code2, _) = await send(
        'POST',
        '/v1/sessions',
        json: offerJson([
          const FileOffer(fileId: 'f1', name: 'b', size: 1),
        ], sender: const SenderInfo(id: 'other', name: 'x', platform: 'ios')),
      );
      expect(code2, 409);
      // Another device (another key) is fine.
      await actAs(await DeviceCredentials.generate());
      await createSession('c', 1);
    });

    test('a finished session frees the sender', () async {
      final sid = await createSession('a', 0);
      await send(
        'POST',
        '/v1/sessions/$sid/files/f1/complete',
        json: {'sha256': shaOf(const [])},
      );
      expect(await statusOf(sid), SessionStatus.done);
      await createSession('b', 0);
    });

    test('unsupported protocol version and bad offers', () async {
      var (code, body) = await send(
        'POST',
        '/v1/sessions',
        json: {
          ...offerJson([]),
          'protocol': 99,
          'files': [
            {'fileId': 'f1', 'name': 'a', 'size': 1},
          ],
        },
      );
      expect(code, 400);
      expect(body['error'], ErrorCodes.unsupportedVersion);
      expect(body['versions'], supportedVersions);
      (code, body) = await send('POST', '/v1/sessions', json: {'protocol': 1});
      expect(code, 400);
      expect(body['error'], ErrorCodes.badRequest);
      (code, body) = await send('GET', '/v1/sessions/nope/files/f1');
      expect(code, 404);
    });

    test('too many open sessions get 503', () async {
      r.decider = (_) => Completer<bool>().future;
      for (var i = 0; i < ReceiveServer.maxOpenSessions; i++) {
        await actAs(await DeviceCredentials.generate());
        final (code, _) = await send(
          'POST',
          '/v1/sessions',
          json: offerJson([
            const FileOffer(fileId: 'f1', name: 'a', size: 1),
          ], sender: SenderInfo(id: 's$i', name: 'x', platform: 'ios')),
        );
        expect(code, 200);
      }
      await actAs(await DeviceCredentials.generate());
      final (code, _) = await send(
        'POST',
        '/v1/sessions',
        json: offerJson([
          const FileOffer(fileId: 'f1', name: 'a', size: 1),
        ], sender: const SenderInfo(id: 'late', name: 'x', platform: 'ios')),
      );
      expect(code, 503);
    });
  });

  group('bytes', () {
    test('full flow: put, status, complete', () async {
      final data = randomBytes(3 * mb + 5);
      final sid = await createSession('photo.jpg', data.length);
      final files = '/v1/sessions/$sid/files/f1';

      var (code, body) = await send('GET', files);
      expect(body['receivedBytes'], 0);
      expect(body['status'], 'pending');

      (code, body) = await send('PUT', '$files?offset=0', bytes: data);
      expect(code, 200);
      expect(body['receivedBytes'], data.length);

      (code, body) = await send(
        'POST',
        '$files/complete',
        json: {'sha256': shaOf(data)},
      );
      expect(code, 200, reason: '$body');
      expect(body['status'], 'saved');

      final saved = File(p.join(r.saveDir, 'photo.jpg'));
      expect(saved.readAsBytesSync(), data);
      expect(Directory(p.join(r.tempDir, sid)).existsSync(), isFalse);
      expect(await statusOf(sid), SessionStatus.done);
      final stored = await r.repo.find(sid, TransferDirection.receive);
      expect(stored!.status, SessionStatus.done);
      expect(stored.files.single.sha256, shaOf(data));
    });

    test('resume in two PUTs gives the right hash', () async {
      final data = randomBytes(2 * mb + 77);
      final sid = await createSession('a.bin', data.length);
      final files = '/v1/sessions/$sid/files/f1';
      const half = mb + 3;
      var (code, _) = await send(
        'PUT',
        '$files?offset=0',
        bytes: data.sublist(0, half),
      );
      expect(code, 200);
      (code, _) = await send(
        'PUT',
        '$files?offset=$half',
        bytes: data.sublist(half),
      );
      expect(code, 200);
      final (c, body) = await send(
        'POST',
        '$files/complete',
        json: {'sha256': shaOf(data)},
      );
      expect(c, 200, reason: '$body');
    });

    test('wrong offset returns 409 with receivedBytes', () async {
      final sid = await createSession('a.bin', 100);
      final files = '/v1/sessions/$sid/files/f1';
      await send('PUT', '$files?offset=0', bytes: List.filled(40, 1));
      final (code, body) = await send(
        'PUT',
        '$files?offset=10',
        bytes: List.filled(10, 1),
      );
      expect(code, 409);
      expect(body['error'], ErrorCodes.offsetMismatch);
      expect(body['receivedBytes'], 40);
    });

    test('Content-Length beyond declared size fails the file', () async {
      final sid = await createSession('a.bin', 10);
      final (code, body) = await send(
        'PUT',
        '/v1/sessions/$sid/files/f1?offset=0',
        bytes: List.filled(11, 1),
      );
      expect(code, 413);
      expect(body['error'], ErrorCodes.tooManyBytes);
      expect(r.events.whereType<FileFailed>().single.code, 'too_many_bytes');
      // The only file failed, so the session failed.
      expect(await statusOf(sid), SessionStatus.failed);
    });

    test(
      'chunked body beyond declared size is stopped; others go on',
      () async {
        final sid = await createSession(
          '',
          0,
          files: const [
            FileOffer(fileId: 'f1', name: 'liar.bin', size: 10),
            FileOffer(fileId: 'f2', name: 'ok.bin', size: 3),
          ],
        );
        final (code, body) = await send(
          'PUT',
          '/v1/sessions/$sid/files/f1?offset=0',
          bytes: List.filled(64, 1),
          chunked: true,
        );
        expect(code, 413);
        expect(body['error'], ErrorCodes.tooManyBytes);
        expect(File(p.join(r.tempDir, sid, 'f1.part')).existsSync(), isFalse);
        final (_, s1) = await send('GET', '/v1/sessions/$sid/files/f1');
        expect(s1['status'], 'failed');

        await send(
          'PUT',
          '/v1/sessions/$sid/files/f2?offset=0',
          bytes: [1, 2, 3],
        );
        final (c2, _) = await send(
          'POST',
          '/v1/sessions/$sid/files/f2/complete',
          json: {
            'sha256': shaOf([1, 2, 3]),
          },
        );
        expect(c2, 200);
        expect(await statusOf(sid), SessionStatus.done);
      },
    );

    test('complete before all bytes arrive returns incomplete', () async {
      final sid = await createSession('a.bin', 100);
      final files = '/v1/sessions/$sid/files/f1';
      await send('PUT', '$files?offset=0', bytes: List.filled(50, 1));
      final (code, body) = await send(
        'POST',
        '$files/complete',
        json: {'sha256': '0' * 64},
      );
      expect(code, 409);
      expect(body['error'], ErrorCodes.incomplete);
      expect(body['receivedBytes'], 50);
    });

    test('hostile names are sanitized and stay in the save folder', () async {
      final names = {
        '../../evil.sh': 'evil.sh',
        r'..\..\win.bat': 'win.bat',
        '/etc/passwd': 'passwd',
        'CON.txt': '_CON.txt',
        'a\u0000b\u001fc.jpg': 'a_b_c.jpg',
        '...': 'file',
        '${'x' * 300}.jpg': '${'x' * 196}.jpg',
      };
      final offers = [
        for (final (i, n) in names.keys.indexed)
          FileOffer(fileId: 'f$i', name: n, size: 1),
      ];
      final sid = await createSession('', 0, files: offers);
      for (final f in offers) {
        await send(
          'PUT',
          '/v1/sessions/$sid/files/${f.fileId}?offset=0',
          bytes: [7],
        );
        final (code, body) = await send(
          'POST',
          '/v1/sessions/$sid/files/${f.fileId}/complete',
          json: {
            'sha256': shaOf([7]),
          },
        );
        expect(code, 200, reason: '${f.name}: $body');
      }
      final savedNames = {for (final e in r.saved) p.basename(e.savedPath)};
      expect(savedNames, names.values.toSet());
      for (final e in r.saved) {
        expect(p.isWithin(r.saveDir, e.savedPath), isTrue);
      }
    });

    test('empty file can be completed without a PUT', () async {
      final sid = await createSession('empty.txt', 0);
      final (code, _) = await send(
        'POST',
        '/v1/sessions/$sid/files/f1/complete',
        json: {'sha256': shaOf(const [])},
      );
      expect(code, 200);
    });

    test('emits progress and saved events', () async {
      final data = randomBytes(2 * mb);
      final sid = await createSession('a.bin', data.length);
      final files = '/v1/sessions/$sid/files/f1';
      await send('PUT', '$files?offset=0', bytes: data);
      await send('POST', '$files/complete', json: {'sha256': shaOf(data)});
      expect(r.events.first, isA<SessionOffered>());
      expect(
        r.events.whereType<FileProgress>().last.receivedBytes,
        data.length,
      );
      expect(r.events.whereType<FileSaved>(), hasLength(1));
    });
  });

  group('complete after its body arrives (review L2)', () {
    /// Sends a complete's headers now; the returned function sends its
    /// body and returns the reply's status line.
    Future<Future<String> Function()> startComplete(String sid) async {
      final body = utf8.encode(jsonEncode({'sha256': shaOf(const [])}));
      final socket = await SecureSocket.connect(
        '127.0.0.1',
        r.port,
        onBadCertificate: (_) => true,
      );
      addTearDown(socket.destroy);
      socket.write(
        'POST /v1/sessions/$sid/files/f1/complete HTTP/1.1\r\n'
        'host: x\r\n${await authLine()}'
        'content-type: application/json\r\n'
        'content-length: ${body.length}\r\n\r\n',
      );
      await socket.flush();
      return () async {
        final reply = utf8.decoder.bind(socket).first;
        socket.add(body);
        await socket.flush();
        return (await reply).split('\r\n').first;
      };
    }

    test('two completes of an empty file save it once', () async {
      // A second file keeps the session open after the first save.
      final sid = await createSession(
        '',
        0,
        files: const [
          FileOffer(fileId: 'f1', name: 'empty.txt', size: 0),
          FileOffer(fileId: 'f2', name: 'later.bin', size: 1),
        ],
      );
      final first = await startComplete(sid);
      final second = await startComplete(sid);
      // Both handlers now wait for their bodies.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await first(), contains('200'));
      expect(await second(), contains('409'), reason: 'already saved');
      expect(r.saved, hasLength(1));
    });

    test('a cancel while the body is on its way leaves nothing', () async {
      final sid = await createSession('empty.txt', 0);
      final complete = await startComplete(sid);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await send('DELETE', '/v1/sessions/$sid');
      expect(await complete(), contains('410'));
      expect(r.saved, isEmpty);
      expect(Directory(p.join(r.tempDir, sid)).existsSync(), isFalse);
    });
  });

  group('hash mismatch', () {
    test('first mismatch restarts the file, second fails it', () async {
      final data = randomBytes(1000);
      final sid = await createSession('a.bin', data.length);
      final files = '/v1/sessions/$sid/files/f1';

      await send('PUT', '$files?offset=0', bytes: data);
      var (code, body) = await send(
        'POST',
        '$files/complete',
        json: {'sha256': '0' * 64},
      );
      expect(code, 422);
      expect(body['error'], ErrorCodes.hashMismatch);
      expect(body['retry'], isTrue);
      expect(Directory(r.saveDir).listSync(), isEmpty);
      final (_, status) = await send('GET', files);
      expect(status['receivedBytes'], 0);
      expect(status['status'], 'receiving');

      await send('PUT', '$files?offset=0', bytes: data);
      (code, body) = await send(
        'POST',
        '$files/complete',
        json: {'sha256': '0' * 64},
      );
      expect(code, 422);
      expect(body['error'], ErrorCodes.fileFailed);
      expect(body['retry'], isFalse);
      expect(await statusOf(sid), SessionStatus.failed);
      final stored = await r.repo.find(sid, TransferDirection.receive);
      expect(stored!.files.single.hashAttempts, 2);
      expect(stored.files.single.status, FileTransferStatus.failed);
    });

    test('a retry after one mismatch can succeed', () async {
      final data = randomBytes(1000);
      final sid = await createSession('a.bin', data.length);
      final files = '/v1/sessions/$sid/files/f1';
      await send('PUT', '$files?offset=0', bytes: data);
      await send('POST', '$files/complete', json: {'sha256': '0' * 64});
      await send('PUT', '$files?offset=0', bytes: data);
      final (code, _) = await send(
        'POST',
        '$files/complete',
        json: {'sha256': shaOf(data)},
      );
      expect(code, 200);
      expect(await statusOf(sid), SessionStatus.done);
    });
  });

  group('memory and limits (review M1, M2, L3)', () {
    Future<TestReceiver> withClock() async {
      await r.close();
      return r = await TestReceiver.start(
        identity: identity,
        bodyIdleTimeout: const Duration(seconds: 2),
        fakeClock: true,
      );
    }

    Future<String> offerAndWithdraw() async {
      r.decider = (_) => Completer<bool>().future;
      final (_, body) = await send(
        'POST',
        '/v1/sessions',
        json: offerJson([const FileOffer(fileId: 'f1', name: 'a', size: 3)]),
      );
      final sid = body['sessionId']! as String;
      await send('DELETE', '/v1/sessions/$sid');
      return sid;
    }

    test(
      'an offer never accepted is forgotten and leaves the database',
      () async {
        await withClock();
        final sid = await offerAndWithdraw();
        expect(r.server.sessions, hasLength(1));
        await r.server.prune();
        expect(r.server.sessions, hasLength(1), reason: 'kept for 5 minutes');
        r.now = r.now.add(const Duration(minutes: 6));
        await r.server.prune();
        expect(r.server.sessions, isEmpty);
        expect(await r.repo.find(sid, TransferDirection.receive), isNull);
        expect((await send('GET', '/v1/sessions/$sid')).$1, 404);
      },
    );

    test('an accepted session that ended stays in history', () async {
      await withClock();
      final sid = await createSession('a', 0);
      await send(
        'POST',
        '/v1/sessions/$sid/files/f1/complete',
        json: {'sha256': shaOf(const [])},
      );
      r.now = r.now.add(const Duration(minutes: 6));
      await r.server.prune();
      expect(r.server.sessions, isEmpty);
      final stored = await r.repo.find(sid, TransferDirection.receive);
      expect(stored?.status, SessionStatus.done);
    });

    test('at most maxRetainedSessions ended sessions stay in memory', () async {
      final ids = [
        for (var i = 0; i < ReceiveServer.maxRetainedSessions + 8; i++)
          await offerAndWithdraw(),
      ];
      await r.server.prune();
      expect(
        r.server.sessions.length,
        lessThanOrEqualTo(ReceiveServer.maxRetainedSessions),
      );
      // The oldest went first, with their rows.
      await waitFor(
        () => r.server.sessions.every((s) => s.sessionId != ids.first),
      );
      expect(await r.repo.find(ids.first, TransferDirection.receive), isNull);
      expect(await r.repo.find(ids.last, TransferDirection.receive), isNotNull);
    });

    test('a paused session expires after 24 h without activity', () async {
      await withClock();
      final sid = await createSession('a.bin', 10 * mb);
      await partialPut('/v1/sessions/$sid/files/f1?offset=0', [
        1,
        2,
        3,
      ], 10 * mb);
      await waitFor(
        () => r.server.sessions.single.status == SessionStatus.paused,
      );
      r.now = r.now.add(const Duration(hours: 23));
      await r.server.prune();
      expect(r.server.sessions.single.status, SessionStatus.paused);
      r.now = r.now.add(const Duration(hours: 2));
      await r.server.prune();
      final s = r.server.sessions.single;
      expect(s.status, SessionStatus.failed);
      expect(s.reason, 'expired');
      expect(Directory(p.join(r.tempDir, sid)).existsSync(), isFalse);
    });

    test('parallel offers from one sender: only one gets through', () async {
      // Review L3: the checks ran before any await and the session was
      // stored after several, so parallel offers all passed.
      await auth();
      final gate = Completer<void>();
      r.decider = (_) => Completer<bool>().future;
      r.trustLookup = (_, _) async {
        await gate.future;
        return PeerTrust.unknown;
      };
      final offers = [
        for (var i = 0; i < 5; i++)
          send(
            'POST',
            '/v1/sessions',
            json: offerJson([FileOffer(fileId: 'f1', name: 'a$i', size: 3)]),
          ),
      ];
      await waitFor(() => r.server.sessions.isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      gate.complete();
      final codes = [for (final (code, _) in await Future.wait(offers)) code];
      expect(codes.where((c) => c == 200), hasLength(1), reason: '$codes');
      expect(codes.where((c) => c == 409), hasLength(4), reason: '$codes');
      expect(r.server.sessions, hasLength(1));
    });

    test('one running hash per session, however the sender hops', () async {
      // Review M2: a PUT that ended short kept its hash isolate, one per
      // file; 10,000 files gave 10,000 isolates.
      final data = randomBytes(10);
      final sid = await createSession(
        '',
        0,
        files: [
          for (var i = 1; i <= 4; i++)
            FileOffer(fileId: 'f$i', name: 'f$i.bin', size: data.length),
        ],
      );
      for (var i = 1; i <= 4; i++) {
        final (code, _) = await send(
          'PUT',
          '/v1/sessions/$sid/files/f$i?offset=0',
          bytes: data.sublist(0, 4),
        );
        expect(code, 200);
        expect(r.server.liveHashes, 1);
      }
      // f1 lost its running hash; it is hashed from disk at the end.
      await send(
        'PUT',
        '/v1/sessions/$sid/files/f1?offset=4',
        bytes: data.sublist(4),
      );
      final (code, body) = await send(
        'POST',
        '/v1/sessions/$sid/files/f1/complete',
        json: {'sha256': shaOf(data)},
      );
      expect(code, 200, reason: '$body');
      expect(body['status'], 'saved');
    });
  });

  group('several files at once (D-068)', () {
    test('info advertises uploadSlots', () async {
      final (_, body) = await send('GET', '/v1/info');
      expect(body['uploadSlots'], ReceiveServer.maxParallelUploads);
      expect(
        DeviceInfo.fromJson(body).uploadSlots,
        ReceiveServer.maxParallelUploads,
      );
    });

    test(
      'uploads run together and keep their hashes; one more gets 503',
      () async {
        const n = ReceiveServer.maxParallelUploads;
        final data = [
          for (var i = 0; i <= n; i++) randomBytes(256 * 1024 + 17 * i),
        ];
        final sid = await createSession(
          '',
          0,
          files: [
            for (var i = 0; i <= n; i++)
              FileOffer(fileId: 'f$i', name: 'f$i.bin', size: data[i].length),
          ],
        );
        final authHeader = await authLine();
        // n uploads that stay open, each half sent.
        final sockets = <SecureSocket>[];
        for (var i = 0; i < n; i++) {
          final socket = await SecureSocket.connect(
            '127.0.0.1',
            r.port,
            onBadCertificate: (_) => true,
          );
          socket.write(
            'PUT /v1/sessions/$sid/files/f$i?offset=0 HTTP/1.1\r\n'
            'host: 127.0.0.1\r\n$authHeader'
            'content-length: ${data[i].length}\r\n'
            'content-type: application/octet-stream\r\n\r\n',
          );
          socket.add(data[i].sublist(0, data[i].length ~/ 2));
          await socket.flush();
          sockets.add(socket);
        }
        await waitFor(
          () => r.server.liveHashes == n,
          reason: 'one running hash per upload, none dropped',
        );

        final (busy, body) = await send(
          'PUT',
          '/v1/sessions/$sid/files/f$n?offset=0',
          bytes: data[n],
        );
        expect(busy, 503);
        expect(body['error'], ErrorCodes.busy);

        final replies = [
          for (final socket in sockets) utf8.decoder.bind(socket).join(),
        ];
        for (var i = 0; i < n; i++) {
          sockets[i].add(data[i].sublist(data[i].length ~/ 2));
          await sockets[i].flush();
        }
        for (var i = 0; i < n; i++) {
          await waitFor(
            () =>
                r.server.sessions.single.files
                    .firstWhere((f) => f.offer.fileId == 'f$i')
                    .receivedBytes ==
                data[i].length,
          );
          await sockets[i].close();
        }
        for (final reply in replies) {
          expect(await reply, startsWith('HTTP/1.1 200'));
        }
        // The free slot takes the last file now.
        final (late, _) = await send(
          'PUT',
          '/v1/sessions/$sid/files/f$n?offset=0',
          bytes: data[n],
        );
        expect(late, 200);
        for (var i = 0; i <= n; i++) {
          final (code, b) = await send(
            'POST',
            '/v1/sessions/$sid/files/f$i/complete',
            json: {'sha256': shaOf(data[i])},
          );
          expect(code, 200, reason: 'f$i: $b');
        }
        expect(await statusOf(sid), SessionStatus.done);
        expect(r.saved, hasLength(n + 1));
      },
    );
  });

  group('cancel', () {
    test('sender DELETE while offered withdraws the offer', () async {
      r.decider = (_) => Completer<bool>().future;
      final (_, body) = await send(
        'POST',
        '/v1/sessions',
        json: offerJson([const FileOffer(fileId: 'f1', name: 'a', size: 3)]),
      );
      final sid = body['sessionId']! as String;
      final (code, reply) = await send('DELETE', '/v1/sessions/$sid');
      expect(code, 200);
      expect(reply['status'], 'cancelled');
      expect(reply['reason'], 'sender');
    });

    test(
      'sender DELETE after accept: cancelled event, parts deleted',
      () async {
        final sid = await createSession('a.bin', 100);
        await send(
          'PUT',
          '/v1/sessions/$sid/files/f1?offset=0',
          bytes: List.filled(40, 1),
        );
        expect(File(p.join(r.tempDir, sid, 'f1.part')).existsSync(), isTrue);
        final events = collectEvents(
          sid,
          2,
          during: () => send('DELETE', '/v1/sessions/$sid'),
        );
        final got = await events;
        expect(got.last, isA<CancelledEvent>());
        expect((got.last as CancelledEvent).by, 'sender');
        expect(Directory(p.join(r.tempDir, sid)).existsSync(), isFalse);
        final (code, body) = await send('GET', '/v1/sessions/$sid/files/f1');
        expect(code, 410);
        expect(body['status'], 'cancelled');
        // Cancelling again is harmless.
        expect((await send('DELETE', '/v1/sessions/$sid')).$1, 200);
      },
    );

    test('receiver cancel during an upload stops it', () async {
      final sid = await createSession('a.bin', 64 * mb);
      final socket = await SecureSocket.connect(
        '127.0.0.1',
        r.port,
        onBadCertificate: (_) => true,
      );
      addTearDown(socket.destroy);
      socket.write(
        'PUT /v1/sessions/$sid/files/f1?offset=0 HTTP/1.1\r\n'
        'host: x\r\n${await authLine()}content-length: ${64 * mb}\r\n\r\n',
      );
      socket.add(Uint8List(2 * mb));
      await socket.flush();
      await waitFor(() => r.server.isReceiving);
      await waitFor(
        () => r.events.whereType<FileProgress>().isNotEmpty,
        reason: 'first bytes',
      );
      // Keep sending while the receiver cancels.
      final pump = () async {
        for (var i = 0; i < 20; i++) {
          try {
            socket.add(Uint8List(mb));
            await socket.flush();
          } on Object {
            return;
          }
        }
      }();
      await r.server.cancel(sid);
      expect(await statusOf(sid), SessionStatus.cancelled);
      expect(r.server.isReceiving, isFalse);
      expect(Directory(p.join(r.tempDir, sid)).existsSync(), isFalse);
      await pump;
    });

    test('receiver cancel while paused and while offered', () async {
      final sid = await createSession('a.bin', 100);
      await partialPut('/v1/sessions/$sid/files/f1?offset=0', [1, 2], 100);
      await waitFor(
        () => r.server.sessions.single.status == SessionStatus.paused,
      );
      await r.server.cancel(sid);
      expect(await statusOf(sid), SessionStatus.cancelled);

      r.decider = (_) => Completer<bool>().future;
      final (_, body) = await send(
        'POST',
        '/v1/sessions',
        json: offerJson([
          const FileOffer(fileId: 'f1', name: 'a', size: 3),
        ], sender: const SenderInfo(id: 'b', name: 'b', platform: 'ios')),
      );
      final sid2 = body['sessionId']! as String;
      await r.server.cancel(sid2);
      expect(await statusOf(sid2), SessionStatus.rejected);
    });
  });

  group('events socket', () {
    test('a late socket gets the current state first', () async {
      final data = randomBytes(10);
      final sid = await createSession(
        '',
        0,
        files: [
          FileOffer(fileId: 'f1', name: 'a', size: data.length),
          const FileOffer(fileId: 'f2', name: 'b', size: 100),
        ],
      );
      await send('PUT', '/v1/sessions/$sid/files/f1?offset=0', bytes: data);
      await send(
        'POST',
        '/v1/sessions/$sid/files/f1/complete',
        json: {'sha256': shaOf(data)},
      );
      await send(
        'PUT',
        '/v1/sessions/$sid/files/f2?offset=0',
        bytes: List.filled(30, 1),
      );
      final got = await collectEvents(sid, 3);
      expect(got[0], isA<AcceptedEvent>());
      expect((got[1] as FileDoneEvent).fileId, 'f1');
      expect((got[2] as ProgressEvent).receivedBytes, 30);
    });

    test('unknown session gives 404', () async {
      final (code, _) = await send('GET', '/v1/sessions/nope/events');
      expect(code, 404);
    });
  });

  group('reading ahead of the disk (D-064)', () {
    test('the socket is read while a write is stuck, up to a bound', () async {
      final gate = Completer<void>();
      await r.close();
      r = await TestReceiver.start(
        identity: identity,
        bodyIdleTimeout: const Duration(seconds: 5),
        store: (t) => _SlowStore(FolderStore(t.saveDir), gate),
      );
      final data = randomBytes(12 * mb);
      final sid = await createSession('big.bin', data.length);
      final put = send(
        'PUT',
        '/v1/sessions/$sid/files/f1?offset=0',
        bytes: data,
      );
      // The first write waits; the server keeps reading into its queue.
      await waitFor(() => r.server.bufferedBytes >= 6 * mb);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        r.server.bufferedBytes,
        lessThanOrEqualTo(ReceiveServer.receiveQueueBytes + mb),
      );
      gate.complete();
      final (code, body) = await put;
      expect(code, 200, reason: '$body');
      expect(body['receivedBytes'], data.length);
      expect(r.server.bufferedBytes, 0);
      final (done, _) = await send(
        'POST',
        '/v1/sessions/$sid/files/f1/complete',
        json: {'sha256': shaOf(data)},
      );
      expect(done, 200);
      expect(await hashFile(r.saved.single.savedPath), shaOf(data));
    }, timeout: const Timeout(Duration(minutes: 1)));
  });

  group('closing with bytes still queued (D-064)', () {
    test(
      'the writer stops at close and its checkpoint matches the part',
      () async {
        final gate = Completer<void>();
        await r.close();
        r = await TestReceiver.start(
          identity: identity,
          bodyIdleTimeout: const Duration(seconds: 5),
          store: (t) => _SlowStore(FolderStore(t.saveDir), gate),
        );
        final data = randomBytes(12 * mb);
        final sid = await createSession('big.bin', data.length);
        unawaited(
          send(
            'PUT',
            '/v1/sessions/$sid/files/f1?offset=0',
            bytes: data,
          ).then<void>((_) {}, onError: (Object _) {}),
        );
        await waitFor(() => r.server.bufferedBytes >= 6 * mb);
        final closing = r.server.close();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        gate.complete();
        await closing;
        final part = File(p.join(r.tempDir, sid, 'f1.part'));
        final length = part.lengthSync();
        // Not the whole queue: the writer stopped after its current write.
        expect(length, lessThan(6 * mb));
        final stored = await r.repo.find(sid, TransferDirection.receive);
        expect(stored!.files.single.transferredBytes, length);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(
          part.lengthSync(),
          length,
          reason: 'nothing written after close',
        );
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });

  group('checkpoints and restart', () {
    test('a dropped upload pauses the session and keeps the bytes', () async {
      final sid = await createSession('a.bin', 10 * mb);
      final data = randomBytes(3 * mb);
      await partialPut('/v1/sessions/$sid/files/f1?offset=0', data, 10 * mb);
      await waitFor(
        () => r.server.sessions.single.status == SessionStatus.paused,
      );
      final (_, status) = await send('GET', '/v1/sessions/$sid/files/f1');
      expect(status['receivedBytes'], data.length);
      final stored = await r.repo.find(sid, TransferDirection.receive);
      expect(stored!.status, SessionStatus.paused);
      expect(stored.files.single.transferredBytes, data.length);
    });

    test('progress is stored every checkpoint while bytes flow', () async {
      await r.close();
      r = await TestReceiver.start(identity: identity, checkpointBytes: mb);
      final sid = await createSession('a.bin', 4 * mb);
      final socket = await SecureSocket.connect(
        '127.0.0.1',
        r.port,
        onBadCertificate: (_) => true,
      );
      addTearDown(socket.destroy);
      socket.write(
        'PUT /v1/sessions/$sid/files/f1?offset=0 HTTP/1.1\r\n'
        'host: x\r\n${await authLine()}content-length: ${4 * mb}\r\n\r\n',
      );
      socket.add(Uint8List(3 * mb));
      await socket.flush();
      await waitFor(
        () => r.events.whereType<FileProgress>().any(
          (e) => e.receivedBytes >= 2 * mb,
        ),
      );
      final stored = await r.repo.find(sid, TransferDirection.receive);
      // Stored without the upload ending.
      expect(stored!.files.single.transferredBytes, greaterThanOrEqualTo(mb));
    });

    test('a slow upload is checkpointed by time, not only by bytes', () async {
      // D-065: every 2 s or 64 MB, whichever first; here 200 ms or 1 GB.
      await r.close();
      r = await TestReceiver.start(
        identity: identity,
        checkpointBytes: 1024 * mb,
        checkpointInterval: const Duration(milliseconds: 200),
      );
      final sid = await createSession('a.bin', 8 * mb);
      final socket = await SecureSocket.connect(
        '127.0.0.1',
        r.port,
        onBadCertificate: (_) => true,
      );
      addTearDown(socket.destroy);
      socket.write(
        'PUT /v1/sessions/$sid/files/f1?offset=0 HTTP/1.1\r\n'
        'host: x\r\n${await authLine()}content-length: ${8 * mb}\r\n\r\n',
      );
      socket.add(Uint8List(2 * mb));
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      socket.add(Uint8List(2 * mb));
      await socket.flush();
      // Stored while the upload is still open, long before 1 GB.
      final end = DateTime.now().add(const Duration(seconds: 10));
      var stored = 0;
      while (stored < 2 * mb && DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final s = await r.repo.find(sid, TransferDirection.receive);
        stored = s!.files.single.transferredBytes;
      }
      expect(stored, greaterThanOrEqualTo(2 * mb));
    });

    test('after a restart the session is paused at its checkpoint', () async {
      final sid = await createSession('a.bin', 10 * mb);
      final data = randomBytes(3 * mb);
      await partialPut('/v1/sessions/$sid/files/f1?offset=0', data, 10 * mb);
      await waitFor(
        () => r.server.sessions.single.status == SessionStatus.paused,
      );
      // Bytes past the checkpoint, as if the app died before saving them.
      final part = File(p.join(r.tempDir, sid, 'f1.part'));
      part.writeAsBytesSync(List.filled(500, 9), mode: FileMode.append);

      await r.restart();

      expect(r.server.sessions.single.status, SessionStatus.paused);
      expect(part.lengthSync(), data.length);
      final (_, status) = await send('GET', '/v1/sessions/$sid/files/f1');
      expect(status['receivedBytes'], data.length);

      // And the sender can finish it.
      final rest = randomBytes(10 * mb);
      final whole = [...data, ...rest.sublist(0, 7 * mb)];
      await send(
        'PUT',
        '/v1/sessions/$sid/files/f1?offset=${data.length}',
        bytes: whole.sublist(data.length),
      );
      final (code, _) = await send(
        'POST',
        '/v1/sessions/$sid/files/f1/complete',
        json: {'sha256': shaOf(whole)},
      );
      expect(code, 200);
      expect(await statusOf(sid), SessionStatus.done);
    });

    test('an offer still waiting at restart becomes rejected', () async {
      r.decider = (_) => Completer<bool>().future;
      final (_, body) = await send(
        'POST',
        '/v1/sessions',
        json: offerJson([const FileOffer(fileId: 'f1', name: 'a', size: 3)]),
      );
      final sid = body['sessionId']! as String;
      await r.restart();
      expect(r.server.sessions, isEmpty);
      final stored = await r.repo.find(sid, TransferDirection.receive);
      expect(stored!.status, SessionStatus.rejected);
    });

    test('checkpointAll saves progress of a running upload', () async {
      await r.close();
      r = await TestReceiver.start(
        identity: identity,
        checkpointBytes: 64 * mb,
      );
      final sid = await createSession('a.bin', 8 * mb);
      final socket = await SecureSocket.connect(
        '127.0.0.1',
        r.port,
        onBadCertificate: (_) => true,
      );
      addTearDown(socket.destroy);
      socket.write(
        'PUT /v1/sessions/$sid/files/f1?offset=0 HTTP/1.1\r\n'
        'host: x\r\n${await authLine()}content-length: ${8 * mb}\r\n\r\n',
      );
      socket.add(Uint8List(2 * mb));
      await socket.flush();
      await waitFor(() => r.events.whereType<FileProgress>().isNotEmpty);
      final checkpoint = r.server.checkpointAll();
      socket.add(Uint8List(mb)); // the "current chunk" finishes
      await socket.flush();
      await checkpoint;
      final stored = await r.repo.find(sid, TransferDirection.receive);
      expect(stored!.files.single.transferredBytes, greaterThan(0));
    });
  });
}

/// A [ReceivedFileStore] whose first append waits for [gate]: a disk
/// that is busy for a while.
class _SlowStore implements ReceivedFileStore {
  _SlowStore(this._inner, this._gate);

  final ReceivedFileStore _inner;
  final Completer<void> _gate;

  @override
  String initialLocation(String sessionDir, FileOffer offer) =>
      _inner.initialLocation(sessionDir, offer);

  @override
  Future<(PartFile, String)> open(
    String location, {
    required String sessionDir,
    required FileOffer offer,
  }) async {
    final (part, at) = await _inner.open(
      location,
      sessionDir: sessionDir,
      offer: offer,
    );
    return (_SlowPart(part, _gate), at);
  }

  @override
  Future<int> length(String location) => _inner.length(location);

  @override
  Future<int> restore(String location, int checkpoint) =>
      _inner.restore(location, checkpoint);

  @override
  Future<void> delete(String location) => _inner.delete(location);

  @override
  Future<SaveResult> save(String location, FileOffer offer) =>
      _inner.save(location, offer);
}

class _SlowPart implements PartFile {
  _SlowPart(this._inner, this._gate);

  final PartFile _inner;
  final Completer<void> _gate;

  @override
  Future<void> append(Uint8List bytes) async {
    await _gate.future;
    await _inner.append(bytes);
  }

  @override
  Future<int> length() => _inner.length();

  @override
  Future<void> sync() => _inner.sync();

  @override
  Future<void> truncate(int length) => _inner.truncate(length);

  @override
  Future<void> setModified(DateTime time) => _inner.setModified(time);

  @override
  ByteSource get source => _inner.source;

  @override
  Future<void> close() => _inner.close();
}
