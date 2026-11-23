import 'dart:async';
import 'dart:io';

import 'package:crossdrop/core/cable/cable_messages.dart';

/// Plays the Android side of the cable on loopback (D-073): a control
/// connection to the iPhone's link, a hello, and each `dial` joined to the
/// requested port, as `CableBridge.kt` does over usbmux.
class FakeCableBridge {
  FakeCableBridge._(this.control, this.allowedPorts);

  final Socket control;

  /// Ports it agrees to dial; others get a `fail`.
  final Set<int> allowedPorts;
  final List<CableDial> dials = [];

  /// The iPhone's hellos, newest last.
  final List<CableHello> hellos = [];
  final List<Socket> _joined = [];
  final _closed = Completer<void>();

  /// Completes when the link closes the control connection.
  Future<void> get closed => _closed.future;

  static Future<FakeCableBridge> connect(
    int linkPort, {
    required int receivePort,
    Set<int>? allowedPorts,
    String deviceId = 'android-1',
    String name = 'Pixel',
    bool sendHello = true,
  }) async {
    final control = await Socket.connect(
      InternetAddress.loopbackIPv4,
      linkPort,
    );
    final bridge = FakeCableBridge._(control, allowedPorts ?? {receivePort});
    cableLines(control).listen(
      bridge._onLine,
      onError: (Object _) {},
      onDone: bridge._closed.complete,
    );
    if (sendHello) {
      bridge.send(
        CableHello(port: receivePort, deviceId: deviceId, name: name),
      );
    }
    return bridge;
  }

  void send(CableMessage m) => control.write(m.encode());

  Future<void> _onLine(String line) async {
    final m = decodeCableMessage(line);
    if (m is CableHello) hellos.add(m);
    if (m is! CableDial) return;
    dials.add(m);
    if (!allowedPorts.contains(m.port)) {
      send(CableFail(listen: m.listen));
      return;
    }
    try {
      final target = await Socket.connect(InternetAddress.loopbackIPv4, m.port);
      final back = await Socket.connect(InternetAddress.loopbackIPv4, m.listen);
      _joined.addAll([target, back]);
      unawaited(target.cast<List<int>>().pipe(back).catchError((_) {}));
      unawaited(back.cast<List<int>>().pipe(target).catchError((_) {}));
    } on SocketException {
      send(CableFail(listen: m.listen));
    }
  }

  /// Like unplugging: the control connection and every joined socket end.
  void unplug() {
    control.destroy();
    for (final s in _joined) {
      s.destroy();
    }
  }
}
