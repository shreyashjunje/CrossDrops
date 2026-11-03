import '../protocol/connect_payload.dart';
import 'network_monitor.dart';

/// An IPv4 address with its prefix length, e.g. 192.168.43.1/24.
class InterfaceAddress {
  const InterfaceAddress(this.name, this.ip, this.prefix);
  final String name;
  final String ip;
  final int prefix;

  @override
  bool operator ==(Object other) =>
      other is InterfaceAddress &&
      other.name == name &&
      other.ip == ip &&
      other.prefix == prefix;

  @override
  int get hashCode => Object.hash(name, ip, prefix);

  @override
  String toString() => '$ip/$prefix ($name)';
}

int? _toInt(String ip) {
  final o = parseIPv4(ip);
  if (o == null) return null;
  return (o[0] << 24) | (o[1] << 16) | (o[2] << 8) | o[3];
}

/// True if [a] and [b] are in the same IPv4 network of [prefix] bits.
bool sameSubnet(String a, String b, int prefix) {
  if (prefix < 0 || prefix > 32) return false;
  final x = _toInt(a);
  final y = _toInt(b);
  if (x == null || y == null) return false;
  if (prefix == 0) return true;
  final mask = (0xffffffff << (32 - prefix)) & 0xffffffff;
  return (x & mask) == (y & mask);
}

/// The local address on the same network as [peerIp], or null. A /32 or
/// /31 never counts: such a link has no neighbours to share.
InterfaceAddress? addressSharingSubnet(
  List<InterfaceAddress> mine,
  String peerIp,
) {
  for (final a in mine) {
    if (a.prefix >= 1 && a.prefix <= 30 && sameSubnet(a.ip, peerIp, a.prefix)) {
      return a;
    }
  }
  return null;
}

/// iPhone Personal Hotspot's network: iOS uses 172.20.10.0/28, with the
/// iPhone at .1. Observed behaviour, not documented by Apple, so it only
/// drives a hint in the guide, never a decision.
bool looksLikeIphoneHotspot(String ip) => sameSubnet(ip, '172.20.10.1', 28);

// Hotspot (soft AP) interface names seen on Android phones.
final RegExp _hotspotInterface = RegExp(r'^(swlan|ap|softap|wlan[1-9]|wigig)');

/// After starting a hotspot, finds the address this phone has on it.
///
/// The hotspot interface has no public API, so compare the addresses from
/// [before] the start with [after]: a new address on a hotspot-like
/// interface wins, then any new reachable address, then an address on a
/// hotspot-like interface that was already there (a hotspot shared with
/// another app). Null while the interface has no address yet.
LocalAddress? pickHotspotAddress(
  List<LocalAddress> before,
  List<LocalAddress> after,
) {
  final reachable = reachableAddresses(after);
  final fresh = [
    for (final a in reachable)
      if (!before.contains(a)) a,
  ];
  for (final a in fresh) {
    if (_hotspotInterface.hasMatch(a.interfaceName)) return a;
  }
  if (fresh.isNotEmpty) return fresh.first;
  for (final a in reachable) {
    if (_hotspotInterface.hasMatch(a.interfaceName)) return a;
  }
  return null;
}

/// Android network binding rule (D-056).
///
/// Bind only in the case that needs it: Wi-Fi is connected but has no
/// internet, and Android made something else (mobile data) the default,
/// so new sockets would leave over mobile data. Otherwise clear the
/// binding: a validated or default Wi-Fi needs none, and a VPN that is the
/// default must keep routing (ARCHITECTURE.md, scenario 6).
bool shouldBindToWifi({
  required bool connected,
  required bool validated,
  required bool isDefault,
}) => connected && !validated && !isDefault;
