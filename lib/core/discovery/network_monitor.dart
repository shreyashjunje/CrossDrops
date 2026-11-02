import 'dart:async';
import 'dart:io';

import '../log.dart';
import '../protocol/connect_payload.dart';

/// An IPv4 address of this device and the interface that holds it.
class LocalAddress {
  const LocalAddress(this.ip, this.interfaceName);
  final String ip;
  final String interfaceName;

  @override
  bool operator ==(Object other) =>
      other is LocalAddress &&
      other.ip == ip &&
      other.interfaceName == interfaceName;

  @override
  int get hashCode => Object.hash(ip, interfaceName);

  @override
  String toString() => '$ip ($interfaceName)';
}

// Mobile data and VPN interfaces. Their addresses can look private
// (10.x, 100.64.x) but other phones cannot reach them.
final RegExp _excludedInterface = RegExp(
  r'^(rmnet|v4-rmnet|ccmni|pdp_ip|tun|utun|ipsec|ppp|dummy|lo)',
);

// Wi-Fi client and hotspot interfaces, best first.
final List<RegExp> _preferredInterface = [
  RegExp(r'^(wlan|en0$)'),
  RegExp(r'^(swlan|ap|softap|bridge|wlan)'),
  RegExp(r'^en'),
];

/// Local IPv4 addresses other phones may reach: local ranges only, mobile
/// data and VPN interfaces left out.
List<LocalAddress> reachableAddresses(List<LocalAddress> all) => [
  for (final a in all)
    if (!_excludedInterface.hasMatch(a.interfaceName) && _isLocal(a.ip)) a,
];

bool _isLocal(String ip) {
  final octets = parseIPv4(ip);
  return octets != null && isLocalIPv4(octets);
}

/// The address to put in the QR code: Wi-Fi first, then hotspot, then any
/// other reachable address. Null if there is none.
LocalAddress? pickQrAddress(List<LocalAddress> all) {
  final candidates = reachableAddresses(all);
  for (final pattern in _preferredInterface) {
    for (final a in candidates) {
      if (pattern.hasMatch(a.interfaceName)) return a;
    }
  }
  return candidates.isEmpty ? null : candidates.first;
}

/// Lists this device's IPv4 addresses with `dart:io`.
Future<List<LocalAddress>> listLocalAddresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  );
  return [
    for (final i in interfaces)
      for (final a in i.addresses) LocalAddress(a.address, i.name),
  ];
}

/// Reports when the network changes, so advertising can restart and the QR
/// code can show the new address.
///
/// Two signals: connectivity events from the OS (a Wi-Fi switch may keep
/// the same IP, so every event counts), and a poll of the address list
/// (an IP change may come without an event). Both are debounced so one
/// switch gives one change.
class NetworkMonitor {
  NetworkMonitor({
    required this.connectivityEvents,
    this.listAddresses = listLocalAddresses,
    this.pollInterval = const Duration(seconds: 3),
    this.debounce = const Duration(seconds: 1),
  });

  final Stream<void> connectivityEvents;
  final Future<List<LocalAddress>> Function() listAddresses;
  final Duration pollInterval;
  final Duration debounce;

  final StreamController<List<LocalAddress>> _changes =
      StreamController.broadcast();
  StreamSubscription<void>? _sub;
  Timer? _poll;
  Timer? _debounceTimer;
  Set<LocalAddress> _last = {};
  List<LocalAddress> _current = const [];
  bool _forceNext = false;

  /// Emits the new reachable addresses after each change.
  Stream<List<LocalAddress>> get changes => _changes.stream;

  /// Reachable addresses as of the last check.
  List<LocalAddress> get current => _current;

  Future<void> start() async {
    if (_sub != null) return;
    _current = reachableAddresses(await listAddresses());
    _last = _current.toSet();
    _sub = connectivityEvents.listen((_) {
      _forceNext = true;
      _schedule();
    });
    _poll = Timer.periodic(pollInterval, (_) => _schedule());
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _poll?.cancel();
    _debounceTimer?.cancel();
  }

  Future<void> dispose() async {
    await stop();
    await _changes.close();
  }

  void _schedule() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, _check);
  }

  Future<void> _check() async {
    if (_sub == null) return;
    final List<LocalAddress> now;
    try {
      now = reachableAddresses(await listAddresses());
    } on SocketException {
      return;
    }
    final set = now.toSet();
    final changed =
        _forceNext || set.length != _last.length || !set.containsAll(_last);
    _forceNext = false;
    _last = set;
    _current = now;
    if (changed && _sub != null) {
      logEvent('discovery', 'network changed: ${now.length} address(es)');
      _changes.add(now);
    }
  }
}
