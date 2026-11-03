import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/discovery/network_monitor.dart';
import '../../core/discovery/subnet.dart';
import '../../core/log.dart';
import '../../core/protocol/connect_payload.dart';
import '../../platform/hotspot.dart';
import '../receive/receive_host.dart';
import '../send/send_controller.dart';

/// Starts a hotspot from the app (Android, D-054).
final hotspotServiceProvider = Provider<HotspotService>(
  (ref) => Platform.isAndroid ? ChannelHotspotService() : const NoHotspot(),
);

/// This phone's IPv4 addresses; replaced in tests.
final localAddressesProvider = Provider<Future<List<LocalAddress>> Function()>(
  (ref) => listLocalAddresses,
);

/// True while a transfer runs in either direction.
final transfersActiveProvider = Provider.autoDispose<bool>((ref) {
  final sending = ref.watch(sendControllerProvider.select((s) => s.isRunning));
  final receiving = ref.watch(
    receiveStateProvider.select(
      (s) => s.sessions.values.any((x) => x.isActive),
    ),
  );
  return sending || receiving;
});

enum HotspotPhase { idle, starting, running, failed }

class HotspotState {
  const HotspotState({
    this.phase = HotspotPhase.idle,
    this.wifi,
    this.address,
    this.error,
    this.stopsAt,
  });

  final HotspotPhase phase;

  /// Name and password while running. Never logged.
  final WifiCredentials? wifi;

  /// This phone's address on the hotspot.
  final LocalAddress? address;

  /// One of [HotspotErrors], or `stopped` (by the user or the system) or
  /// `no_address`.
  final String? error;

  /// When the hotspot stops by itself after the last transfer ended.
  final DateTime? stopsAt;

  bool get isRunning => phase == HotspotPhase.running;
}

/// Owns the Android hotspot while the hotspot screen is open (D-054).
///
/// - Start finds this phone's address on the new network by comparing the
///   address list before and after.
/// - When the last transfer ends, the hotspot stops after [idleStop];
///   [keepOn] cancels that.
/// - Leaving the screen disposes this controller, which stops the hotspot.
class HotspotController extends Notifier<HotspotState> {
  static const idleStop = Duration(seconds: 60);
  static const addressWait = Duration(seconds: 10);
  static const addressPoll = Duration(milliseconds: 500);

  late HotspotService _service;
  StreamSubscription<void>? _stoppedSub;
  Timer? _idleTimer;
  bool _wasActive = false;

  /// The service holds a hotspot (or is starting one). Not `state`:
  /// onDispose may not read it.
  bool _live = false;

  @override
  HotspotState build() {
    _service = ref.read(hotspotServiceProvider);
    _stoppedSub = _service.stopped.listen((_) => _onStoppedElsewhere());
    final active = ref.listen<bool>(
      transfersActiveProvider,
      (_, active) => _onTransfersActive(active),
    );
    _wasActive = active.read();
    ref.onDispose(() {
      _idleTimer?.cancel();
      unawaited(_stoppedSub?.cancel());
      if (_live) {
        _live = false;
        unawaited(_service.stop());
      }
    });
    return const HotspotState();
  }

  Future<void> start() async {
    if (state.phase == HotspotPhase.starting || state.isRunning) return;
    state = const HotspotState(phase: HotspotPhase.starting);
    final list = ref.read(localAddressesProvider);
    final before = await list();
    final WifiCredentials wifi;
    _live = true;
    try {
      wifi = await _service.start();
    } on HotspotException catch (e) {
      _live = false;
      if (ref.mounted) {
        state = HotspotState(phase: HotspotPhase.failed, error: e.code);
      }
      return;
    }
    if (!ref.mounted) return; // onDispose stopped it.
    if (state.phase != HotspotPhase.starting) {
      // Stopped while starting: the stop came before the hotspot was up.
      await _service.stop();
      return;
    }
    // The interface gets its address a moment after the start.
    LocalAddress? address;
    for (var waited = Duration.zero; ; waited += addressPoll) {
      address = pickHotspotAddress(before, await list());
      if (address != null || waited >= addressWait) break;
      await Future<void>.delayed(addressPoll);
      if (!ref.mounted || state.phase != HotspotPhase.starting) return;
    }
    if (!ref.mounted || state.phase != HotspotPhase.starting) return;
    if (address == null) {
      logEvent('hotspot', 'no address on the hotspot');
      _live = false;
      await _service.stop();
      state = const HotspotState(
        phase: HotspotPhase.failed,
        error: 'no_address',
      );
      return;
    }
    logEvent('hotspot', 'running on ${address.interfaceName}');
    state = HotspotState(
      phase: HotspotPhase.running,
      wifi: wifi,
      address: address,
    );
    if (_wasActive) _onTransfersActive(true);
  }

  Future<void> stop() async {
    _idleTimer?.cancel();
    state = const HotspotState();
    if (_live) {
      _live = false;
      await _service.stop();
    }
  }

  /// Cancels the stop after the last transfer.
  void keepOn() {
    _idleTimer?.cancel();
    if (state.isRunning) state = _running(stopsAt: null);
  }

  HotspotState _running({required DateTime? stopsAt}) => HotspotState(
    phase: HotspotPhase.running,
    wifi: state.wifi,
    address: state.address,
    stopsAt: stopsAt,
  );

  void _onTransfersActive(bool active) {
    final ended = _wasActive && !active;
    _wasActive = active;
    if (!state.isRunning) return;
    if (active) {
      _idleTimer?.cancel();
      if (state.stopsAt != null) state = _running(stopsAt: null);
    } else if (ended) {
      _idleTimer?.cancel();
      _idleTimer = Timer(idleStop, () {
        logEvent('hotspot', 'stopping: idle after the last transfer');
        unawaited(stop());
      });
      state = _running(stopsAt: DateTime.now().add(idleStop));
    }
  }

  void _onStoppedElsewhere() {
    if (!ref.mounted || state.phase == HotspotPhase.idle) return;
    _live = false;
    _idleTimer?.cancel();
    state = const HotspotState(phase: HotspotPhase.failed, error: 'stopped');
  }
}

final hotspotControllerProvider =
    NotifierProvider.autoDispose<HotspotController, HotspotState>(
      HotspotController.new,
    );

/// The standard Wi-Fi QR code (`WIFI:T:WPA;S:...;P:...;;`) that the
/// iPhone Camera app can join without CrossDrop's help (D-055). Special
/// characters are escaped with a backslash.
String wifiJoinQr(WifiCredentials wifi) {
  String esc(String s) =>
      s.replaceAllMapped(RegExp(r'[\\;,:"]'), (m) => '\\${m.group(0)}');
  return 'WIFI:T:WPA;S:${esc(wifi.ssid)};P:${esc(wifi.password)};;';
}
