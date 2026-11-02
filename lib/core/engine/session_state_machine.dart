import '../protocol/models.dart';

/// Legal moves between [SessionStatus] values. ARCHITECTURE.md,
/// "Session state machine":
///
/// offered → accepted → transferring ⇄ paused → verifying → done,
/// or rejected / cancelled / failed.
///
/// `verifying` goes back to `transferring` when more files follow, and
/// `paused` can go straight to `verifying` when the last bytes arrived
/// before the drop.
const Map<SessionStatus, Set<SessionStatus>> sessionTransitions = {
  SessionStatus.offered: {
    SessionStatus.accepted,
    SessionStatus.rejected,
    SessionStatus.cancelled,
    SessionStatus.failed,
  },
  SessionStatus.accepted: {
    SessionStatus.transferring,
    SessionStatus.paused,
    SessionStatus.verifying,
    SessionStatus.cancelled,
    SessionStatus.failed,
  },
  SessionStatus.transferring: {
    SessionStatus.paused,
    SessionStatus.verifying,
    SessionStatus.cancelled,
    SessionStatus.failed,
  },
  SessionStatus.paused: {
    SessionStatus.transferring,
    SessionStatus.verifying,
    SessionStatus.cancelled,
    SessionStatus.failed,
  },
  SessionStatus.verifying: {
    SessionStatus.transferring,
    SessionStatus.paused,
    SessionStatus.done,
    SessionStatus.cancelled,
    SessionStatus.failed,
  },
  SessionStatus.done: {},
  SessionStatus.rejected: {},
  SessionStatus.cancelled: {},
  SessionStatus.failed: {},
};

class IllegalTransition extends StateError {
  IllegalTransition(this.from, this.to)
    : super('illegal transition ${from.name} -> ${to.name}');

  final SessionStatus from;
  final SessionStatus to;
}

/// The receiver's view of one session's state. Pure Dart, no I/O.
class SessionStateMachine {
  SessionStateMachine([this._state = SessionStatus.offered]);

  SessionStatus _state;

  SessionStatus get state => _state;

  bool canMoveTo(SessionStatus to) =>
      to == _state || sessionTransitions[_state]!.contains(to);

  /// Moves to [to]. Staying in the same state is allowed and does nothing.
  /// Throws [IllegalTransition] otherwise.
  void moveTo(SessionStatus to) {
    if (!canMoveTo(to)) throw IllegalTransition(_state, to);
    _state = to;
  }

  /// Like [moveTo] but returns false instead of throwing.
  bool tryMoveTo(SessionStatus to) {
    if (!canMoveTo(to)) return false;
    _state = to;
    return true;
  }
}
