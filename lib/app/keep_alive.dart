import 'dart:async';

import '../core/log.dart';
import '../platform/keep_alive.dart';

/// A running transfer that must react when the app leaves the screen.
abstract interface class BackgroundAware {
  /// iOS is about to suspend the app: finish the current chunk, save
  /// progress, and stop. Must complete within a few seconds.
  Future<void> onBackground();

  /// Back on screen: continue.
  void onForeground();
}

/// Keeps transfers alive while they run (ARCHITECTURE.md, "Screen lock
/// during transfer"):
///
/// - both: the screen stays on;
/// - Android: a dataSync foreground service with a progress notification,
///   so the transfer goes on with the screen off;
/// - iOS: when the app is hidden, a short background task in which every
///   transfer saves progress and pauses; they resume on return.
class KeepAliveCoordinator {
  KeepAliveCoordinator(
    this._platform, {
    required this.pauseInBackground,
    this.backgroundBudget = const Duration(seconds: 20),
    this.notificationInterval = const Duration(seconds: 1),
  });

  final KeepAlivePlatform _platform;

  /// True on iOS: transfers pause in the background. False on Android:
  /// the foreground service keeps them running.
  final bool pauseInBackground;

  /// iOS gives about 30 s; stay well inside it.
  final Duration backgroundBudget;
  final Duration notificationInterval;

  final Map<Object, BackgroundAware> _active = {};

  /// Who wants the screen on: running transfers, and screens such as
  /// Receive that must stay discoverable.
  final Set<Object> _screen = {};
  bool _askedPermission = false;
  bool _inBackground = false;
  DateTime _lastNotification = DateTime.fromMillisecondsSinceEpoch(0);

  int get activeCount => _active.length;

  bool get isInBackground => _inBackground;

  /// A transfer started. [title] and [text] go into the Android
  /// notification.
  Future<void> begin(
    Object key,
    BackgroundAware transfer, {
    required String title,
    required String text,
  }) async {
    final first = _active.isEmpty;
    _active[key] = transfer;
    await holdScreen(key);
    if (!first) return;
    if (!pauseInBackground) {
      if (!_askedPermission) {
        _askedPermission = true;
        final granted = await _guardValue(
          'notification permission',
          _platform.ensureNotificationPermission,
          false,
        );
        if (!granted) {
          logEvent('keepalive', 'notifications off; service runs silently');
        }
      }
      await _guard(
        'service start',
        () => _platform.startService(title: title, text: text),
      );
    }
    logEvent('keepalive', 'on');
  }

  /// Updates the notification text, at most once per
  /// [notificationInterval].
  Future<void> progress(Object key, String text) async {
    if (pauseInBackground || !_active.containsKey(key)) return;
    final now = DateTime.now();
    if (now.difference(_lastNotification) < notificationInterval) return;
    _lastNotification = now;
    await _guard('service update', () => _platform.updateService(text: text));
  }

  /// A transfer ended (done, failed or cancelled).
  Future<void> end(Object key) async {
    if (_active.remove(key) == null) return;
    await releaseScreen(key);
    if (_active.isNotEmpty) return;
    if (!pauseInBackground) {
      await _guard('service stop', _platform.stopService);
    }
    logEvent('keepalive', 'off');
  }

  /// Keeps the screen on until [releaseScreen] with the same [key].
  Future<void> holdScreen(Object key) async {
    final first = _screen.isEmpty;
    _screen.add(key);
    if (first) await _guard('screen on', () => _platform.setScreenOn(true));
  }

  Future<void> releaseScreen(Object key) async {
    if (!_screen.remove(key) || _screen.isNotEmpty) return;
    await _guard('screen off', () => _platform.setScreenOn(false));
  }

  /// The app left the screen (lock, home button, app switcher).
  Future<void> appBackgrounded() async {
    if (_inBackground) return;
    _inBackground = true;
    if (!pauseInBackground || _active.isEmpty) return;
    final transfers = _active.values.toList();
    var ended = false;
    Future<void> endTask() async {
      if (ended) return;
      ended = true;
      await _guard('background task end', _platform.endBackgroundTask);
    }

    await _guard(
      'background task begin',
      () =>
          _platform.beginBackgroundTask(onExpiring: () => unawaited(endTask())),
    );
    logEvent('keepalive', 'background: saving ${transfers.length} transfer(s)');
    await Future.wait([
      for (final t in transfers)
        t.onBackground().catchError((Object e) {
          logEvent('keepalive', 'onBackground failed: ${e.runtimeType}');
        }),
    ]).timeout(backgroundBudget, onTimeout: () => const []);
    await endTask();
  }

  /// The app is back on screen.
  void appResumed() {
    if (!_inBackground) return;
    _inBackground = false;
    if (!pauseInBackground) return;
    for (final t in _active.values.toList()) {
      t.onForeground();
    }
  }

  static Future<void> _guard(String what, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      // Keep-alive helps; it must never break a transfer.
      logEvent('keepalive', '$what failed: ${e.runtimeType}');
    }
  }

  static Future<T> _guardValue<T>(
    String what,
    Future<T> Function() f,
    T fallback,
  ) async {
    try {
      return await f();
    } catch (e) {
      logEvent('keepalive', '$what failed: ${e.runtimeType}');
      return fallback;
    }
  }
}
