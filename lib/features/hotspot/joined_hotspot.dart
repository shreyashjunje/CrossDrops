import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log.dart';
import '../../platform/hotspot.dart';
import 'hotspot_controller.dart';

/// Joins a network from the app (iPhone, D-055).
final hotspotJoinerProvider = Provider<HotspotJoiner>(
  (ref) => Platform.isIOS ? ChannelHotspotJoiner() : const _NoJoiner(),
);

class _NoJoiner implements HotspotJoiner {
  const _NoJoiner();

  @override
  Future<JoinCapability> capability() async => JoinCapability.manualOnly;

  @override
  Future<JoinOutcome> join(_) async => JoinOutcome.notAvailable;

  @override
  Future<void> forget(String ssid) async {}
}

/// The Android hotspot this iPhone joined from the app. iOS keeps such a
/// network until the app removes it (`joinOnce` is off so a screen lock
/// does not drop it, D-055), so CrossDrop removes it:
/// - [afterTransfer] after the last transfer ends, or
/// - [unused] after joining if no transfer ever starts.
///
/// The state is the network name, or null. Never logged.
class JoinedHotspot extends Notifier<String?> {
  static const afterTransfer = Duration(seconds: 60);
  static const unused = Duration(minutes: 10);

  Timer? _timer;
  bool _active = false;

  @override
  String? build() {
    final sub = ref.listen<bool>(transfersActiveProvider, (prev, active) {
      final ended = _active && !active;
      _active = active;
      if (state == null) return;
      if (active) {
        _timer?.cancel();
      } else if (ended) {
        _arm(afterTransfer);
      }
    });
    _active = sub.read();
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  /// Called once CrossDrop added [ssid] and the other phone answers.
  void remember(String ssid) {
    state = ssid;
    if (!_active) _arm(unused);
  }

  void _arm(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, () => unawaited(forget()));
  }

  /// Removes the network now; iOS goes back to its usual Wi-Fi.
  Future<void> forget() async {
    _timer?.cancel();
    final ssid = state;
    if (ssid == null) return;
    state = null;
    logEvent('hotspot', 'removing the joined network');
    await ref.read(hotspotJoinerProvider).forget(ssid);
  }
}

final joinedHotspotProvider = NotifierProvider<JoinedHotspot, String?>(
  JoinedHotspot.new,
);
