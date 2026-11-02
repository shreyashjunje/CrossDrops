import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/client/peer_check.dart';
import '../../core/client/upload_client.dart';
import '../../core/discovery/discovery_service.dart';
import '../../core/discovery/network_monitor.dart';
import '../../core/discovery/peer_list.dart';
import '../../core/protocol/connect_payload.dart';
import '../../platform/local_network.dart';

/// How long to search before suggesting QR or manual entry and, on iOS,
/// checking the Local Network permission (ARCHITECTURE.md, "Connection
/// flow": about 5 s).
final nearbySearchTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 5),
);

/// Only iOS has a Local Network permission to check.
final checkLocalNetworkPermissionProvider = Provider<bool>(
  (ref) => Platform.isIOS,
);

/// Checks a target before sending; replaced in tests.
final peerCheckProvider =
    Provider<Future<ConnectTarget> Function(ConnectTarget)>((ref) => checkPeer);

class NearbyState {
  const NearbyState({
    this.peers = const {},
    this.searching = true,
    this.searchedLong = false,
    this.permission,
    this.hasNetwork = true,
    this.error,
  });

  final Map<String, Peer> peers;
  final bool searching;

  /// The search timeout passed with nobody found.
  final bool searchedLong;

  /// Result of the last Local Network probe (iOS), if one ran.
  final LocalNetworkStatus? permission;

  /// False when this phone has no Wi-Fi or hotspot address.
  final bool hasNetwork;

  /// Browsing could not start.
  final String? error;

  bool get permissionDenied => permission == LocalNetworkStatus.denied;

  /// Peers sorted by name, then id, so the list does not jump around.
  List<Peer> get sortedPeers => peers.values.toList()
    ..sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.deviceId.compareTo(b.deviceId);
    });

  NearbyState copyWith({
    Map<String, Peer>? peers,
    bool? searching,
    bool? searchedLong,
    LocalNetworkStatus? Function()? permission,
    bool? hasNetwork,
    String? Function()? error,
  }) => NearbyState(
    peers: peers ?? this.peers,
    searching: searching ?? this.searching,
    searchedLong: searchedLong ?? this.searchedLong,
    permission: permission != null ? permission() : this.permission,
    hasNetwork: hasNetwork ?? this.hasNetwork,
    error: error != null ? error() : this.error,
  );
}

final nearbyControllerProvider =
    NotifierProvider.autoDispose<NearbyController, NearbyState>(
      NearbyController.new,
    );

/// Browses for nearby devices while the Nearby screen is open.
///
/// Browsing stops when the app goes to the background, which also releases
/// the Android multicast lock, and starts again on return.
class NearbyController extends Notifier<NearbyState> {
  PeerBrowser? _browser;
  StreamSubscription<PeerChange>? _changesSub;
  NetworkMonitor? _monitor;
  StreamSubscription<List<LocalAddress>>? _networkSub;
  AppLifecycleListener? _lifecycle;
  Timer? _searchTimer;

  @override
  NearbyState build() {
    ref.onDispose(_stop);
    unawaited(_start());
    return const NearbyState();
  }

  Future<void> _start() async {
    final device = await ref.read(identityProvider.future);
    if (!ref.mounted) return;
    final browser = _browser = PeerBrowser(
      ref.read(mdnsBackendProvider),
      ownDeviceId: device.deviceId,
    );
    _changesSub = browser.changes.listen(_onChange);
    _lifecycle = AppLifecycleListener(onPause: _onPause, onResume: _onResume);

    final monitor = _monitor = NetworkMonitor(
      connectivityEvents: ref.read(connectivityEventsProvider),
    );
    await monitor.start();
    if (!ref.mounted) return;
    _networkSub = monitor.changes.listen(_onNetworkChanged);
    state = state.copyWith(hasNetwork: monitor.current.isNotEmpty);

    await _startBrowsing();
  }

  Future<void> _stop() async {
    _searchTimer?.cancel();
    _lifecycle?.dispose();
    await _networkSub?.cancel();
    await _monitor?.dispose();
    await _changesSub?.cancel();
    await _browser?.dispose();
  }

  Future<void> _startBrowsing() async {
    try {
      await _browser?.start();
      if (!ref.mounted) return;
      state = state.copyWith(searching: true, error: () => null);
      _armSearchTimer();
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(
        searching: false,
        error: () => 'Nearby search could not start. Use the QR code instead.',
      );
    }
  }

  void _armSearchTimer() {
    _searchTimer?.cancel();
    _searchTimer = Timer(
      ref.read(nearbySearchTimeoutProvider),
      _onSearchTimeout,
    );
  }

  Future<void> _onSearchTimeout() async {
    if (!ref.mounted || state.peers.isNotEmpty) return;
    state = state.copyWith(searchedLong: true);
    await _probePermission();
  }

  /// iOS: nothing found, so check whether Local Network is denied.
  Future<void> _probePermission() async {
    if (!ref.read(checkLocalNetworkPermissionProvider)) return;
    final status = await ref.read(localNetworkProvider).probe();
    if (!ref.mounted) return;
    // Peers that appeared meanwhile prove access, whatever the probe said.
    state = state.copyWith(
      permission: () =>
          state.peers.isNotEmpty ? LocalNetworkStatus.granted : status,
    );
  }

  void _onChange(PeerChange change) {
    if (!ref.mounted) return;
    final peers = Map.of(state.peers);
    switch (change) {
      case PeerAdded(:final peer) || PeerUpdated(:final peer):
        peers[peer.deviceId] = peer;
      case PeerRemoved(:final deviceId):
        peers.remove(deviceId);
    }
    state = state.copyWith(
      peers: peers,
      permission: peers.isNotEmpty && state.permissionDenied
          ? () => LocalNetworkStatus.granted
          : null,
    );
  }

  Future<void> _onNetworkChanged(List<LocalAddress> addresses) async {
    if (!ref.mounted) return;
    state = state.copyWith(hasNetwork: addresses.isNotEmpty);
    await refresh();
  }

  Future<void> _onPause() async {
    _searchTimer?.cancel();
    await _browser?.stop();
  }

  Future<void> _onResume() async {
    if (!ref.mounted) return;
    await _startBrowsing();
    // Back from Settings, the permission may have changed. The explanation
    // stays up until the probe says otherwise or a peer appears.
    if (state.permissionDenied) await _probePermission();
  }

  /// Starts searching again with an empty list.
  Future<void> refresh() async {
    if (!ref.mounted) return;
    state = state.copyWith(
      searchedLong: false,
      permission: () => null,
      peers: const {},
    );
    await _browser?.stop();
    await _startBrowsing();
  }

  /// Checks a nearby device before opening Send. A device that does not
  /// answer is dropped from the list. Throws [UploadException].
  Future<ConnectTarget> connectToPeer(Peer peer) async {
    try {
      return await ref.read(peerCheckProvider)(
        ConnectTarget(
          host: peer.host,
          port: peer.port,
          deviceId: peer.deviceId,
          name: peer.name,
          fingerprintHint: peer.fingerprintHint,
        ),
      );
    } on UploadException catch (e) {
      if (e.code == 'network' || e.code == 'identity_mismatch') {
        _browser?.markUnreachable(peer.deviceId);
      }
      rethrow;
    }
  }

  /// Checks the device from a scanned QR code. Throws [UploadException].
  Future<ConnectTarget> connectToQr(ConnectPayload qr) =>
      ref.read(peerCheckProvider)(
        ConnectTarget(
          host: qr.ip,
          port: qr.port,
          deviceId: qr.deviceId,
          name: qr.name,
          fingerprint: qr.fingerprint,
        ),
      );

  /// Checks a typed address. Throws [UploadException].
  Future<ConnectTarget> connectToAddress(String host, int port) =>
      ref.read(peerCheckProvider)(ConnectTarget(host: host, port: port));
}
