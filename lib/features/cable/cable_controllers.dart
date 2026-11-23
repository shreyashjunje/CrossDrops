import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/cable/cable_link.dart';
import '../../core/log.dart';
import '../../platform/usb_cable.dart';
import '../receive/receive_host.dart';

// Send by cable (D-073). Both controllers are kept alive by `ReceiveHost`.

/// Android: the iPhone on the USB cable.
final usbCableProvider = Provider<UsbCable>(
  (ref) => Platform.isAndroid ? ChannelUsbCable() : const NoUsbCable(),
);

/// Android: the iPhones plugged in now.
final usbDevicesProvider = StreamProvider<List<UsbCableDevice>>((ref) {
  final cable = ref.watch(usbCableProvider);
  final devices = <String, UsbCableDevice>{};
  final out = StreamController<List<UsbCableDevice>>();
  void push() => out.add(List.unmodifiable(devices.values));
  final sub = cable.events.listen((e) {
    switch (e) {
      case UsbCableAttached(:final device):
        devices[device.id] = device;
        push();
      case UsbCableDetached(:final id):
        if (devices.remove(id) != null) push();
      case UsbCableState():
        break;
    }
  });
  unawaited(
    cable.devices().then(
      (list) {
        for (final d in list) {
          devices[d.id] = d;
        }
        push();
      },
      onError: (Object e) {
        logEvent('cable', 'devices failed (${e.runtimeType})');
        push();
      },
    ),
  );
  ref.onDispose(() async {
    await sub.cancel();
    await out.close();
  });
  return out.stream;
});

/// iPhone: sends over the cable.
final cableSendAvailableProvider = Provider<bool>((ref) => Platform.isIOS);

/// Android: receives over the cable.
final cableReceiveAvailableProvider = Provider<bool>(
  (ref) => Platform.isAndroid,
);

/// Replaced in tests.
final cableLinkFactoryProvider = Provider<CableLink Function()>(
  (ref) => CableLink.new,
);

/// iPhone: the phone on the cable, or null. Runs the cable link while the
/// app is in the foreground; iOS closes its sockets in the background.
final cablePeerProvider = NotifierProvider<CableSendController, CablePeer?>(
  CableSendController.new,
);

class CableSendController extends Notifier<CablePeer?> {
  @override
  CablePeer? build() {
    if (!ref.watch(cableSendAvailableProvider)) return null;
    final link = ref.watch(cableLinkFactoryProvider)();
    final sub = link.changes.listen((p) => state = p);
    final lifecycle = AppLifecycleListener(
      onPause: () => unawaited(link.stop()),
      onResume: () => unawaited(link.start()),
    );
    unawaited(link.start());
    ref.onDispose(() {
      lifecycle.dispose();
      unawaited(sub.cancel());
      unawaited(link.dispose());
    });
    return null;
  }
}

/// Android: the cable bridge's state while it runs; null while it does
/// not. It runs while an iPhone is plugged in, the receive server is up
/// and Receiving is on.
final cableReceiveProvider =
    NotifierProvider<CableReceiveController, UsbCableState?>(
      CableReceiveController.new,
    );

class CableReceiveController extends Notifier<UsbCableState?> {
  late UsbCable _camera;
  bool _plugged = false;

  /// What the bridge was last started with; null while stopped. Kept after
  /// a failed start, so a refused permission is not asked again until the
  /// iPhone is plugged in again.
  String? _running;

  @override
  UsbCableState? build() {
    if (!ref.watch(cableReceiveAvailableProvider)) return null;
    final camera = _camera = ref.watch(usbCableProvider);
    final sub = camera.events.listen((e) {
      if (e is UsbCableState) state = e;
    });
    ref.listen(usbDevicesProvider, (_, next) {
      _plugged = (next.value ?? const []).isNotEmpty;
      _sync();
    }, fireImmediately: true);
    ref.listen(receiveStateProvider, (_, _) => _sync());
    ref.listen(identityProvider, (_, _) => _sync());
    ref.onDispose(() {
      unawaited(sub.cancel());
      if (_running != null) unawaited(camera.stopCableBridge());
    });
    return null;
  }

  void _sync() {
    final receive = ref.read(receiveStateProvider);
    final port = receive.port;
    final wanted = _plugged && port != null && !receive.receivingOff;
    final me = wanted ? ref.read(identityProvider).value : null;
    if (port == null || me == null) {
      if (_running == null) return;
      _running = null;
      unawaited(_camera.stopCableBridge());
      state = null;
      return;
    }
    final ports = [port, ...receive.dataPorts];
    final key = '$port ${ports.join(',')} ${me.deviceId} ${me.deviceName}';
    if (key == _running) return;
    _running = key;
    unawaited(_start(port, ports, me.deviceId, me.deviceName));
  }

  Future<void> _start(
    int port,
    List<int> ports,
    String deviceId,
    String name,
  ) async {
    try {
      await _camera.startCableBridge(
        port: port,
        ports: ports,
        deviceId: deviceId,
        name: name,
      );
    } on PlatformException catch (e) {
      logEvent('cable', 'bridge did not start: ${e.code}');
      if (ref.mounted) state = UsbCableState('stopped', e.code);
    }
  }
}
