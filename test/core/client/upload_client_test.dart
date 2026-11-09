import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crossdrop/core/client/upload_client.dart';
import 'package:crossdrop/core/security/device_credentials.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late DeviceCredentials identity;
  late DeviceCredentials sender;

  setUpAll(() async {
    identity = await DeviceCredentials.generate();
    sender = await DeviceCredentials.generate();
  });

  /// Answers the two auth requests with well-formed values, so the
  /// client gets past authentication; returns false for other requests.
  bool answerAuth(Socket socket, String head) {
    final String body;
    if (head.startsWith('POST /v1/auth/challenge ')) {
      body = jsonEncode({'nonce': 'N' * 43});
    } else if (head.startsWith('POST /v1/auth ')) {
      body = jsonEncode({'token': 'T' * 43, 'expiresIn': 3600});
    } else {
      return false;
    }
    socket.write(
      'HTTP/1.1 200 OK\r\n'
      'content-type: application/json\r\n'
      'content-length: ${body.length}\r\n'
      'connection: close\r\n\r\n$body',
    );
    socket.close();
    return true;
  }

  setUp(() => dir = Directory.systemTemp.createTempSync('cd_client'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// A receiver that answers GET with receivedBytes 0, then accepts the PUT
  /// connection but never reads its body, like a peer whose Wi-Fi dropped.
  Future<SecureServerSocket> silentReceiver(int size) async {
    final server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      identity.serverContext(),
    );
    server.listen((socket) {
      late StreamSubscription<Uint8List> sub;
      sub = socket.listen((data) {
        final head = latin1.decode(data.take(64).toList());
        if (answerAuth(socket, head)) return;
        if (head.startsWith('GET ')) {
          final body = jsonEncode({
            'fileId': 'f1',
            'size': size,
            'receivedBytes': 0,
            'status': 'receiving',
          });
          socket.write(
            'HTTP/1.1 200 OK\r\n'
            'content-type: application/json\r\n'
            'content-length: ${body.length}\r\n'
            'connection: close\r\n\r\n$body',
          );
          socket.close();
        } else {
          sub.pause();
        }
      }, onError: (_) {});
    });
    return server;
  }

  test('aborts with "stalled" when the receiver stops reading', () async {
    const size = 64 * 1024 * 1024;
    final path = p.join(dir.path, 'big.bin');
    final raf = File(path).openSync(mode: FileMode.write)..truncateSync(size);
    raf.closeSync();
    final server = await silentReceiver(size);
    addTearDown(server.close);

    final client = UploadClient(
      host: '127.0.0.1',
      port: server.port,
      fingerprint: identity.fingerprint,
      credentials: sender,
      stallTimeout: const Duration(seconds: 1),
    );
    addTearDown(client.close);
    final target = UploadTarget(
      sessionId: 's',
      fileId: 'f1',
      path: path,
      size: size,
    );

    final watch = Stopwatch()..start();
    await expectLater(
      client.transfer(target),
      throwsA(isA<UploadException>().having((e) => e.code, 'code', 'stalled')),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
  });

  test('control request to a silent peer times out as network', () async {
    final server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      identity.serverContext(),
    );
    addTearDown(server.close);
    server.listen((socket) => socket.listen((_) {}, onError: (_) {}));

    final client = UploadClient(
      host: '127.0.0.1',
      port: server.port,
      fingerprint: identity.fingerprint,
      credentials: sender,
      stallTimeout: const Duration(seconds: 1),
    );
    addTearDown(client.close);
    await expectLater(
      client.fileStatus(UploadTarget(sessionId: 's', fileId: 'f1', size: 0)),
      throwsA(isA<UploadException>().having((e) => e.code, 'code', 'network')),
    );
  });

  test('refuses a reply larger than maxReplyBytes', () async {
    final server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      identity.serverContext(),
    );
    addTearDown(server.close);
    server.listen((socket) {
      socket.listen((data) {
        final head = latin1.decode(data.take(64).toList());
        if (answerAuth(socket, head)) return;
        if (!head.startsWith('GET ')) return;
        final body = '{"pad":"${'x' * (maxReplyBytes + 1)}"}';
        socket.write(
          'HTTP/1.1 200 OK\r\n'
          'content-type: application/json\r\n'
          'content-length: ${body.length}\r\n'
          'connection: close\r\n\r\n$body',
        );
        socket.close();
      }, onError: (_) {});
    });

    final client = UploadClient(
      host: '127.0.0.1',
      port: server.port,
      fingerprint: identity.fingerprint,
      credentials: sender,
    );
    addTearDown(client.close);
    await expectLater(
      client.fileStatus(UploadTarget(sessionId: 's', fileId: 'f1', size: 0)),
      throwsA(
        isA<UploadException>()
            .having((e) => e.code, 'code', 'bad_response')
            .having((e) => e.message, 'message', 'response too large'),
      ),
    );
  });
}
