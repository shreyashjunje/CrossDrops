import 'dart:async';

import 'discovery_service.dart';
import 'mdns_backend.dart';
import 'peer_list.dart';

/// Finds a device's current address by its id (ARCHITECTURE.md, "Peer IP
/// changes": rediscover by device id). Used to resume a transfer after the
/// receiver's IP or port changed, for example after its app restarted.
///
/// Browses with its own [backend] for at most [timeout]. Returns null if
/// the device is not advertising (its Receive screen is closed).
Future<({String host, int port})?> locatePeer(
  MdnsBackend backend, {
  required String deviceId,
  required String ownDeviceId,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final browser = PeerBrowser(backend, ownDeviceId: ownDeviceId);
  try {
    final found = browser.changes
        .where((c) => c.deviceId == deviceId)
        .map(
          (c) => switch (c) {
            PeerAdded(:final peer) || PeerUpdated(:final peer) => peer,
            PeerRemoved() => null,
          },
        )
        .where((p) => p != null)
        .first
        // Closing the browser ends the stream: "not found", not an error.
        .then<Peer?>((p) => p, onError: (Object _) => null);
    await browser.start();
    final peer =
        browser.peers[deviceId] ??
        await found.timeout(timeout, onTimeout: () => null);
    return peer == null ? null : (host: peer.host, port: peer.port);
  } catch (_) {
    // Best effort: the caller keeps retrying the old address.
    return null;
  } finally {
    await browser.dispose();
  }
}
