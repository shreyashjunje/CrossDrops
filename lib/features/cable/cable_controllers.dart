import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/cable/cable_link.dart';
import '../../core/cable/cable_messages.dart';
import '../../core/cable/cable_route.dart';
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

/// iPhone: runs the cable link.
final cableLinkAvailableProvider = Provider<bool>((ref) => Platform.isIOS);

/// Android: runs the cable bridge.
final cableBridgeAvailableProvider = Provider<bool>(
  (ref) => Platform.isAndroid,
);

/// Replaced in tests.
final cableLinkFactoryProvider = Provider<CableLink Function()>(
  (ref) => CableLink.new,
);

/// The other phone on the cable, on either platform; null while there is
/// none. Use [CablePeer.receives] before sending to it.
final cablePeerProvider = Provider<CablePeer?>(
  (ref) => ref.watch(cableLinkAvailableProvider)
      ? ref.watch(cableLinkProvider)
      : ref.watch(cableBridgeProvider)?.peer,
);

/// This phone's hello: its receive port while it receives (D-074).
CableHello? _ownHello(Ref ref) {
  final me = ref.read(identityProvider).value;
  if (me == null) return null;
  final receive = ref.read(receiveStateProvider);
  return CableHello(
    port: receive.receivingOff ? null : receive.port,
    deviceId: me.deviceId,
    name: me.deviceName,
  );
}

/// iPhone: the Android on the cable, or null. Runs the cable link while the
/// app is in the foreground; iOS closes its sockets in the background.
final cableLinkProvider = NotifierProvider<CableLinkController, CablePeer?>(
  CableLinkController.new,
);

class CableLinkController extends Notifier<CablePeer?> {
  @override
  CablePeer? build() {
    if (!ref.watch(cableLinkAvailableProvider)) return null;
    final link = ref.watch(cableLinkFactoryProvider)();
    final sub = link.changes.listen((p) => state = p);
    void hello() => link.hello = _ownHello(ref);
    ref.listen(receiveStateProvider, (_, _) => hello());
    ref.listen(identityProvider, (_, _) => hello(), fireImmediately: true);
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
/// not. It runs while an iPhone is plugged in. While the iPhone's hello
/// says it receives, this isolate's [cableDialer] dials it (D-074).
final cableBridgeProvider =
    NotifierProvider<CableBridgeController, UsbCableState?>(
      CableBridgeController.new,
    );

class CableBridgeController extends Notifier<UsbCableState?> {
  late UsbCable _cable;
  bool _plugged = false;
  CableDialer? _dialer;

  /// What the bridge was last started with; null while stopped. Kept after
  /// a failed start, so a refused permission is not asked again until the
  /// iPhone is plugged in again.
  String? _running;

  @override
  UsbCableState? build() {
    if (!ref.watch(cableBridgeAvailableProvider)) return null;
    final cable = _cable = ref.watch(usbCableProvider);
    final dials = ReceivePort()..listen(_onDial);
    final sub = cable.events.listen((e) {
      if (e is! UsbCableState) return;
      state = e;
      _setDialer(e.connected && (e.peer?.receives ?? false), dials);
    });
    ref.listen(usbDevicesProvider, (_, next) {
      _plugged = (next.value ?? const []).isNotEmpty;
      _sync();
    }, fireImmediately: true);
    ref.listen(receiveStateProvider, (_, _) => _sync());
    ref.listen(identityProvider, (_, _) => _sync());
    ref.onDispose(() {
      unawaited(sub.cancel());
      _setDialer(false, dials);
      dials.close();
      if (_running != null) unawaited(cable.stopCableBridge());
    });
    return null;
  }

  void _setDialer(bool on, ReceivePort dials) {
    if (on) {
      cableDialer = _dialer ??= CableDialer(dials.sendPort);
    } else if (_dialer != null) {
      if (identical(cableDialer, _dialer)) cableDialer = null;
      _dialer = null;
    }
  }

  /// A dial from any isolate: Kotlin joins the iPhone port to its socket.
  Future<void> _onDial(Object? m) async {
    if (m is! List || m.length != 3) return;
    final [listen as int, port as int, reply as SendPort] = m;
    try {
      await _cable.dialCable(listen: listen, port: port);
    } on PlatformException catch (e) {
      reply.send(e.code);
    }
  }

  void _sync() {
    final hello = _plugged ? _ownHello(ref) : null;
    if (hello == null) {
      if (_running == null) return;
      _running = null;
      unawaited(_cable.stopCableBridge());
      state = null;
      return;
    }
    final port = hello.port;
    final ports = [
      if (port != null) ...[port, ...ref.read(receiveStateProvider).dataPorts],
    ];
    final key = '${ports.join(',')} ${hello.deviceId} ${hello.name}';
    if (key == _running) return;
    _running = key;
    unawaited(_start(port, ports, hello.deviceId, hello.name));
  }

  Future<void> _start(
    int? port,
    List<int> ports,
    String deviceId,
    String name,
  ) async {
    try {
      await _cable.startCableBridge(
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
