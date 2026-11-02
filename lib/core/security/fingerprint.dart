import 'package:crypto/crypto.dart';

/// Length of a full fingerprint in hex characters (SHA-256).
const int fingerprintLength = 64;

final RegExp _fingerprintPattern = RegExp(r'^[0-9a-f]{64}$');

/// The device identity: lowercase hex SHA-256 of the certificate's DER
/// bytes (ARCHITECTURE.md, "Device identity").
String certificateFingerprint(List<int> der) => sha256.convert(der).toString();

bool isValidFingerprint(String value) => _fingerprintPattern.hasMatch(value);

/// Compares two fingerprints without an early exit, so the time taken does
/// not tell how many leading characters matched.
bool fingerprintsEqual(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// The first 16 hex characters in groups of four, for settings screens:
/// `a1b2 c3d4 e5f6 0718`. Never use it for a security decision.
String shortFingerprint(String fingerprint) {
  final head = fingerprint.substring(0, 16);
  return [for (var i = 0; i < head.length; i += 4) head.substring(i, i + 4)]
      .join(' ');
}
