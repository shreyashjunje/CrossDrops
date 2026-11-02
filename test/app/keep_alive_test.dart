import 'dart:async';

import 'package:crossdrop/app/keep_alive.dart';
import 'package:crossdrop/platform/keep_alive.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlatform implements KeepAlivePlatform {
  final List<String> calls = [];
  bool grant = true;
  void Function()? expiring;

  @override
  Future<void> setScreenOn(bool on) async => calls.add('screen:$on');

  @override
  Future<bool> ensureNotificationPermission() async {
    calls.add('permission');
    return grant;
  }

  @override
  Future<void> startService({
    required String title,
    required String text,
  }) async => calls.add('start');

  @override
  Future<void> updateService({required String text}) async =>
      calls.add('update:$text');

  @override
  Future<void> stopService() async => calls.add('stop');

  @override
  Future<void> beginBackgroundTask({
    required void Function() onExpiring,
  }) async {
    expiring = onExpiring;
    calls.add('begin');
  }

  @override
  Future<void> endBackgroundTask() async => calls.add('end');
}

class FakeTransfer implements BackgroundAware {
  final List<String> calls = [];
  Completer<void>? hold;

  @override
  Future<void> onBackground() async {
    calls.add('background');
    await hold?.future;
  }

  @override
  void onForeground() => calls.add('foreground');
}

void main() {
  late FakePlatform platform;

  setUp(() => platform = FakePlatform());

  group('Android', () {
    late KeepAliveCoordinator c;
    setUp(
      () => c = KeepAliveCoordinator(
        platform,
        pauseInBackground: false,
        notificationInterval: Duration.zero,
      ),
    );

    test('service runs while any transfer runs', () async {
      await c.begin('a', FakeTransfer(), title: 't', text: 'x');
      await c.begin('b', FakeTransfer(), title: 't', text: 'x');
      await c.end('a');
      expect(platform.calls, ['screen:true', 'permission', 'start']);
      await c.end('b');
      expect(platform.calls.skip(3), ['screen:false', 'stop']);
    });

    test(
      'notification permission is asked once; denial is not fatal',
      () async {
        platform.grant = false;
        await c.begin('a', FakeTransfer(), title: 't', text: 'x');
        await c.end('a');
        await c.begin('b', FakeTransfer(), title: 't', text: 'x');
        expect(platform.calls.where((x) => x == 'permission'), hasLength(1));
        expect(platform.calls.where((x) => x == 'start'), hasLength(2));
      },
    );

    test('progress updates the notification', () async {
      await c.begin('a', FakeTransfer(), title: 't', text: 'x');
      await c.progress('a', '42%');
      await c.progress('unknown', 'nope');
      expect(platform.calls.last, 'update:42%');
    });

    test('backgrounding does not pause transfers', () async {
      final t = FakeTransfer();
      await c.begin('a', t, title: 't', text: 'x');
      await c.appBackgrounded();
      c.appResumed();
      expect(t.calls, isEmpty);
      expect(platform.calls, isNot(contains('begin')));
    });
  });

  group('iOS', () {
    late KeepAliveCoordinator c;
    setUp(
      () => c = KeepAliveCoordinator(
        platform,
        pauseInBackground: true,
        backgroundBudget: const Duration(milliseconds: 200),
      ),
    );

    test('screen stays on, no service', () async {
      await c.begin('a', FakeTransfer(), title: 't', text: 'x');
      await c.progress('a', '1%');
      await c.end('a');
      expect(platform.calls, ['screen:true', 'screen:false']);
    });

    test('background: task around saving, then resume on return', () async {
      final a = FakeTransfer();
      final b = FakeTransfer();
      await c.begin('a', a, title: 't', text: 'x');
      await c.begin('b', b, title: 't', text: 'x');
      await c.appBackgrounded();
      expect(a.calls, ['background']);
      expect(b.calls, ['background']);
      expect(platform.calls.skip(1), ['begin', 'end']);
      c.appResumed();
      expect(a.calls.last, 'foreground');
      expect(b.calls.last, 'foreground');
    });

    test('a slow transfer cannot hold the task past the budget', () async {
      final slow = FakeTransfer()..hold = Completer<void>();
      await c.begin('a', slow, title: 't', text: 'x');
      final watch = Stopwatch()..start();
      await c.appBackgrounded();
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(platform.calls.last, 'end');
    });

    test('iOS taking the time back ends the task once', () async {
      final slow = FakeTransfer()..hold = Completer<void>();
      await c.begin('a', slow, title: 't', text: 'x');
      final bg = c.appBackgrounded();
      await Future<void>.delayed(Duration.zero);
      platform.expiring!();
      await bg;
      expect(platform.calls.where((x) => x == 'end'), hasLength(1));
    });

    test('a screen holder keeps the screen on after transfers end', () async {
      await c.holdScreen('receive screen');
      await c.begin('a', FakeTransfer(), title: 't', text: 'x');
      await c.end('a');
      expect(platform.calls, ['screen:true']);
      await c.releaseScreen('receive screen');
      expect(platform.calls, ['screen:true', 'screen:false']);
    });

    test('nothing to do without transfers', () async {
      await c.appBackgrounded();
      c.appResumed();
      expect(platform.calls, isEmpty);
    });
  });
}
