import 'dart:async';

import 'package:crossdrop/core/discovery/network_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

const _wifi = LocalAddress('192.168.1.20', 'wlan0');
const _wifi2 = LocalAddress('10.0.0.7', 'wlan0');
const _mobile = LocalAddress('10.12.0.3', 'rmnet_data0');

void main() {
  group('reachableAddresses', () {
    test('drops mobile data, VPN, loopback and public addresses', () {
      expect(
        reachableAddresses(const [
          _wifi,
          _mobile,
          LocalAddress('100.70.1.2', 'pdp_ip0'),
          LocalAddress('10.8.0.2', 'tun0'),
          LocalAddress('10.8.0.3', 'utun3'),
          LocalAddress('127.0.0.1', 'lo'),
          LocalAddress('8.8.4.4', 'wlan1'),
        ]),
        [_wifi],
      );
    });
  });

  group('pickQrAddress', () {
    test('prefers Wi-Fi over hotspot and others', () {
      expect(
        pickQrAddress(const [
          LocalAddress('192.168.43.1', 'swlan0'),
          LocalAddress('172.17.0.1', 'eth0'),
          _wifi,
        ]),
        _wifi,
      );
    });

    test('iPhone en0', () {
      const en0 = LocalAddress('192.168.1.5', 'en0');
      expect(
        pickQrAddress(const [LocalAddress('172.20.10.1', 'bridge100'), en0]),
        en0,
      );
    });

    test('hotspot host when there is no Wi-Fi client address', () {
      const bridge = LocalAddress('172.20.10.1', 'bridge100');
      expect(pickQrAddress(const [_mobile, bridge]), bridge);
    });

    test('falls back to any reachable address, or null', () {
      const eth = LocalAddress('192.168.0.9', 'eth0');
      expect(pickQrAddress(const [eth]), eth);
      expect(pickQrAddress(const [_mobile]), isNull);
      expect(pickQrAddress(const []), isNull);
    });
  });

  group('NetworkMonitor', () {
    late StreamController<void> connectivity;
    late List<LocalAddress> addresses;
    late NetworkMonitor monitor;
    late List<List<LocalAddress>> changes;

    setUp(() async {
      connectivity = StreamController<void>.broadcast();
      addresses = [_wifi, _mobile];
      monitor = NetworkMonitor(
        connectivityEvents: connectivity.stream,
        listAddresses: () async => List.of(addresses),
        pollInterval: const Duration(milliseconds: 20),
        debounce: const Duration(milliseconds: 10),
      );
      changes = [];
      monitor.changes.listen(changes.add);
      await monitor.start();
    });

    tearDown(() async {
      await monitor.dispose();
      await connectivity.close();
    });

    Future<void> wait() =>
        Future<void>.delayed(const Duration(milliseconds: 80));

    test('current holds reachable addresses after start', () {
      expect(monitor.current, [_wifi]);
    });

    test('no change, no event', () async {
      await wait();
      expect(changes, isEmpty);
    });

    test('an IP change is reported once', () async {
      addresses = [_wifi2, _mobile];
      await wait();
      expect(changes, [
        [_wifi2],
      ]);
      expect(monitor.current, [_wifi2]);
    });

    test('a mobile data change alone is not reported', () async {
      addresses = [_wifi, const LocalAddress('10.99.0.1', 'rmnet_data1')];
      await wait();
      expect(changes, isEmpty);
    });

    test('Wi-Fi lost is reported with an empty list', () async {
      addresses = [_mobile];
      await wait();
      expect(changes, [<LocalAddress>[]]);
    });

    test('a connectivity event is reported even with the same IP', () async {
      connectivity.add(null);
      await wait();
      expect(changes, [
        [_wifi],
      ]);
    });

    test('a burst of events gives one change', () async {
      for (var i = 0; i < 5; i++) {
        connectivity.add(null);
      }
      addresses = [_wifi2];
      await wait();
      expect(changes, hasLength(1));
    });

    test('nothing after stop', () async {
      await monitor.stop();
      addresses = [_wifi2];
      connectivity.add(null);
      await wait();
      expect(changes, isEmpty);
    });
  });
}
