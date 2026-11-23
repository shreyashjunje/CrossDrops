import 'dart:async';
import 'dart:io';

import '../cable/cable_route.dart';
import 'fingerprint.dart';

/// The receiver's certificate did not have the expected fingerprint. The
/// connection was closed during the handshake, before any request was
/// sent. Never retried without the pin (CLAUDE.md hard rule 4).
class PinMismatchException implements Exception {
  const PinMismatchException();

  @override
  String toString() => 'PinMismatchException';
}

SecurityContext _clientContext() =>
    SecurityContext(withTrustedRoots: false)
      ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3;

/// An HttpClient whose every connection is pinned to [fingerprint].
///
/// Verified with dart:io 3.13 (D-027): the certificate passed to
/// `onBadCertificate` is the leaf, and a chain that appends the expected
/// certificate after an attacker's leaf is refused. The leaf is checked a
/// second time after the handshake, before the socket is handed to the
/// HttpClient, so a request body never reaches the wrong server.
///
/// [onMismatch] runs when a connection is refused for its fingerprint.
HttpClient pinnedHttpClient({
  required String fingerprint,
  Duration connectTimeout = const Duration(seconds: 10),
  void Function()? onMismatch,
}) {
  if (!isValidFingerprint(fingerprint)) {
    throw ArgumentError.value(fingerprint, 'fingerprint');
  }
  bool matches(X509Certificate? cert) =>
      cert != null &&
      fingerprintsEqual(certificateFingerprint(cert.der), fingerprint);

  return HttpClient()
    // Local network only; never a proxy.
    ..findProxy = ((_) => 'DIRECT')
    ..connectionTimeout = connectTimeout
    ..connectionFactory = (uri, proxyHost, proxyPort) async {
      if (uri.scheme != 'https' && uri.scheme != 'wss') {
        throw ArgumentError('only https is allowed');
      }
      bool onCertificate(X509Certificate cert) {
        final ok = matches(cert);
        if (!ok) onMismatch?.call();
        return ok;
      }

      Socket checked(SecureSocket s) {
        if (!matches(s.peerCertificate)) {
          s.destroy();
          onMismatch?.call();
          throw const PinMismatchException();
        }
        return s;
      }

      if (isCableHost(uri.host)) {
        var cancelled = false;
        final socket = _secureOverCable(uri.port, connectTimeout, onCertificate)
            .then((s) {
              if (cancelled) {
                s.destroy();
                throw const SocketException('connect cancelled');
              }
              return checked(s);
            });
        return ConnectionTask.fromSocket(socket, () => cancelled = true);
      }
      final task = await SecureSocket.startConnect(
        uri.host,
        uri.port,
        context: _clientContext(),
        onBadCertificate: onCertificate,
      );
      final socket = task.socket
          .timeout(
            connectTimeout,
            onTimeout: () {
              task.cancel();
              throw const SocketException('connect timed out');
            },
          )
          .then(checked);
      return ConnectionTask.fromSocket(socket, task.cancel);
    };
}

/// TLS over a socket dialed through the cable (D-073), with the same
/// context and certificate check as a network connection.
Future<SecureSocket> _secureOverCable(
  int port,
  Duration timeout,
  bool Function(X509Certificate) onBadCertificate,
) async {
  final raw = await dialCable(port, timeout);
  try {
    return await SecureSocket.secure(
      raw,
      context: _clientContext(),
      onBadCertificate: onBadCertificate,
    ).timeout(timeout);
  } catch (_) {
    raw.destroy();
    rethrow;
  }
}

/// Connects once, reads the server's certificate fingerprint and closes,
/// without sending any request. For a first contact from the nearby list
/// or a typed address, where only a hint (or nothing) is known; the
/// pairing code then checks it (ARCHITECTURE.md, "Pairing").
///
/// Throws [SocketException], [HandshakeException] or [TimeoutException].
Future<String> probeFingerprint(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final socket = isCableHost(host)
      ? await _secureOverCable(port, timeout, (_) => true)
      : await SecureSocket.connect(
          host,
          port,
          context: _clientContext(),
          onBadCertificate: (_) => true,
          timeout: timeout,
        );
  try {
    final cert = socket.peerCertificate;
    if (cert == null) {
      throw const HandshakeException('no server certificate');
    }
    return certificateFingerprint(cert.der);
  } finally {
    socket.destroy();
  }
}
