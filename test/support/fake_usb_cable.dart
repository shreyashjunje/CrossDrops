import 'dart:async';

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
  final List<({int port, List<int> ports, String deviceId, String name})?>
  cableCalls = [];

  /// Codes `startCableBridge` throws, one per call.
  final List<String> cableErrors = [];

  void cableState(String state, [String? code]) =>
      _events.add(UsbCableState(state, code));

  @override
  Future<void> startCableBridge({
    required int port,
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
}
