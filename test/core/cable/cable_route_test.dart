import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crossdrop/core/cable/cable_route.dart';
import 'package:crossdrop/core/security/device_credentials.dart';
import 'package:crossdrop/core/security/pinning.dart';
import 'package:flutter_test/flutter_test.dart';

/// Plays the Android bridge on loopback: for each dial it connects to the
/// requested port and to the dialer's listen port, and joins them.
class FakeBridge {
  FakeBridge({this.refuse = false}) {
    _requests.listen((m) async {
      final [listen as int, port as int, reply as SendPort] = m as List;
      dialedPorts.add(port);
      if (refuse) {
        reply.send('refused');
        return;
      }
      final target = await Socket.connect(InternetAddress.loopbackIPv4, port);
      final back = await Socket.connect(InternetAddress.loopbackIPv4, listen);
      unawaited(target.cast<List<int>>().pipe(back).catchError((_) {}));
      unawaited(back.cast<List<int>>().pipe(target).catchError((_) {}));
    });
  }

  final bool refuse;
  final _requests = ReceivePort();
  final List<int> dialedPorts = [];

  CableDialer get dialer => CableDialer(_requests.sendPort);

  void close() => _requests.close();
}

/// An upload worker's view: its own isolate, a dialer from its arguments.
Future<void> _workerGet(List<Object> a) async {
  cableDialer = a[0] as CableDialer;
  final body = await _get(
    pinnedHttpClient(fingerprint: a[1] as String),
    _cableUrl(a[2] as int),
  );
  (a[3] as SendPort).send(body);
}

Uri _cableUrl(int port) => Uri.parse('https://$cableHost:$port/v1/info');

Future<String> _get(HttpClient client, Uri url) async {
  try {
    final res = await (await client.getUrl(url)).close();
    return await res.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

void main() {
  late DeviceCredentials receiver;
  late DeviceCredentials other;
  late HttpServer server;
  var requests = 0;

  setUpAll(() async {
    receiver = await DeviceCredentials.generate();
    other = await DeviceCredentials.generate();
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      receiver.serverContext(),
    );
    server.listen((r) async {
      requests++;
      r.response.write('ok');
      await r.response.close();
    });
  });

  tearDownAll(() => server.close(force: true));
  tearDown(() => cableDialer = null);

  test('a pinned request reaches the receiver through the cable', () async {
    final bridge = FakeBridge();
    addTearDown(bridge.close);
    cableDialer = bridge.dialer;
    final body = await _get(
      pinnedHttpClient(fingerprint: receiver.fingerprint),
      _cableUrl(server.port),
    );
    expect(body, 'ok');
    expect(bridge.dialedPorts, [server.port]);
  });

  test(
    'another certificate on the cable is refused before any request',
    () async {
      final bridge = FakeBridge();
      addTearDown(bridge.close);
      cableDialer = bridge.dialer;
      final before = requests;
      var mismatch = false;
      await expectLater(
        _get(
          pinnedHttpClient(
            fingerprint: other.fingerprint,
            onMismatch: () => mismatch = true,
          ),
          _cableUrl(server.port),
        ),
        throwsA(anything),
      );
      expect(mismatch, isTrue);
      expect(requests, before);
    },
  );

  test('the fingerprint probe works through the cable', () async {
    final bridge = FakeBridge();
    addTearDown(bridge.close);
    cableDialer = bridge.dialer;
    expect(
      await probeFingerprint(cableHost, server.port),
      receiver.fingerprint,
    );
  });

  test('without a cable link the cable host fails like a network', () async {
    await expectLater(
      probeFingerprint(cableHost, server.port),
      throwsA(isA<SocketException>()),
    );
  });

  test('a refused dial fails at once', () async {
    final bridge = FakeBridge(refuse: true);
    addTearDown(bridge.close);
    final watch = Stopwatch()..start();
    await expectLater(
      bridge.dialer.dial(server.port),
      throwsA(isA<SocketException>()),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('a dial nobody answers times out as a socket error', () async {
    final silent = ReceivePort();
    addTearDown(silent.close);
    await expectLater(
      CableDialer(silent.sendPort)
          .dial(server.port, timeout: const Duration(milliseconds: 200)),
      throwsA(isA<SocketException>()),
    );
  });

  test('another isolate dials its own socket with a sent dialer', () async {
    final bridge = FakeBridge();
    addTearDown(bridge.close);
    final done = ReceivePort();
    await Isolate.spawn(_workerGet, [
      bridge.dialer,
      receiver.fingerprint,
      server.port,
      done.sendPort,
    ]);
    final body = await done.first;
    expect(body, 'ok');
  });
}
