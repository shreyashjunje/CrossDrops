import 'dart:async';
import 'dart:io';

import 'package:crossdrop/core/cable/cable_link.dart';
import 'package:crossdrop/platform/usb_cable.dart';
import 'package:flutter/services.dart';

/// An iPhone on a cable, in memory.
class FakeUsbCable implements UsbCable {
  FakeUsbCable({List<UsbCableDevice>? attached})
    : attached = attached ?? [iphone];

  static const iphone = UsbCableDevice(
    id: '/dev/bus/usb/001/002',
    name: 'iPhone',
  );

  final List<UsbCableDevice> attached;
  final _events = StreamController<UsbCableEvent>.broadcast();

  void plug(UsbCableDevice d) {
    attached.add(d);
    _events.add(UsbCableAttached(d));
  }

  void unplug(String id) {
    attached.removeWhere((d) => d.id == id);
    _events.add(UsbCableDetached(id));
  }

  @override
  Stream<UsbCableEvent> get events => _events.stream;

  @override
  Future<List<UsbCableDevice>> devices() async => List.of(attached);

  /// What [probeTunnel] answers.
  String probeReport = 'Handshake: ok, version 2';
  int? probedPort;

  @override
  Future<String> probeTunnel({int? port}) async {
    probedPort = port;
    return probeReport;
  }

  /// Each start of the cable bridge, newest last; null after a stop.
  final List<({int? port, List<int> ports, String deviceId, String name})?>
  cableCalls = [];

  /// Codes `startCableBridge` throws, one per call.
  final List<String> cableErrors = [];

  void cableState(String state, [String? code, CablePeer? peer]) =>
      _events.add(UsbCableState(state, code, peer));

  @override
  Future<void> startCableBridge({
    required int? port,
    required List<int> ports,
    required String deviceId,
    required String name,
  }) async {
    if (cableErrors.isNotEmpty) {
      throw PlatformException(code: cableErrors.removeAt(0));
    }
    cableCalls.add((port: port, ports: ports, deviceId: deviceId, name: name));
  }

  @override
  Future<void> stopCableBridge() async => cableCalls.add(null);

  /// Dials made, as (listen, port).
  final List<(int, int)> dials = [];

  /// Ports on "the iPhone" (here: loopback) that answer a dial.
  Set<int>? reachable;

  /// Like Kotlin's `dialOut`: joins [port] (the iPhone, here on loopback)
  /// to [listen].
  @override
  Future<void> dialCable({required int listen, required int port}) async {
    dials.add((listen, port));
    if (!(reachable?.contains(port) ?? false)) {
      throw PlatformException(code: 'refused');
    }
    final target = await Socket.connect(InternetAddress.loopbackIPv4, port);
    final back = await Socket.connect(InternetAddress.loopbackIPv4, listen);
    unawaited(target.cast<List<int>>().pipe(back).catchError((_) {}));
    unawaited(back.cast<List<int>>().pipe(target).catchError((_) {}));
  }
}
