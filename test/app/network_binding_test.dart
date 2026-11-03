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

  /// When set, a bind waits for it, as the platform call does.
  Completer<void>? bindGate;

  @override
  Future<List<InterfaceAddress>> interfaces() async => const [];

  @override
  Future<WifiState?> wifiState() async => initial;

  @override
  Stream<WifiState> get wifiChanges => changes.stream;

  @override
  Future<bool> bindToWifi(bool on) async {
    binds.add(on);
    await bindGate?.future;
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

  test('Wi-Fi lost while a bind runs: the next such Wi-Fi is bound', () async {
    // Review L7: the loss cleared the flag, then the late bind result set
    // it again, so the next Wi-Fi without internet was skipped.
    final net = FakeNetwork(null);
    final binder = NetworkBinder(net);
    await binder.start();
    final gate = net.bindGate = Completer<void>();
    net.changes.add(_noInternet);
    await settle();
    expect(net.binds, [true]);
    net.changes.add(const WifiState()); // lost while the bind runs
    await settle();
    gate.complete();
    net.bindGate = null;
    await pumpEventQueue();
    net.changes.add(_noInternet);
    await pumpEventQueue();
    expect(net.binds, [true, true]);
    await binder.stop();
  });

  test('changes never run side by side; a burst ends at the newest', () async {
    final net = FakeNetwork(null);
    final binder = NetworkBinder(net);
    await binder.start();
    final gate = net.bindGate = Completer<void>();
    net.changes.add(_noInternet);
    await settle();
    // While that bind runs: internet, none, internet again.
    net.changes
      ..add(_home)
      ..add(_noInternet)
      ..add(_home);
    await settle();
    expect(net.binds, [true], reason: 'one call at a time');
    gate.complete();
    net.bindGate = null;
    await pumpEventQueue();
    expect(net.binds, [true, false]);
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
