import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crossdrop/core/client/upload_client.dart';
import 'package:crossdrop/core/security/ephemeral_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late EphemeralIdentity identity;

  setUpAll(() async => identity = await EphemeralIdentity.generate());
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
        if (latin1.decode(data.take(4).toList()) == 'GET ') {
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
      stallTimeout: const Duration(seconds: 1),
    );
    addTearDown(client.close);
    await expectLater(
      client.fileStatus(
        const UploadTarget(sessionId: 's', fileId: 'f1', path: '', size: 0),
      ),
      throwsA(isA<UploadException>().having((e) => e.code, 'code', 'network')),
    );
  });
}
