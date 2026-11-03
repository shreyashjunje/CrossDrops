import 'dart:async';

import 'package:crossdrop/app/network_binding.dart';
import 'package:crossdrop/core/discovery/subnet.dart';
import 'package:crossdrop/platform/network.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeNetwork implements NetworkPlatform {
  FakeNetwork(this.initial);
  WifiState? initial;
  final changes = StreamController<WifiState>.broadcast();
  final binds = <bool>[];
  bool bindWorks = true;

  @override
  Future<List<InterfaceAddress>> interfaces() async => const [];

  @override
  Future<WifiState?> wifiState() async => initial;

  @override
  Stream<WifiState> get wifiChanges => changes.stream;

  @override
  Future<bool> bindToWifi(bool on) async {
    binds.add(on);
    return bindWorks;
  }
}

const _noInternet = WifiState(connected: true);
const _home = WifiState(connected: true, validated: true, isDefault: true);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('binds at start on a Wi-Fi without internet', () async {
    final net = FakeNetwork(_noInternet);
    final binder = NetworkBinder(net);
    await binder.start();
    expect(net.binds, [true]);
    await binder.stop();
    expect(net.binds, [true, false]);
  });

  test('normal home Wi-Fi: one clear at start, then nothing', () async {
    final net = FakeNetwork(_home);
    final binder = NetworkBinder(net);
    await binder.start();
    expect(net.binds, [false]);
    net.changes.add(_home);
    await settle();
    expect(net.binds, [false]);
    await binder.stop();
  });

  test('follows changes and binds once per change', () async {
    final net = FakeNetwork(null);
    final binder = NetworkBinder(net);
    await binder.start();
    net.changes.add(_noInternet);
    await settle();
    net.changes.add(_noInternet);
    await settle();
    expect(net.binds, [true]);
    net.changes.add(_home); // Joined a Wi-Fi with internet.
    await settle();
    expect(net.binds, [true, false]);
    await binder.stop();
  });

  test('Wi-Fi lost: Android cleared it; bind again on return', () async {
    final net = FakeNetwork(_noInternet);
    final binder = NetworkBinder(net);
    await binder.start();
    net.changes.add(const WifiState());
    await settle();
    net.changes.add(_noInternet);
    await settle();
    expect(net.binds, [true, true]);
    await binder.stop();
  });

  test('a failed bind is retried on the next change', () async {
    final net = FakeNetwork(_noInternet)..bindWorks = false;
    final binder = NetworkBinder(net);
    await binder.start();
    net.bindWorks = true;
    net.changes.add(_noInternet);
    await settle();
    expect(net.binds, [true, true]);
    await binder.stop();
  });

  test('band from the frequency', () {
    expect(const WifiState(frequencyMhz: 2437).band, '2.4 GHz');
    expect(const WifiState(frequencyMhz: 5180).band, '5 GHz');
    expect(const WifiState(frequencyMhz: 5955).band, '6 GHz');
    expect(const WifiState().band, isNull);
  });

  test('fromMap tolerates missing and wrong types', () {
    final s = WifiState.fromMap({'connected': true, 'frequencyMhz': 'x'});
    expect(s.connected, isTrue);
    expect(s.frequencyMhz, isNull);
  });
}
