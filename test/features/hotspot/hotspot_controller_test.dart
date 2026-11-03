import 'dart:async';

import 'package:crossdrop/core/discovery/network_monitor.dart';
import 'package:crossdrop/core/protocol/connect_payload.dart';
import 'package:crossdrop/features/hotspot/hotspot_controller.dart';
import 'package:crossdrop/platform/hotspot.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _wifi = WifiCredentials(
  ssid: 'AndroidShare_1',
  password: 'secret123',
  security: WifiSecurity.wpa3Transition,
);
const _client = LocalAddress('192.168.1.20', 'wlan0');
const _ap = LocalAddress('192.168.49.1', 'swlan0');

class FakeHotspot implements HotspotService {
  String? failWith;
  int starts = 0;
  int stops = 0;
  final _stopped = StreamController<void>.broadcast();

  /// Addresses the phone has after a start.
  List<LocalAddress> addresses = [_client];

  @override
  Future<HotspotSupport> support() async => HotspotSupport.available;

  @override
  Future<WifiCredentials> start() async {
    starts++;
    if (failWith != null) throw HotspotException(failWith!);
    addresses = [_client, _ap];
    return _wifi;
  }

  @override
  Future<void> stop() async {
    stops++;
    addresses = [_client];
  }

  @override
  Stream<void> get stopped => _stopped.stream;

  void stopFromSettings() => _stopped.add(null);
}

class FakeActive extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) => state = v;
}

final fakeActiveProvider = NotifierProvider<FakeActive, bool>(FakeActive.new);

ProviderContainer containerFor(FakeHotspot hotspot) {
  final c = ProviderContainer(
    overrides: [
      hotspotServiceProvider.overrideWithValue(hotspot),
      localAddressesProvider.overrideWithValue(() async => hotspot.addresses),
      transfersActiveProvider.overrideWith(
        (ref) => ref.watch(fakeActiveProvider),
      ),
    ],
  );
  // Keep the auto-dispose controller alive, as the screen does.
  c.listen(hotspotControllerProvider, (_, _) {});
  return c;
}

void main() {
  test('start finds the hotspot address; dispose stops it', () async {
    final hotspot = FakeHotspot();
    final c = containerFor(hotspot);
    await c.read(hotspotControllerProvider.notifier).start();
    final s = c.read(hotspotControllerProvider);
    expect(s.phase, HotspotPhase.running);
    expect(s.wifi, _wifi);
    expect(s.address, _ap);
    c.dispose();
    expect(hotspot.stops, 1);
  });

  test('a failure keeps the code; nothing to stop', () async {
    final hotspot = FakeHotspot()..failWith = HotspotErrors.tetheringOn;
    final c = containerFor(hotspot);
    await c.read(hotspotControllerProvider.notifier).start();
    final s = c.read(hotspotControllerProvider);
    expect(s.phase, HotspotPhase.failed);
    expect(s.error, HotspotErrors.tetheringOn);
    c.dispose();
    expect(hotspot.stops, 0);
  });

  test('no address within the wait: stops and fails', () {
    fakeAsync((async) {
      final hotspot = _NoAddressHotspot();
      final c = containerFor(hotspot);
      c.read(hotspotControllerProvider.notifier).start();
      async.elapse(HotspotController.addressWait + const Duration(seconds: 1));
      final s = c.read(hotspotControllerProvider);
      expect(s.phase, HotspotPhase.failed);
      expect(s.error, 'no_address');
      expect(hotspot.stops, 1);
      c.dispose();
    });
  });

  test('stopped from quick settings', () async {
    final hotspot = FakeHotspot();
    final c = containerFor(hotspot);
    await c.read(hotspotControllerProvider.notifier).start();
    hotspot.stopFromSettings();
    await Future<void>.delayed(Duration.zero);
    expect(c.read(hotspotControllerProvider).error, 'stopped');
    c.dispose();
  });

  test('stops 60 s after the last transfer; a new one cancels', () {
    fakeAsync((async) {
      final hotspot = FakeHotspot();
      final c = containerFor(hotspot);
      final ctrl = c.read(hotspotControllerProvider.notifier);
      ctrl.start();
      async.flushMicrotasks();
      final active = c.read(fakeActiveProvider.notifier);

      active.set(true);
      async.elapse(Duration.zero);
      active.set(false);
      async.elapse(Duration.zero);
      expect(c.read(hotspotControllerProvider).stopsAt, isNotNull);

      async.elapse(const Duration(seconds: 30));
      active.set(true); // Another transfer.
      async.elapse(Duration.zero);
      expect(c.read(hotspotControllerProvider).stopsAt, isNull);
      async.elapse(const Duration(seconds: 60));
      expect(c.read(hotspotControllerProvider).isRunning, isTrue);

      active.set(false);
      async.elapse(Duration.zero);
      async.elapse(HotspotController.idleStop);
      expect(c.read(hotspotControllerProvider).phase, HotspotPhase.idle);
      expect(hotspot.stops, 1);
      c.dispose();
    });
  });

  test('Keep on cancels the stop', () {
    fakeAsync((async) {
      final hotspot = FakeHotspot();
      final c = containerFor(hotspot);
      final ctrl = c.read(hotspotControllerProvider.notifier);
      ctrl.start();
      async.flushMicrotasks();
      final active = c.read(fakeActiveProvider.notifier);
      active.set(true);
      async.elapse(Duration.zero);
      active.set(false);
      async.elapse(Duration.zero);
      ctrl.keepOn();
      async.elapse(const Duration(minutes: 5));
      expect(c.read(hotspotControllerProvider).isRunning, isTrue);
      expect(c.read(hotspotControllerProvider).stopsAt, isNull);
      c.dispose();
    });
  });

  test('no countdown when no transfer ran yet', () async {
    final hotspot = FakeHotspot();
    final c = containerFor(hotspot);
    await c.read(hotspotControllerProvider.notifier).start();
    expect(c.read(hotspotControllerProvider).stopsAt, isNull);
    c.dispose();
  });

  group('wifiJoinQr', () {
    test('standard format', () {
      expect(
        wifiJoinQr(const WifiCredentials(ssid: 'Net', password: 'pass1234')),
        'WIFI:T:WPA;S:Net;P:pass1234;;',
      );
    });

    test('escapes special characters', () {
      expect(
        wifiJoinQr(
          const WifiCredentials(ssid: r'a;b,c:d"e\f', password: 'p;w:1234'),
        ),
        r'WIFI:T:WPA;S:a\;b\,c\:d\"e\\f;P:p\;w\:1234;;',
      );
    });
  });
}

class _NoAddressHotspot extends FakeHotspot {
  @override
  Future<WifiCredentials> start() async {
    starts++;
    return _wifi; // Addresses stay as before.
  }
}
