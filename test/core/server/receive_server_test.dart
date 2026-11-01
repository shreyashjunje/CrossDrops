import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/ephemeral_identity.dart';
import 'package:crossdrop/core/server/receive_server.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late EphemeralIdentity identity;
  late Directory root;
  late ReceiveServer server;
  late HttpClient http;

  setUpAll(() async => identity = await EphemeralIdentity.generate());

  setUp(() async {
    root = Directory.systemTemp.createTempSync('cd_server');
    server = await ReceiveServer.start(
      securityContext: identity.serverContext(),
      tempDir: p.join(root.path, 'tmp'),
      saveDir: p.join(root.path, 'save'),
      address: InternetAddress.loopbackIPv4,
      bodyIdleTimeout: const Duration(seconds: 2),
    );
    http = HttpClient()..badCertificateCallback = (_, _, _) => true;
  });

  tearDown(() async {
    http.close(force: true);
    await server.close();
    root.deleteSync(recursive: true);
  });

  Uri url(String path) => Uri.parse('https://127.0.0.1:${server.port}$path');

  Future<(int, Map<String, Object?>)> send(
    String method,
    String path, {
    Object? json,
    List<int>? bytes,
    bool chunked = false,
    int? contentLength,
  }) async {
    final req = await http.openUrl(method, url(path));
    if (json != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(json));
    } else if (bytes != null) {
      if (contentLength != null) {
        req.contentLength = contentLength;
      } else if (!chunked) {
        req.contentLength = bytes.length;
      }
      req.add(bytes);
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return (res.statusCode, jsonDecode(text) as Map<String, Object?>);
  }

  Future<String> createSession(String name, int size) async {
    final (code, body) = await send(
      'POST',
      '/v1/sessions',
      json: SessionOffer(
        sender: const SenderInfo(id: 's', name: 'test', platform: 'android'),
        files: [FileOffer(fileId: 'f1', name: name, size: size)],
      ).toJson(),
    );
    expect(code, 200);
    return body['sessionId']! as String;
  }

  Uint8List randomBytes(int n) {
    final rnd = Random(7);
    return Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));
  }

  test('full flow: offer, put, status, complete', () async {
    final data = randomBytes(3 * 1024 * 1024 + 5);
    final sid = await createSession('photo.jpg', data.length);
    final files = '/v1/sessions/$sid/files/f1';

    var (code, body) = await send('GET', files);
    expect(body['receivedBytes'], 0);

    (code, body) = await send('PUT', '$files?offset=0', bytes: data);
    expect(code, 200);
    expect(body['receivedBytes'], data.length);

    (code, body) = await send(
      'POST',
      '$files/complete',
      json: {'sha256': sha256.convert(data).toString()},
    );
    expect(code, 200, reason: '$body');
    expect(body['status'], 'saved');

    final saved = File(p.join(root.path, 'save', 'photo.jpg'));
    expect(saved.readAsBytesSync(), data);
    expect(
      File(p.join(root.path, 'tmp', sid, 'f1.part')).existsSync(),
      isFalse,
    );
  });

  test('resume in two PUTs gives the right hash', () async {
    final data = randomBytes(2 * 1024 * 1024 + 77);
    final sid = await createSession('a.bin', data.length);
    final files = '/v1/sessions/$sid/files/f1';
    const half = 1024 * 1024 + 3;

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
      json: {'sha256': sha256.convert(data).toString()},
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

  test('Content-Length beyond declared size is rejected up front', () async {
    final sid = await createSession('a.bin', 10);
    final (code, body) = await send(
      'PUT',
      '/v1/sessions/$sid/files/f1?offset=0',
      bytes: List.filled(11, 1),
    );
    expect(code, 413);
    expect(body['error'], ErrorCodes.tooManyBytes);
  });

  test('chunked body beyond declared size is stopped and discarded', () async {
    final sid = await createSession('a.bin', 10);
    final files = '/v1/sessions/$sid/files/f1';
    final (code, body) = await send(
      'PUT',
      '$files?offset=0',
      bytes: List.filled(64, 1),
      chunked: true,
    );
    expect(code, 413);
    expect(body['error'], ErrorCodes.tooManyBytes);
    final (_, status) = await send('GET', files);
    expect(status['receivedBytes'], 0);
  });

  test('hash mismatch is not saved and resets the partial file', () async {
    final data = randomBytes(1000);
    final sid = await createSession('a.bin', data.length);
    final files = '/v1/sessions/$sid/files/f1';
    await send('PUT', '$files?offset=0', bytes: data);
    final (code, body) = await send(
      'POST',
      '$files/complete',
      json: {'sha256': '0' * 64},
    );
    expect(code, 422);
    expect(body['error'], ErrorCodes.hashMismatch);
    expect(Directory(p.join(root.path, 'save')).listSync(), isEmpty);
    final (_, status) = await send('GET', files);
    expect(status['receivedBytes'], 0);
  });

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

  test('malicious name is sanitized and stays in the save folder', () async {
    final data = utf8.encode('hello');
    final sid = await createSession('../../evil.sh', data.length);
    final files = '/v1/sessions/$sid/files/f1';
    await send('PUT', '$files?offset=0', bytes: data);
    final (code, _) = await send(
      'POST',
      '$files/complete',
      json: {'sha256': sha256.convert(data).toString()},
    );
    expect(code, 200);
    expect(File(p.join(root.path, 'save', 'evil.sh')).existsSync(), isTrue);
    expect(File(p.join(root.path, 'evil.sh')).existsSync(), isFalse);
  });

  test('empty file can be completed without a PUT', () async {
    final sid = await createSession('empty.txt', 0);
    final (code, _) = await send(
      'POST',
      '/v1/sessions/$sid/files/f1/complete',
      json: {'sha256': sha256.convert(const []).toString()},
    );
    expect(code, 200);
  });

  test('unknown session and bad offer', () async {
    var (code, body) = await send('GET', '/v1/sessions/nope/files/f1');
    expect(code, 404);
    (code, body) = await send('POST', '/v1/sessions', json: {'protocol': 1});
    expect(code, 400);
    expect(body['error'], ErrorCodes.badRequest);
  });

  test('emits progress and saved events', () async {
    final events = <ReceiveEvent>[];
    final sub = server.events.listen(events.add);
    final data = randomBytes(2 * 1024 * 1024);
    final sid = await createSession('a.bin', data.length);
    final files = '/v1/sessions/$sid/files/f1';
    await send('PUT', '$files?offset=0', bytes: data);
    await send(
      'POST',
      '$files/complete',
      json: {'sha256': sha256.convert(data).toString()},
    );
    await sub.cancel();
    expect(events.first, isA<SessionStarted>());
    expect(events.whereType<FileProgress>().last.receivedBytes, data.length);
    expect(events.last, isA<FileSaved>());
  });
}
