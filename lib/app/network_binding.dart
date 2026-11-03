import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/discovery/subnet.dart';
import '../core/log.dart';
import '../platform/network.dart';
import 'providers.dart';

/// Android: keeps the process bound to the Wi-Fi network while that Wi-Fi
/// has no internet and mobile data is the default (ARCHITECTURE.md,
/// scenario 7; D-056). Without it, sockets to the other phone would leave
/// over mobile data and fail.
///
/// Follows every Wi-Fi change; the rule is [shouldBindToWifi].
class NetworkBinder {
  NetworkBinder(this._platform);

  final NetworkPlatform _platform;
  StreamSubscription<WifiState>? _sub;
  bool? _bound;

  /// The newest state not applied yet, and the loop applying states.
  WifiState? _pending;
  Future<void>? _draining;

  /// The last state seen, for the About screen and logs.
  WifiState? last;

  Future<void> start() async {
    _sub = _platform.wifiChanges.listen((s) => unawaited(_enqueue(s)));
    final now = await _platform.wifiState();
    if (now != null) await _enqueue(now);
  }

  /// Applies [s] once the change before it is done; a burst collapses to
  /// the newest state. Applying changes side by side let a bind that was
  /// still running when the Wi-Fi was lost set `_bound` after the loss had
  /// cleared it, so the next Wi-Fi without internet was never bound
  /// (review L7).
  Future<void> _enqueue(WifiState s) {
    _pending = s;
    // _drain always awaits before it ends, so it is stored before its
    // finally clears it.
    return _draining ??= _drain();
  }

  Future<void> _drain() async {
    try {
      for (var s = _pending; s != null; s = _pending) {
        _pending = null;
        await _apply(s);
      }
    } finally {
      _draining = null;
    }
  }

  Future<void> _apply(WifiState s) async {
    last = s;
    final want = shouldBindToWifi(
      connected: s.connected,
      validated: s.validated,
      isDefault: s.isDefault,
    );
    // Android clears the binding itself when the network is lost.
    if (!s.connected) _bound = false;
    if (want == _bound) return;
    final ok = await _platform.bindToWifi(want);
    _bound = ok ? want : false;
    logEvent(
      'network',
      want
          ? (ok
                ? 'bound to Wi-Fi (no internet there)'
                : 'binding to Wi-Fi failed')
          : 'binding cleared',
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _pending = null;
    await _draining;
    if (_bound == true) await _platform.bindToWifi(false);
    _bound = false;
  }
}

final networkBinderProvider = Provider<NetworkBinder?>((ref) {
  if (!Platform.isAndroid) return null;
  final binder = NetworkBinder(ref.read(networkPlatformProvider));
  unawaited(binder.start());
  ref.onDispose(() => unawaited(binder.stop()));
  return binder;
});

/// Starts [networkBinderProvider] for the app's lifetime.
class NetworkBindingHost extends ConsumerStatefulWidget {
  const NetworkBindingHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<NetworkBindingHost> createState() => _NetworkBindingHostState();
}

class _NetworkBindingHostState extends ConsumerState<NetworkBindingHost> {
  @override
  void initState() {
    super.initState();
    ref.read(networkBinderProvider);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
