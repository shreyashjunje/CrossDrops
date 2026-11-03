import 'dart:async';

import '../../core/protocol/models.dart';

/// Which received sessions hold the keep-alive (screen on, Android
/// foreground service) and keep the server up (review M3, L6).
///
/// - `accepted`, `transferring`, `verifying`: held.
/// - `paused`: still held for [grace], then released. The sender retries
///   for about 2 minutes (D-019); dropping the wake lock at the first drop
///   would let an iPhone lock and suspend at once. A sender that went to
///   the background or gave up must not keep the screen on for good.
/// - `offered` and final states: not held.
///
/// A session paused when it was not held (restored after a restart) is
/// not held either.
class SessionKeepAlive {
  SessionKeepAlive({
    required this.onBegin,
    required this.onEnd,
    this.onGraceOver,
    this.grace = defaultGrace,
  });

  /// The sender's retry deadline (D-019) plus a margin.
  static const defaultGrace = Duration(seconds: 150);

  /// Start keeping the app alive for this session.
  final void Function(String sessionId) onBegin;

  /// Stop keeping it alive: it ended, or stayed paused for [grace].
  final void Function(String sessionId) onEnd;

  /// A paused session's grace ran out; the server may be idle now.
  final void Function()? onGraceOver;
  final Duration grace;

  final Set<String> _held = {};
  final Map<String, Timer> _paused = {};

  /// Some session is paused but may still resume within [grace].
  bool get anyInGrace => _paused.isNotEmpty;

  bool isHeld(String sessionId) => _held.contains(sessionId);

  void update(String sessionId, SessionStatus status) {
    if (status != SessionStatus.paused) _paused.remove(sessionId)?.cancel();
    switch (status) {
      case SessionStatus.accepted ||
          SessionStatus.transferring ||
          SessionStatus.verifying:
        if (_held.add(sessionId)) onBegin(sessionId);
      case SessionStatus.paused:
        if (!_held.contains(sessionId) || _paused.containsKey(sessionId)) {
          return;
        }
        _paused[sessionId] = Timer(grace, () {
          _paused.remove(sessionId);
          if (_held.remove(sessionId)) onEnd(sessionId);
          onGraceOver?.call();
        });
      case SessionStatus.offered:
        break;
      case SessionStatus.done ||
          SessionStatus.rejected ||
          SessionStatus.cancelled ||
          SessionStatus.failed:
        if (_held.remove(sessionId)) onEnd(sessionId);
    }
  }

  /// Releases everything (the server stopped).
  void clear() {
    for (final t in _paused.values) {
      t.cancel();
    }
    _paused.clear();
    final held = _held.toList();
    _held.clear();
    held.forEach(onEnd);
  }
}
