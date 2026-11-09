import 'package:crossdrop/platform/haptics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each moment maps to its feedback kind', () {
    final played = <String>[];
    final h = PlatformHaptics(feedback: played.add);
    for (final m in HapticMoment.values) {
      h.play(m);
    }
    expect(played, ['selection', 'light', 'medium', 'success', 'error']);
  });

  test('device found buzzes at most once per second', () {
    var now = DateTime(2026, 11, 9, 12);
    final played = <String>[];
    final h = PlatformHaptics(clock: () => now, feedback: played.add);
    h.play(HapticMoment.deviceFound);
    now = now.add(const Duration(milliseconds: 400));
    h.play(HapticMoment.deviceFound);
    now = now.add(const Duration(milliseconds: 700));
    h.play(HapticMoment.deviceFound);
    expect(played, ['selection', 'selection']);
  });

  test('the throttle does not hold back other moments', () {
    final played = <String>[];
    final h = PlatformHaptics(
      clock: () => DateTime(2026),
      feedback: played.add,
    );
    h
      ..play(HapticMoment.deviceFound)
      ..play(HapticMoment.lockOn)
      ..play(HapticMoment.deviceFound);
    expect(played, ['selection', 'light']);
  });

  group('channel', () {
    const channel = MethodChannel('crossdrop/haptics');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final system = <String>[];

    setUp(() {
      system.clear();
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          system.add(call.arguments as String);
        }
        return null;
      });
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('success and error go to the native channel', () async {
      final calls = <Object?>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add([call.method, call.arguments]);
        return null;
      });
      final h = PlatformHaptics();
      h.play(HapticMoment.done);
      h.play(HapticMoment.failed);
      await pumpEventQueue();
      expect(calls, [
        [
          'notify',
          {'kind': 'success'},
        ],
        [
          'notify',
          {'kind': 'error'},
        ],
      ]);
      expect(system, isEmpty);
    });

    test('without the channel they fall back to impact feedback', () async {
      final h = PlatformHaptics();
      h.play(HapticMoment.done);
      h.play(HapticMoment.failed);
      await pumpEventQueue();
      expect(system, [
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.heavyImpact',
      ]);
    });

    test('a channel error is swallowed', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'boom');
      });
      PlatformHaptics().play(HapticMoment.failed);
      await pumpEventQueue();
      expect(system, isEmpty);
    });

    test('impact moments use Flutter feedback directly', () async {
      final h = PlatformHaptics();
      h
        ..play(HapticMoment.deviceFound)
        ..play(HapticMoment.lockOn)
        ..play(HapticMoment.accepted);
      await pumpEventQueue();
      expect(system, [
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.mediumImpact',
      ]);
    });
  });

  test('silent haptics do nothing', () {
    const SilentHaptics().play(HapticMoment.done);
  });
}
