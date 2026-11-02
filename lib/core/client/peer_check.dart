import '../protocol/models.dart';
import 'upload_client.dart';

/// Where to send, from the nearby list, a QR code or typed by hand.
class ConnectTarget {
  const ConnectTarget({
    required this.host,
    required this.port,
    this.deviceId,
    this.name,
    this.fingerprint,
    this.fingerprintHint,
  });

  final String host;
  final int port;

  /// Expected device id; null when the address was typed by hand.
  final String? deviceId;
  final String? name;

  /// Full certificate fingerprint, known only from a QR code.
  /// TODO(phase4): pin the TLS connection to it.
  final String? fingerprint;

  /// First 16 hex characters, from the TXT record.
  final String? fingerprintHint;

  ConnectTarget withInfo(DeviceInfo info) => ConnectTarget(
    host: host,
    port: port,
    deviceId: info.id,
    name: info.name,
    fingerprint: fingerprint,
    fingerprintHint: fingerprintHint,
  );
}

/// Asks [target] who it is (`GET /v1/info`) before sending to it.
///
/// Throws [UploadException] with code:
/// - `network` if nothing answers (wrong address, client isolation, VPN),
/// - `version` if there is no common protocol version,
/// - `identity_mismatch` if another device answers at that address,
/// - `bad_response` if the reply is not valid.
///
/// Returns the target completed with the device's id and name.
Future<ConnectTarget> checkPeer(
  ConnectTarget target, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final client = UploadClient(
    host: target.host,
    port: target.port,
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
    return target.withInfo(info);
  } finally {
    client.close();
  }
}
