import 'dart:convert';

import '../security/device_identity.dart';
import 'device_name.dart';
import 'models.dart';

/// Why a scanned or typed payload was refused. Messages never include the
/// payload itself (CLAUDE.md hard rule 7).
enum ConnectPayloadError {
  /// Not a CrossDrop code at all (other scheme, host, or shape).
  notCrossDrop,

  /// A CrossDrop code from a newer protocol version.
  unsupportedVersion,

  /// A CrossDrop code with a missing, repeated or invalid field.
  invalid,
}

class ConnectPayloadException implements Exception {
  const ConnectPayloadException(this.error, this.detail);
  final ConnectPayloadError error;

  /// Which check failed, e.g. `ip`. Safe to log.
  final String detail;

  @override
  String toString() => 'ConnectPayloadException(${error.name}: $detail)';
}

/// Longest payload accepted, in characters. A real one is about 200.
const int maxConnectPayloadLength = 1024;

final RegExp _ipv4 = RegExp(
  r'^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.'
  r'(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$',
);
final RegExp _port = RegExp(r'^[1-9][0-9]{0,4}$');
final RegExp _fingerprint = RegExp(r'^[0-9a-f]{64}$');
final RegExp _version = RegExp(r'^[1-9][0-9]{0,2}$');

// Uri.tryParse silently turns a stray '%' into '%25'; refuse it instead.
final RegExp _badPercent = RegExp(r'%(?![0-9A-Fa-f]{2})');

/// True for IPv4 addresses on a local network: 10/8, 172.16/12,
/// 192.168/16, 169.254/16 (link-local) and 100.64/10 (carrier-grade NAT,
/// used by some hotspots). Anything else would mean connecting outside
/// the local network (CLAUDE.md hard rule 8).
bool isLocalIPv4(List<int> o) {
  if (o.length != 4) return false;
  return o[0] == 10 ||
      (o[0] == 172 && o[1] >= 16 && o[1] <= 31) ||
      (o[0] == 192 && o[1] == 168) ||
      (o[0] == 169 && o[1] == 254) ||
      (o[0] == 100 && o[1] >= 64 && o[1] <= 127);
}

/// Parses a dotted IPv4 literal (no leading zeros, no hostnames).
List<int>? parseIPv4(String s) {
  final m = _ipv4.firstMatch(s);
  if (m == null) return null;
  final octets = [for (var i = 1; i <= 4; i++) int.parse(m.group(i)!)];
  return octets.any((o) => o > 255) ? null : octets;
}

/// Wi-Fi security of a hotspot in the QR code (`wsec`).
enum WifiSecurity {
  wpa2('wpa2'),

  /// WPA3 with WPA2 fallback (transition mode).
  wpa3Transition('wpa3t'),
  wpa3('wpa3');

  const WifiSecurity(this.code);
  final String code;

  static WifiSecurity? fromCode(String code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// The Android hotspot's Wi-Fi name and password, carried in the QR code
/// in hotspot mode (`ws`, `wp`, `wsec`). Never logged (CLAUDE.md hard
/// rule 7): [toString] leaves both out.
class WifiCredentials {
  const WifiCredentials({
    required this.ssid,
    required this.password,
    this.security = WifiSecurity.wpa2,
  });

  final String ssid;
  final String password;
  final WifiSecurity security;

  @override
  bool operator ==(Object other) =>
      other is WifiCredentials &&
      other.ssid == ssid &&
      other.password == password &&
      other.security == security;

  @override
  int get hashCode => Object.hash(ssid, password, security);

  @override
  String toString() => 'WifiCredentials(${security.code})';
}

// WPA passphrase: 8-63 printable ASCII characters (IEEE 802.11i).
final RegExp _wpaPassphrase = RegExp(r'^[\x20-\x7e]{8,63}$');

/// True if [ssid] is 1-32 bytes of UTF-8 with no control characters.
bool isValidSsid(String ssid) {
  if (ssid.isEmpty) return false;
  if (ssid.runes.any((r) => r < 0x20 || r == 0x7f)) return false;
  return utf8.encode(ssid).length <= 32;
}

/// The QR code payload (ARCHITECTURE.md, "QR code payload"):
/// `crossdrop://connect?v=1&ip=...&port=...&fp=...&id=...&n=...`, plus
/// `ws`, `wp` and `wsec` in hotspot mode.
class ConnectPayload {
  const ConnectPayload({
    required this.ip,
    required this.port,
    required this.fingerprint,
    required this.deviceId,
    required this.name,
    this.wifi,
  });

  /// Dotted IPv4 on a local network.
  final String ip;
  final int port;

  /// Full lowercase hex SHA-256 of the receiver's certificate.
  final String fingerprint;
  final String deviceId;
  final String name;

  /// The hotspot to join first; null outside hotspot mode.
  final WifiCredentials? wifi;

  String toUri() => Uri(
    scheme: 'crossdrop',
    host: 'connect',
    queryParameters: {
      'v': '$protocolVersion',
      'ip': ip,
      'port': '$port',
      'fp': fingerprint,
      'id': deviceId,
      'n': name,
      if (wifi case final w?) ...{
        'ws': w.ssid,
        'wp': w.password,
        'wsec': w.security.code,
      },
    },
  ).toString();

  /// Parses a scanned QR code. Throws [ConnectPayloadException].
  ///
  /// Unknown parameters are ignored so later versions can add fields; every
  /// known one must appear once. The hotspot fields are optional, but `ws`
  /// and `wp` come together.
  static ConnectPayload parse(String raw) {
    Never fail(ConnectPayloadError e, String detail) =>
        throw ConnectPayloadException(e, detail);

    final text = raw.trim();
    if (text.length > maxConnectPayloadLength) {
      fail(ConnectPayloadError.invalid, 'too long');
    }
    if (text.codeUnits.any((c) => c < 0x21 || c == 0x7f)) {
      fail(ConnectPayloadError.notCrossDrop, 'whitespace or control');
    }

    if (_badPercent.hasMatch(text)) {
      fail(ConnectPayloadError.invalid, 'encoding');
    }

    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.scheme != 'crossdrop' ||
        uri.host != 'connect' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      fail(ConnectPayloadError.notCrossDrop, 'shape');
    }

    final Map<String, List<String>> query;
    try {
      query = uri.queryParametersAll;
    } on ArgumentError {
      fail(ConnectPayloadError.invalid, 'encoding');
    } on FormatException {
      fail(ConnectPayloadError.invalid, 'encoding');
    }

    String? optional(String key) {
      final values = query[key];
      if (values == null || values.isEmpty) return null;
      if (values.length > 1) fail(ConnectPayloadError.invalid, 'repeated $key');
      return values.single;
    }

    String field(String key) =>
        optional(key) ?? fail(ConnectPayloadError.invalid, 'missing $key');

    final v = field('v');
    if (!_version.hasMatch(v)) fail(ConnectPayloadError.invalid, 'v');
    if (int.parse(v) != protocolVersion) {
      fail(ConnectPayloadError.unsupportedVersion, 'v');
    }

    final ip = field('ip');
    final octets = parseIPv4(ip);
    if (octets == null || !isLocalIPv4(octets)) {
      fail(ConnectPayloadError.invalid, 'ip');
    }

    final portText = field('port');
    final port = _port.hasMatch(portText) ? int.parse(portText) : 0;
    if (port < 1 || port > 65535) fail(ConnectPayloadError.invalid, 'port');

    final fp = field('fp').toLowerCase();
    if (!_fingerprint.hasMatch(fp)) fail(ConnectPayloadError.invalid, 'fp');

    final id = field('id').toLowerCase();
    if (!isValidDeviceId(id)) fail(ConnectPayloadError.invalid, 'id');

    final name = sanitizeDeviceName(field('n'));
    if (name.isEmpty) fail(ConnectPayloadError.invalid, 'n');

    final ssid = optional('ws');
    final password = optional('wp');
    final securityCode = optional('wsec');
    WifiCredentials? wifi;
    if (ssid != null || password != null || securityCode != null) {
      if (ssid == null || !isValidSsid(ssid)) {
        fail(ConnectPayloadError.invalid, 'ws');
      }
      if (password == null || !_wpaPassphrase.hasMatch(password)) {
        fail(ConnectPayloadError.invalid, 'wp');
      }
      final security = securityCode == null
          ? WifiSecurity.wpa2
          : WifiSecurity.fromCode(securityCode) ??
                fail(ConnectPayloadError.invalid, 'wsec');
      wifi = WifiCredentials(
        ssid: ssid,
        password: password,
        security: security,
      );
    }

    return ConnectPayload(
      ip: ip,
      port: port,
      fingerprint: fp,
      deviceId: id,
      name: name,
      wifi: wifi,
    );
  }
}
