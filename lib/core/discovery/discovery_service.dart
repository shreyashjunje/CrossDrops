import 'dart:async';

import '../log.dart';
import 'mdns_backend.dart';
import 'peer_list.dart';
import 'txt_record.dart';

/// DNS-SD instance name for a device: `CrossDrop-` plus the first 8
/// characters of its id. Unique enough to avoid name clashes, and carries no
/// personal data (the user's device name is only in the TXT record).
String serviceNameFor(String deviceId) =>
    'CrossDrop-${deviceId.substring(0, 8)}';

/// Browses for other CrossDrop devices and keeps a [PeerList].
class PeerBrowser {
  PeerBrowser(this._backend, {required String ownDeviceId})
    : _list = PeerList(ownDeviceId: ownDeviceId);

  final MdnsBackend _backend;
  final PeerList _list;
  final StreamController<PeerChange> _changes = StreamController.broadcast();
  StreamSubscription<MdnsEvent>? _sub;
  bool _running = false;

  /// Add, update and remove events, keyed by device id.
  Stream<PeerChange> get changes => _changes.stream;

  Map<String, Peer> get peers => _list.peers;

  bool get isRunning => _running;

  /// See [PeerList.sawSelf].
  bool get sawSelf => _list.sawSelf;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      final events = await _backend.startBrowsing();
      _sub = events.listen(_onEvent, onError: _onError);
      logEvent('discovery', 'browsing started');
    } catch (e) {
      _running = false;
      rethrow;
    }
  }

  /// Stops browsing and clears the list.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _sub?.cancel();
    _sub = null;
    await _backend.stopBrowsing();
    _emit(_list.clear());
    logEvent('discovery', 'browsing stopped');
  }

  /// Starts again with an empty list (network change, pull to refresh).
  Future<void> restart() async {
    await stop();
    await start();
  }

  /// Drops a device that did not answer.
  void markUnreachable(String deviceId) => _emit(_list.unreachable(deviceId));

  Future<void> dispose() async {
    await stop();
    await _changes.close();
  }

  void _onEvent(MdnsEvent e) {
    switch (e) {
      case MdnsServiceResolved(
        :final serviceName,
        :final hostAddresses,
        :final port,
        :final attributes,
      ):
        _emit(
          _list.resolved(
            serviceName,
            hostAddresses: hostAddresses,
            port: port,
            attributes: attributes,
          ),
        );
      case MdnsServiceLost(:final serviceName):
        _emit(_list.lost(serviceName));
    }
  }

  void _onError(Object error) {
    // Error details can include service names; log the type only.
    logEvent('discovery', 'browse error: ${error.runtimeType}');
  }

  void _emit(List<PeerChange> changes) {
    for (final c in changes) {
      logEvent('discovery', '${c.runtimeType} ${c.deviceId.substring(0, 8)}');
      _changes.add(c);
    }
  }
}

/// Advertises this device's `_crossdrop._tcp` service.
class Advertiser {
  Advertiser(this._backend);

  final MdnsBackend _backend;
  MdnsAdvertisement? _current;

  bool get isAdvertising => _current != null;

  Future<void> start({required TxtRecord txt, required int port}) async {
    final ad = MdnsAdvertisement(
      serviceName: serviceNameFor(txt.deviceId),
      port: port,
      attributes: txt.encode(),
    );
    await _backend.startAdvertising(ad);
    _current = ad;
    logEvent('discovery', 'advertising on port $port');
  }

  /// Registers the same service again (after a network change).
  Future<void> restart() async {
    final ad = _current;
    if (ad == null) return;
    await _backend.stopAdvertising();
    await _backend.startAdvertising(ad);
    logEvent('discovery', 'advertising restarted');
  }

  Future<void> stop() async {
    if (_current == null) return;
    _current = null;
    await _backend.stopAdvertising();
    logEvent('discovery', 'advertising stopped');
  }
}
