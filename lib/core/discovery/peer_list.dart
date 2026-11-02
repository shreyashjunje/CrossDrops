import '../protocol/connect_payload.dart';
import '../protocol/models.dart';
import '../security/device_identity.dart';
import 'txt_record.dart';

/// A CrossDrop device seen on the local network.
class Peer {
  const Peer({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.host,
    required this.port,
    required this.fingerprintHint,
    required this.version,
  });

  final String deviceId;
  final String name;

  /// Null when [version] is not supported.
  final DevicePlatform? platform;

  /// Dotted IPv4 on a local network.
  final String host;
  final int port;

  /// First 16 hex characters of the peer's certificate SHA-256. A hint
  /// only: anyone on the network can advertise any value.
  final String? fingerprintHint;
  final int version;

  /// False when the peer speaks a protocol version this app does not, so
  /// the UI shows "needs update" instead of connecting.
  bool get isSupported => version == protocolVersion;

  @override
  bool operator ==(Object other) =>
      other is Peer &&
      other.deviceId == deviceId &&
      other.name == name &&
      other.platform == platform &&
      other.host == host &&
      other.port == port &&
      other.fingerprintHint == fingerprintHint &&
      other.version == version;

  @override
  int get hashCode => Object.hash(
    deviceId,
    name,
    platform,
    host,
    port,
    fingerprintHint,
    version,
  );
}

sealed class PeerChange {
  const PeerChange(this.deviceId);
  final String deviceId;
}

class PeerAdded extends PeerChange {
  PeerAdded(this.peer) : super(peer.deviceId);
  final Peer peer;
}

class PeerUpdated extends PeerChange {
  PeerUpdated(this.peer) : super(peer.deviceId);
  final Peer peer;
}

class PeerRemoved extends PeerChange {
  const PeerRemoved(super.deviceId);
}

/// The list of nearby devices, keyed by device id, built from mDNS events.
///
/// Pure state machine: each method returns the changes it caused, so it can
/// be tested without a network.
///
/// - Several service names can point to one device (for example after it
///   re-advertises under a new name); the device is removed only when the
///   last one is lost.
/// - Records with a bad TXT, without a local IPv4 address, or with this
///   device's own id are ignored.
class PeerList {
  PeerList({required this.ownDeviceId});

  final String ownDeviceId;
  final Map<String, Peer> _peers = {};
  final Map<String, String> _idByService = {};

  Map<String, Peer> get peers => Map.unmodifiable(_peers);

  /// True once this device's own advertisement has been seen. On iOS this
  /// shows that the Local Network permission is granted.
  bool get sawSelf => _sawSelf;
  bool _sawSelf = false;

  List<PeerChange> resolved(
    String serviceName, {
    required List<String> hostAddresses,
    required int port,
    required Map<String, String> attributes,
  }) {
    final TxtRecord txt;
    try {
      txt = TxtRecord.decode(attributes);
    } on FormatError {
      return _detach(serviceName);
    }
    if (txt.deviceId == ownDeviceId) {
      _sawSelf = true;
      return _detach(serviceName);
    }
    final host = _pickHost(hostAddresses);
    if (host == null || port < 1 || port > 65535) return _detach(serviceName);

    final changes = <PeerChange>[];
    final previousId = _idByService[serviceName];
    if (previousId != null && previousId != txt.deviceId) {
      changes.addAll(_detach(serviceName));
    }
    _idByService[serviceName] = txt.deviceId;

    final peer = Peer(
      deviceId: txt.deviceId,
      name: txt.name,
      platform: txt.platform,
      host: host,
      port: port,
      fingerprintHint: txt.fingerprintHint,
      version: txt.version,
    );
    final existing = _peers[txt.deviceId];
    if (existing == null) {
      changes.add(PeerAdded(peer));
    } else if (existing != peer) {
      changes.add(PeerUpdated(peer));
    }
    _peers[txt.deviceId] = peer;
    return changes;
  }

  List<PeerChange> lost(String serviceName) => _detach(serviceName);

  /// Removes a device that did not answer (for example a failed connect
  /// after it left without a goodbye packet).
  List<PeerChange> unreachable(String deviceId) {
    _idByService.removeWhere((_, id) => id == deviceId);
    return _peers.remove(deviceId) == null ? const [] : [PeerRemoved(deviceId)];
  }

  /// Removes everything, for example when browsing restarts.
  List<PeerChange> clear() {
    final changes = [for (final id in _peers.keys) PeerRemoved(id)];
    _peers.clear();
    _idByService.clear();
    _sawSelf = false;
    return changes;
  }

  List<PeerChange> _detach(String serviceName) {
    final id = _idByService.remove(serviceName);
    if (id == null || _idByService.containsValue(id)) return const [];
    return _peers.remove(id) == null ? const [] : [PeerRemoved(id)];
  }

  static String? _pickHost(List<String> addresses) {
    for (final a in addresses) {
      final octets = parseIPv4(a);
      if (octets != null && isLocalIPv4(octets)) return a;
    }
    return null;
  }
}
