import 'dart:async';
import 'dart:io';

import '../protocol/models.dart';
import '../security/device_credentials.dart';
import '../security/fingerprint.dart';
import '../security/pinning.dart';
import '../storage/trust_repository.dart';
import 'upload_client.dart';

/// How the receiver's fingerprint became known.
enum PinSource {
  /// Scanned from its QR code: strong (ARCHITECTURE.md, "Pairing" 1).
  qr,

  /// Seen on first contact (nearby list or typed address); the pairing
  /// code checks it (ARCHITECTURE.md, "Pairing" 2).
  firstContact,
}

/// Where to send, from the nearby list, a QR code or typed by hand.
class ConnectTarget {
  const ConnectTarget({
    required this.host,
    required this.port,
    this.deviceId,
    this.name,
    this.platform,
    this.fingerprint,
    this.fingerprintHint,
    this.pinSource,
    this.trust = PeerTrust.unknown,
  });

  final String host;
  final int port;

  /// Expected device id; null when the address was typed by hand.
  final String? deviceId;
  final String? name;
  final String? platform;

  /// Full certificate fingerprint. From a QR code before [checkPeer];
  /// always set after it, and every connection is pinned to it.
  final String? fingerprint;

  /// First 16 hex characters, from the TXT record.
  final String? fingerprintHint;

  /// Set by [checkPeer].
  final PinSource? pinSource;

  /// What this phone knows about [fingerprint]. A [PeerTrust.lookalike]
  /// means "a device you trust has this name or id, but a different key":
  /// warn before sending.
  final PeerTrust trust;

  ConnectTarget _checked(
    DeviceInfo info,
    String fingerprint,
    PinSource source,
    PeerTrust trust,
  ) => ConnectTarget(
    host: host,
    port: port,
    deviceId: info.id,
    name: info.name,
    platform: info.platform,
    fingerprint: fingerprint,
    fingerprintHint: fingerprintHint,
    pinSource: source,
    trust: trust,
  );
}

/// Looks up trust for a receiver; see [TrustRepository.check].
typedef ReceiverTrustLookup = Future<PeerTrust> Function({
  required String fingerprint,
  String? deviceId,
  String? name,
});

/// Asks [target] who it is (`GET /v1/info`) before sending to it, over a
/// connection pinned to its fingerprint.
///
/// The fingerprint comes from the QR code if there is one. Otherwise it is
/// read from the TLS handshake first (no request is sent on that
/// connection) and must start with the TXT hint, if the target came from
/// the nearby list.
///
/// Throws [UploadException] with code:
/// - `network` if nothing answers (wrong address, client isolation, VPN),
/// - `pin_mismatch` if the certificate is not the one in the QR code,
/// - `version` if there is no common protocol version,
/// - `identity_mismatch` if another device answers at that address,
/// - `bad_response` if the reply is not valid.
///
/// Returns the target completed with the device's id, name, fingerprint
/// and trust.
Future<ConnectTarget> checkPeer(
  ConnectTarget target, {
  required DeviceCredentials credentials,
  ReceiverTrustLookup? trustLookup,
  Duration timeout = const Duration(seconds: 5),
}) async {
  var pin = target.fingerprint;
  final source = pin == null ? PinSource.firstContact : PinSource.qr;
  if (pin == null) {
    try {
      pin = await probeFingerprint(target.host, target.port, timeout: timeout);
    } on SocketException catch (e) {
      throw UploadException('network', e.message);
    } on HandshakeException catch (e) {
      throw UploadException('network', e.message);
    } on TimeoutException {
      throw const UploadException('network', 'no answer');
    }
    final hint = target.fingerprintHint;
    if (hint != null && !pin.startsWith(hint)) {
      throw const UploadException(
        'identity_mismatch',
        'A different device answered at this address.',
      );
    }
  } else if (!isValidFingerprint(pin)) {
    throw const UploadException('bad_response', 'invalid fingerprint');
  }

  final client = UploadClient(
    host: target.host,
    port: target.port,
    fingerprint: pin,
    credentials: credentials,
    connectTimeout: timeout,
    stallTimeout: timeout,
  );
  try {
    final DeviceInfo info;
    try {
      info = await client.info();
    } on FormatError {
      throw const UploadException('bad_response', 'invalid device info');
    }
    if (!info.versions.contains(protocolVersion)) {
      throw const UploadException(
        'version',
        'Update CrossDrop on the other phone.',
      );
    }
    final expected = target.deviceId;
    if (expected != null && info.id != expected) {
      throw const UploadException(
        'identity_mismatch',
        'A different device answered at this address.',
      );
    }
    final trust =
        await trustLookup?.call(
          fingerprint: pin,
          deviceId: info.id,
          name: info.name,
        ) ??
        PeerTrust.unknown;
    return target._checked(info, pin, source, trust);
  } finally {
    client.close();
  }
}
