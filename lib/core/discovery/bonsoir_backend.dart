import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import 'mdns_backend.dart';

/// [MdnsBackend] on top of the `bonsoir` plugin (NWBrowser and
/// DNSServiceRegister on iOS, NsdManager on Android).
///
/// On Android, bonsoir holds a reference-counted Wi-Fi multicast lock from
/// each `start()` until the matching `stop()`, so the lock is held exactly
/// while browsing or advertising.
///
/// `printLogs` stays off: bonsoir's logs include device names from TXT
/// records (CLAUDE.md hard rule 7).
class BonsoirBackend implements MdnsBackend {
  BonsoirDiscovery? _discovery;
  BonsoirBroadcast? _broadcast;
  StreamController<MdnsEvent>? _events;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;

  @override
  Future<Stream<MdnsEvent>> startBrowsing() async {
    await stopBrowsing();
    final discovery = BonsoirDiscovery(
      type: crossDropServiceType,
      printLogs: false,
    );
    await discovery.initialize();
    final events = StreamController<MdnsEvent>();
    _discovery = discovery;
    _events = events;
    _sub = discovery.eventStream!.listen(
      (e) => _onEvent(discovery, events, e),
      onError: events.addError,
    );
    await discovery.start();
    return events.stream;
  }

  void _onEvent(
    BonsoirDiscovery discovery,
    StreamController<MdnsEvent> events,
    BonsoirDiscoveryEvent e,
  ) {
    switch (e) {
      case BonsoirDiscoveryServiceFoundEvent(:final service):
        // Small networks: resolve everything we find.
        service.resolve(discovery.serviceResolver);
      case BonsoirDiscoveryServiceResolvedEvent(:final service):
        events.add(_resolved(service));
      case BonsoirDiscoveryServiceUpdatedEvent(:final service):
        // An update may carry a new TXT without addresses; resolve again
        // in that case to learn the current address.
        if (service.hostAddresses.isEmpty) {
          service.resolve(discovery.serviceResolver);
        } else {
          events.add(_resolved(service));
        }
      case BonsoirDiscoveryServiceLostEvent(:final service):
        events.add(MdnsServiceLost(service.name));
      case BonsoirDiscoveryStartedEvent() ||
          BonsoirDiscoveryStoppedEvent() ||
          BonsoirDiscoveryServiceResolveFailedEvent() ||
          BonsoirDiscoveryUnknownEvent():
        break;
    }
  }

  static MdnsServiceResolved _resolved(BonsoirService s) => MdnsServiceResolved(
    s.name,
    hostAddresses: s.hostAddresses,
    port: s.port,
    attributes: s.attributes,
  );

  @override
  Future<void> stopBrowsing() async {
    final discovery = _discovery;
    _discovery = null;
    await _sub?.cancel();
    _sub = null;
    await _events?.close();
    _events = null;
    if (discovery != null && !discovery.isStopped) await discovery.stop();
  }

  @override
  Future<void> startAdvertising(MdnsAdvertisement ad) async {
    await stopAdvertising();
    final broadcast = BonsoirBroadcast(
      printLogs: false,
      service: BonsoirService(
        name: ad.serviceName,
        type: crossDropServiceType,
        port: ad.port,
        attributes: ad.attributes,
      ),
    );
    await broadcast.initialize();
    await broadcast.start();
    _broadcast = broadcast;
  }

  @override
  Future<void> stopAdvertising() async {
    final broadcast = _broadcast;
    _broadcast = null;
    if (broadcast != null && !broadcast.isStopped) await broadcast.stop();
  }
}
