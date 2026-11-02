import '../protocol/device_name.dart';
import '../protocol/models.dart';
import '../security/device_identity.dart';

/// Length of the fingerprint hint in the TXT record, in hex characters.
const int fingerprintHintLength = 16;

final RegExp _hintPattern = RegExp(r'^[0-9a-f]{16}$');
final RegExp _versionPattern = RegExp(r'^[1-9][0-9]{0,2}$');

/// The `_crossdrop._tcp` TXT record (ARCHITECTURE.md, "Discovery
/// advertisement"): `v`, `id`, `n`, `p`, `fp`.
///
/// `fp` is only a hint; the full fingerprint is checked during the TLS
/// handshake.
class TxtRecord {
  const TxtRecord({
    required this.version,
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.fingerprintHint,
  });

  /// Builds the record this device advertises. [fingerprint] is the full
  /// lowercase hex SHA-256 of the certificate.
  factory TxtRecord.forDevice({
    required DeviceIdentity identity,
    required DevicePlatform platform,
    required String fingerprint,
  }) => TxtRecord(
    version: protocolVersion,
    deviceId: identity.deviceId,
    name: identity.deviceName,
    platform: platform,
    fingerprintHint: fingerprint.substring(0, fingerprintHintLength),
  );

  final int version;
  final String deviceId;
  final String name;

  /// Null only when [version] is not one this app understands.
  final DevicePlatform? platform;

  /// First 16 hex characters of the certificate SHA-256, lowercase. Null
  /// only when [version] is not one this app understands.
  final String? fingerprintHint;

  bool get isSupported => version == protocolVersion;

  Map<String, String> encode() => {
    'v': '$version',
    'id': deviceId,
    'n': name,
    'p': ?platform?.name,
    'fp': ?fingerprintHint,
  };

  /// Parses a received TXT record. Throws [FormatError] if it cannot be
  /// used.
  ///
  /// Keys are case-insensitive (RFC 6763). A record with a newer protocol
  /// version only needs `v`, `id` and `n`, so the UI can show "needs
  /// update" for it.
  static TxtRecord decode(Map<String, String> attributes) {
    final a = <String, String>{};
    for (final MapEntry(:key, :value) in attributes.entries) {
      final k = key.toLowerCase();
      if (a.containsKey(k)) throw FormatError('duplicate key');
      a[k] = value;
    }

    final v = a['v'];
    if (v == null || !_versionPattern.hasMatch(v)) {
      throw FormatError('invalid v');
    }
    final version = int.parse(v);

    final id = a['id']?.toLowerCase();
    if (id == null || !isValidDeviceId(id)) throw FormatError('invalid id');

    final name = sanitizeDeviceName(a['n'] ?? '');
    if (name.isEmpty) throw FormatError('invalid n');

    if (version != protocolVersion) {
      return TxtRecord(
        version: version,
        deviceId: id,
        name: name,
        platform: DevicePlatform.tryParse(a['p'] ?? ''),
        fingerprintHint: null,
      );
    }

    final platform = DevicePlatform.tryParse(a['p'] ?? '');
    if (platform == null) throw FormatError('invalid p');

    final fp = a['fp']?.toLowerCase();
    if (fp == null || !_hintPattern.hasMatch(fp)) {
      throw FormatError('invalid fp');
    }

    return TxtRecord(
      version: version,
      deviceId: id,
      name: name,
      platform: platform,
      fingerprintHint: fp,
    );
  }
}
