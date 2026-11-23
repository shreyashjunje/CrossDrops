import 'dart:async';
import 'dart:io';
import 'dart:isolate';

/// The receiver's host for a send over the USB cable (D-073). `.invalid`
/// never resolves (RFC 2606), so it cannot reach the network by mistake.
const String cableHost = 'cable.crossdrop.invalid';

bool isCableHost(String host) => host == cableHost;

/// This isolate's way to the phone on the cable; null while no phone is
/// connected by cable. Set by the cable link in the main isolate and by
/// each upload worker from its arguments.
CableDialer? cableDialer;

/// Opens plain sockets to ports of the phone on the cable.
///
/// Holds only a [SendPort], so it can be sent to other isolates: upload
/// workers dial their own sockets and no bytes pass through the main
/// isolate.
class CableDialer {
  const CableDialer(this._link);

  /// The cable link's dial requests (`CableLink`): `[listen, port, reply]`.
  final SendPort _link;

  /// A socket to [port] on the other phone. This isolate listens on a new
  /// loopback port; the other phone connects to it through the cable and
  /// joins it to [port]. Throws [SocketException].
  Future<Socket> dial(
    int port, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final reply = ReceivePort();
    final done = Completer<Socket>();
    final sub = server.listen((s) {
      // Only the first connection is ours.
      done.isCompleted ? s.destroy() : done.complete(s);
    });
    reply.listen((m) {
      if (!done.isCompleted) done.completeError(SocketException('cable: $m'));
    });
    try {
      _link.send([server.port, port, reply.sendPort]);
      return await done.future.timeout(timeout);
    } on TimeoutException {
      throw const SocketException('cable: no answer');
    } finally {
      await sub.cancel();
      reply.close();
      await server.close();
    }
  }
}

/// A plain socket to [port] through this isolate's [cableDialer].
Future<Socket> dialCable(int port, Duration timeout) {
  final dialer = cableDialer;
  if (dialer == null) {
    return Future.error(const SocketException('cable: not connected'));
  }
  return dialer.dial(port, timeout: timeout);
}
