import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../log.dart';
import 'cable_messages.dart';
import 'cable_route.dart';

/// The phone on the other end of the cable, from its hello.
class CablePeer {
  const CablePeer({
    required this.port,
    required this.deviceId,
    required this.name,
  });

  /// Its receive server port; null while it does not receive.
  final int? port;

  /// It receives now: there is something to send to.
  bool get receives => port != null;
  final String deviceId;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is CablePeer &&
      other.port == port &&
      other.deviceId == deviceId &&
      other.name == name;

  @override
  int get hashCode => Object.hash(port, deviceId, name);
}

/// The iPhone's end of the cable (D-073, D-074).
///
/// Listens on 127.0.0.1 at the first free port of [ports] for the Android
/// bridge's control connection, and sets this isolate's [cableDialer]:
/// each dial is sent to the Android as a `dial` line. After the Android's
/// hello it answers with [hello], so the Android can send here too. Only
/// the newest control connection is used, so a bridge that reconnects
/// takes over.
class CableLink {
  CableLink({
    this.ports = cableControlPorts,
    this.helloTimeout = const Duration(seconds: 5),
  });

  final List<int> ports;

  /// A control connection that sends no hello in this time is closed.
  final Duration helloTimeout;

  final _changes = StreamController<CablePeer?>.broadcast();
  ServerSocket? _server;
  ReceivePort? _dials;
  CableDialer? _dialer;
  Socket? _control;
  CablePeer? _peer;
  CableHello? _hello;

  /// This phone's hello for the Android; sent again when it changes.
  CableHello? get hello => _hello;
  set hello(CableHello? h) {
    if (h?.encode() == _hello?.encode()) return;
    _hello = h;
    if (h != null && _peer != null) _control?.write(h.encode());
  }

  /// Dial replies by listen port, until the Android fails them or they
  /// expire (the dialer has its own timeout).
  final Map<int, SendPort> _pending = {};

  /// The connected phone; null while none is.
  CablePeer? get peer => _peer;
  Stream<CablePeer?> get changes => _changes.stream;

  /// The control port in use; null when stopped.
  int? get port => _server?.port;

  /// Starts listening. False if every port in [ports] is taken.
  Future<bool> start() async {
    if (_server != null) return true;
    for (final p in ports) {
      try {
        _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, p);
        break;
      } on SocketException {
        continue;
      }
    }
    final server = _server;
    if (server == null) {
      logEvent('cable', 'link: no free control port');
      return false;
    }
    server.listen(_onControl, onError: (Object _) {});
    final dials = _dials = ReceivePort()..listen(_onDial);
    cableDialer = _dialer = CableDialer(dials.sendPort);
    logEvent('cable', 'link: listening on ${server.port}');
    return true;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close();
    _control?.destroy();
    _control = null;
    _dials?.close();
    _dials = null;
    if (identical(cableDialer, _dialer)) cableDialer = null;
    _dialer = null;
    _failPending('stopped');
    _setPeer(null);
  }

  Future<void> dispose() async {
    await stop();
    await _changes.close();
  }

  void _onControl(Socket socket) {
    // Swap before destroying: the old socket may end synchronously.
    final old = _control;
    _control = socket;
    old?.destroy();
    var greeted = false;
    late final Timer helloTimer;
    void ended() {
      helloTimer.cancel();
      socket.destroy();
      if (!identical(_control, socket)) return;
      _control = null;
      _failPending('disconnected');
      _setPeer(null);
    }

    helloTimer = Timer(helloTimeout, () {
      if (!greeted) ended();
    });
    cableLines(socket).listen(
      (line) {
        if (!identical(_control, socket)) return;
        switch (decodeCableMessage(line)) {
          case CableHello(
            :final version,
            :final port,
            :final deviceId,
            :final name,
          ):
            if (version != cableProtocolVersion) {
              logEvent('cable', 'link: unsupported version $version');
              socket.destroy();
              return;
            }
            if (!greeted) {
              greeted = true;
              final mine = _hello;
              if (mine != null) socket.write(mine.encode());
            }
            _setPeer(CablePeer(port: port, deviceId: deviceId, name: name));
          case CableFail(:final listen):
            _pending.remove(listen)?.send('refused');
          case CableDial() || null:
            break;
        }
      },
      onError: (Object _) => ended(),
      onDone: ended,
      cancelOnError: true,
    );
  }

  void _onDial(Object? m) {
    if (m is! List || m.length != 3) return;
    final [listen as int, port as int, reply as SendPort] = m;
    final control = _control;
    if (control == null || _peer == null) {
      reply.send('not connected');
      return;
    }
    _pending[listen] = reply;
    Timer(const Duration(seconds: 30), () => _pending.remove(listen));
    control.write(CableDial(listen: listen, port: port).encode());
  }

  void _failPending(String why) {
    for (final reply in _pending.values) {
      reply.send(why);
    }
    _pending.clear();
  }

  void _setPeer(CablePeer? peer) {
    if (peer == _peer) return;
    _peer = peer;
    logEvent(
      'cable',
      peer == null ? 'link: no phone' : 'link: phone connected',
    );
    if (!_changes.isClosed) _changes.add(peer);
  }
}
