/// The mDNS / DNS-SD operations CrossDrop needs, behind an interface so the
/// discovery logic can be tested without a network (CLAUDE.md hard rule 9).
library;

/// Service type from ARCHITECTURE.md, "Discovery advertisement".
const String crossDropServiceType = '_crossdrop._tcp';

sealed class MdnsEvent {
  const MdnsEvent(this.serviceName);

  /// The DNS-SD instance name, unique per service on the network.
  final String serviceName;
}

/// A service was found and resolved to addresses and a port.
class MdnsServiceResolved extends MdnsEvent {
  const MdnsServiceResolved(
    super.serviceName, {
    required this.hostAddresses,
    required this.port,
    required this.attributes,
  });

  final List<String> hostAddresses;
  final int port;
  final Map<String, String> attributes;
}

/// A service went away (goodbye packet or the OS cache expired).
class MdnsServiceLost extends MdnsEvent {
  const MdnsServiceLost(super.serviceName);
}

class MdnsAdvertisement {
  const MdnsAdvertisement({
    required this.serviceName,
    required this.port,
    required this.attributes,
  });

  final String serviceName;
  final int port;
  final Map<String, String> attributes;
}

abstract interface class MdnsBackend {
  /// Starts browsing for [crossDropServiceType]. Events arrive on the
  /// returned stream until [stopBrowsing] is called.
  Future<Stream<MdnsEvent>> startBrowsing();

  Future<void> stopBrowsing();

  /// Registers this device's service. Replaces any earlier advertisement.
  Future<void> startAdvertising(MdnsAdvertisement advertisement);

  Future<void> stopAdvertising();
}
