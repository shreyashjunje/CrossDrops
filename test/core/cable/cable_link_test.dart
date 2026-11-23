import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crossdrop/core/cable/cable_link.dart';
import 'package:crossdrop/core/cable/cable_messages.dart';
import 'package:crossdrop/core/cable/cable_route.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_cable_bridge.dart';

/// A plain echo server: what a dialed socket reaches.
Future<ServerSocket> _echo() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  s.listen((c) => c.cast<List<int>>().pipe(c).catchError((_) {}));
  return s;
}

Future<String> _roundTrip(Socket s, String text) async {
  s.write(text);
  final got = await s.first.timeout(const Duration(seconds: 5));
  s.destroy();
  return utf8.decode(got);
}

void main() {
  group('messages', () {
    test('round trip', () {
      const hello = CableHello(port: 5000, deviceId: 'a1', name: 'Pixel');
      final back = decodeCableMessage(hello.encode().trim())! as CableHello;
      expect(
        (back.version, back.port, back.deviceId, back.name),
        (1, 5000, 'a1', 'Pixel'),
      );
      final dial =
          decodeCableMessage(
                const CableDial(listen: 6000, port: 5001).encode().trim(),
              )!
              as CableDial;
      expect((dial.listen, dial.port), (6000, 5001));
      final fail =
          decodeCableMessage(const CableFail(listen: 6000).encode().trim())!
              as CableFail;
      expect(fail.listen, 6000);
    });

    test('invalid or unknown lines are skipped', () {
      for (final line in [
        'not json',
        '[]',
        '{"t":"what"}',
        '{"t":"dial","listen":0,"port":5}',
        '{"t":"dial","listen":70000,"port":5}',
        '{"t":"dial","listen":"1","port":5}',
        '{"t":"hello","v":1,"port":5,"id":"","name":"x"}',
        '{"t":"hello","v":1,"port":5,"name":"x"}',
      ]) {
        expect(decodeCableMessage(line), isNull, reason: line);
      }
    });

    test('a long name is cut', () {
      final m =
          decodeCableMessage(
                jsonEncode({
                  't': 'hello',
                  'v': 1,
                  'port': 5,
                  'id': 'a',
                  'name': 'x' * 500,
                }),
              )!
              as CableHello;
      expect(m.name.length, maxCableNameChars);
    });

    test('lines split across chunks, several per chunk', () async {
      final lines = await cableLines(
        Stream.fromIterable([
          utf8.encode('ab'),
          utf8.encode('c\nde\nf'),
          utf8.encode('\n'),
        ]),
      ).toList();
      expect(lines, ['abc', 'de', 'f']);
    });

    test('a line over the limit ends the stream', () async {
      await expectLater(
        cableLines(Stream.value(List.filled(maxCableLineBytes, 0x41))).toList(),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('link', () {
    late CableLink link;
    late ServerSocket echo;

    setUp(() async {
      link = CableLink(
        ports: const [0],
        helloTimeout: const Duration(milliseconds: 300),
      );
      expect(await link.start(), isTrue);
      echo = await _echo();
    });

    tearDown(() async {
      await link.dispose();
      await echo.close();
    });

    Future<CablePeer?> nextChange() =>
        link.changes.first.timeout(const Duration(seconds: 5));

    test('sets the dialer; dials fail until a phone says hello', () async {
      expect(cableDialer, isNotNull);
      expect(link.peer, isNull);
      await expectLater(
        dialCable(echo.port, const Duration(seconds: 2)),
        throwsA(isA<SocketException>()),
      );
    });

    test('a hello connects the phone and dials reach its ports', () async {
      final changed = nextChange();
      final bridge = await FakeCableBridge.connect(
        link.port!,
        receivePort: echo.port,
      );
      addTearDown(bridge.unplug);
      expect(
        await changed,
        CablePeer(port: echo.port, deviceId: 'android-1', name: 'Pixel'),
      );
      final s = await dialCable(echo.port, const Duration(seconds: 5));
      expect(await _roundTrip(s, 'hi'), 'hi');
      expect(bridge.dials.single.port, echo.port);
    });

    test('a port the phone refuses fails the dial at once', () async {
      final changed = nextChange();
      final bridge = await FakeCableBridge.connect(
        link.port!,
        receivePort: echo.port,
      );
      addTearDown(bridge.unplug);
      await changed;
      final watch = Stopwatch()..start();
      await expectLater(
        dialCable(1, const Duration(seconds: 5)),
        throwsA(isA<SocketException>()),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('unplugging drops the phone', () async {
      final connected = nextChange();
      final bridge = await FakeCableBridge.connect(
        link.port!,
        receivePort: echo.port,
      );
      await connected;
      final gone = nextChange();
      bridge.unplug();
      expect(await gone, isNull);
      expect(link.peer, isNull);
    });

    test('a connection without a hello is closed', () async {
      final bridge = await FakeCableBridge.connect(
        link.port!,
        receivePort: echo.port,
        sendHello: false,
      );
      await expectLater(bridge.closed, completes);
      expect(link.peer, isNull);
    });

    test('a newer control connection takes over', () async {
      final first = await FakeCableBridge.connect(
        link.port!,
        receivePort: echo.port,
        name: 'Old',
      );
      await nextChange();
      final changed = nextChange();
      final second = await FakeCableBridge.connect(
        link.port!,
        receivePort: echo.port,
        name: 'New',
      );
      addTearDown(second.unplug);
      expect((await changed)?.name, 'New');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(link.peer?.name, 'New');
      final s = await dialCable(echo.port, const Duration(seconds: 5));
      expect(await _roundTrip(s, 'x'), 'x');
      expect(first.dials, isEmpty);
    });

    test('an oversized line closes the control connection', () async {
      final bridge = await FakeCableBridge.connect(
        link.port!,
        receivePort: echo.port,
      );
      await nextChange();
      final gone = nextChange();
      bridge.control.add(List.filled(maxCableLineBytes + 10, 0x41));
      expect(await gone, isNull);
    });

    test('stop clears the dialer and the phone', () async {
      await FakeCableBridge.connect(link.port!, receivePort: echo.port);
      await nextChange();
      await link.stop();
      expect(cableDialer, isNull);
      expect(link.peer, isNull);
      expect(link.port, isNull);
    });

    test('a taken port moves to the next one', () async {
      final taken = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(taken.close);
      final other = CableLink(ports: [taken.port, 0]);
      addTearDown(other.dispose);
      expect(await other.start(), isTrue);
      expect(other.port, isNot(taken.port));
    });
  });
}
