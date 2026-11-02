import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// A TCP proxy in the same process that simulates a bad Wi-Fi link between
/// sender and receiver. TLS passes through untouched.
///
/// - [dropEvery]: kill all connections each time a random number of
///   sender-to-receiver bytes (within the range) has passed.
/// - [dropAt]: kill all connections once, after this many more bytes.
/// - [latency]: delay every chunk in both directions.
/// - [blackhole]: stop forwarding without closing (Wi-Fi gone, no RST).
/// - [refuse]: close new connections at once (no route).
class FlakyProxy {
  FlakyProxy._(this._server, this.targetPort, this._random);

  final ServerSocket _server;

  /// Where the receiver listens. Change it to follow a restarted receiver.
  int targetPort;
  final Random _random;
  final Set<_Pipe> _pipes = {};

  ({int min, int max})? dropEvery;
  int? _nextDropAt;
  int _upBytes = 0;
  Duration latency = Duration.zero;
  bool blackhole = false;
  bool refuse = false;

  /// Runs right after each drop, before anyone can reconnect.
  void Function()? onDrop;

  /// Connections dropped so far.
  int drops = 0;

  /// Connections accepted so far.
  int connections = 0;

  static Future<FlakyProxy> start(int targetPort, {int seed = 1}) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = FlakyProxy._(server, targetPort, Random(seed));
    server.listen(proxy._accept);
    return proxy;
  }

  int get port => _server.port;

  /// Sender-to-receiver bytes forwarded so far.
  int get upBytes => _upBytes;

  /// Drops every connection once [bytes] more upstream bytes have passed.
  void dropAt(int bytes) => _nextDropAt = _upBytes + bytes;

  void dropAll() {
    for (final p in _pipes.toList()) {
      p.destroy();
    }
    drops++;
    onDrop?.call();
  }

  Future<void> close() async {
    for (final p in _pipes.toList()) {
      p.destroy();
    }
    await _server.close();
  }

  Future<void> _accept(Socket client) async {
    connections++;
    if (refuse) {
      client.destroy();
      return;
    }
    final Socket upstream;
    try {
      upstream = await Socket.connect(InternetAddress.loopbackIPv4, targetPort);
    } on SocketException {
      client.destroy();
      return;
    }
    final pipe = _Pipe(client, upstream, this);
    _pipes.add(pipe);
    pipe.start();
  }

  /// Called for each upstream chunk; returns false if the link just died.
  bool _countUp(int n) {
    _upBytes += n;
    final every = dropEvery;
    if (_nextDropAt == null && every != null) {
      _nextDropAt =
          _upBytes + every.min + _random.nextInt(every.max - every.min + 1);
    }
    final at = _nextDropAt;
    if (at != null && _upBytes >= at) {
      _nextDropAt = null;
      dropAll();
      return false;
    }
    return true;
  }
}

class _Pipe {
  _Pipe(this.client, this.upstream, this.proxy);

  final Socket client;
  final Socket upstream;
  final FlakyProxy proxy;
  bool _dead = false;

  void start() {
    // Write errors on a dropped link land here.
    client.done.then((_) {}, onError: (Object _) => destroy());
    upstream.done.then((_) {}, onError: (Object _) => destroy());
    _forward(client, upstream, up: true);
    _forward(upstream, client, up: false);
  }

  void _forward(Socket from, Socket to, {required bool up}) {
    late StreamSubscription<Uint8List> sub;
    sub = from.listen(
      (data) async {
        if (_dead) return;
        if (proxy.blackhole) return; // swallowed, like a dead link
        if (proxy.latency > Duration.zero) {
          sub.pause();
          await Future<void>.delayed(proxy.latency);
          sub.resume();
          if (_dead) return;
        }
        if (up && !proxy._countUp(data.length)) return;
        try {
          to.add(data);
        } on Object {
          destroy();
        }
      },
      onDone: destroy,
      onError: (Object _) => destroy(),
      cancelOnError: true,
    );
  }

  void destroy() {
    if (_dead) return;
    _dead = true;
    proxy._pipes.remove(this);
    client.destroy();
    upstream.destroy();
  }
}
