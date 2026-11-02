import 'package:crossdrop/core/engine/session_state_machine.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('happy path: offered to done with two files', () {
    final m = SessionStateMachine();
    for (final s in [
      SessionStatus.accepted,
      SessionStatus.transferring,
      SessionStatus.verifying,
      SessionStatus.transferring,
      SessionStatus.paused,
      SessionStatus.transferring,
      SessionStatus.verifying,
      SessionStatus.done,
    ]) {
      m.moveTo(s);
    }
    expect(m.state, SessionStatus.done);
  });

  test('cancel is allowed from every non-terminal state', () {
    for (final from in SessionStatus.values.where((s) => !s.isTerminal)) {
      final m = SessionStateMachine(from);
      expect(m.tryMoveTo(SessionStatus.cancelled), isTrue, reason: from.name);
    }
  });

  test('terminal states never move', () {
    for (final from in SessionStatus.values.where((s) => s.isTerminal)) {
      for (final to in SessionStatus.values.where((s) => s != from)) {
        final m = SessionStateMachine(from);
        expect(m.tryMoveTo(to), isFalse, reason: '${from.name}->${to.name}');
        expect(() => m.moveTo(to), throwsA(isA<IllegalTransition>()));
      }
    }
  });

  test('bytes cannot flow before accept', () {
    final m = SessionStateMachine();
    expect(m.canMoveTo(SessionStatus.transferring), isFalse);
    expect(m.canMoveTo(SessionStatus.verifying), isFalse);
    expect(m.canMoveTo(SessionStatus.done), isFalse);
  });

  test('only an offer can be rejected', () {
    for (final from in SessionStatus.values) {
      final ok = SessionStateMachine(from).canMoveTo(SessionStatus.rejected);
      expect(
        ok,
        from == SessionStatus.offered || from == SessionStatus.rejected,
        reason: from.name,
      );
    }
  });

  test('staying in the same state is a no-op', () {
    final m = SessionStateMachine(SessionStatus.paused)
      ..moveTo(SessionStatus.paused);
    expect(m.state, SessionStatus.paused);
  });

  test('every state has an entry in the table', () {
    expect(sessionTransitions.keys.toSet(), SessionStatus.values.toSet());
  });
}
