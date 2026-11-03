import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/features/receive/session_keep_alive.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> log;
  late SessionKeepAlive k;

  setUp(() {
    log = [];
    k = SessionKeepAlive(
      onBegin: (s) => log.add('begin $s'),
      onEnd: (s) => log.add('end $s'),
      onGraceOver: () => log.add('grace over'),
    );
  });

  test('held while bytes move, released when the session ends', () {
    k.update('a', SessionStatus.offered);
    expect(log, isEmpty);
    k.update('a', SessionStatus.accepted);
    k.update('a', SessionStatus.transferring);
    k.update('a', SessionStatus.verifying);
    expect(log, ['begin a']);
    k.update('a', SessionStatus.done);
    expect(log, ['begin a', 'end a']);
    expect(k.isHeld('a'), isFalse);
  });

  test('a paused session is released after the grace (review M3)', () {
    fakeAsync((async) {
      k.update('a', SessionStatus.transferring);
      k.update('a', SessionStatus.paused);
      expect(k.anyInGrace, isTrue);
      async.elapse(SessionKeepAlive.defaultGrace - const Duration(seconds: 1));
      expect(log, ['begin a'], reason: 'the sender may still be retrying');
      async.elapse(const Duration(seconds: 2));
      expect(log, ['begin a', 'end a', 'grace over']);
      expect(k.anyInGrace, isFalse);
      // The sender comes back later: held again.
      k.update('a', SessionStatus.transferring);
      expect(log.last, 'begin a');
    });
  });

  test('a sender back within the grace keeps it held throughout', () {
    fakeAsync((async) {
      k.update('a', SessionStatus.transferring);
      k.update('a', SessionStatus.paused);
      async.elapse(const Duration(seconds: 10));
      k.update('a', SessionStatus.transferring);
      async.elapse(const Duration(minutes: 10));
      expect(log, ['begin a']);
      expect(k.anyInGrace, isFalse);
    });
  });

  test('repeated pauses do not extend the grace', () {
    fakeAsync((async) {
      k.update('a', SessionStatus.transferring);
      k.update('a', SessionStatus.paused);
      async.elapse(const Duration(seconds: 100));
      k.update('a', SessionStatus.paused);
      async.elapse(const Duration(seconds: 51));
      expect(log, contains('end a'));
    });
  });

  test('a session restored as paused is never held', () {
    fakeAsync((async) {
      k.update('a', SessionStatus.paused);
      expect(k.anyInGrace, isFalse);
      async.elapse(const Duration(minutes: 5));
      expect(log, isEmpty);
    });
  });

  test('ending while paused cancels the grace', () {
    fakeAsync((async) {
      k.update('a', SessionStatus.transferring);
      k.update('a', SessionStatus.paused);
      k.update('a', SessionStatus.cancelled);
      async.elapse(const Duration(minutes: 5));
      expect(log, ['begin a', 'end a']);
    });
  });

  test('clear releases every session and stops the timers', () {
    fakeAsync((async) {
      k.update('a', SessionStatus.transferring);
      k.update('b', SessionStatus.transferring);
      k.update('b', SessionStatus.paused);
      k.clear();
      expect(log, ['begin a', 'begin b', 'end a', 'end b']);
      async.elapse(const Duration(minutes: 5));
      expect(log, hasLength(4));
      expect(k.anyInGrace, isFalse);
    });
  });
}
