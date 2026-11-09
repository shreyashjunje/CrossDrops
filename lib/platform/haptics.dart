import 'package:flutter/services.dart';

/// The moments that get a haptic (D-069). Everything else stays silent.
enum HapticMoment {
  /// A new phone appeared on the radar. At most once per second.
  deviceFound,

  /// The user tapped a phone and the radar locked on to it.
  lockOn,

  /// The other phone tapped Accept.
  accepted,

  /// Every file arrived and was checked.
  done,

  /// The transfer failed or was declined.
  failed,
}

/// Plays a haptic for a [HapticMoment] (hard rule 9: platform code behind
/// a Dart interface).
abstract interface class Haptics {
  void play(HapticMoment moment);
}

/// No haptics: tests, and platforms without a vibration motor.
class SilentHaptics implements Haptics {
  const SilentHaptics();

  @override
  void play(HapticMoment moment) {}
}

/// Flutter's impact and selection feedback, plus the `crossdrop/haptics`
/// channel for the success and error patterns Flutter does not ship:
///
/// - iOS: `UINotificationFeedbackGenerator` success and error.
/// - Android: `HapticFeedbackConstants.CONFIRM` and `REJECT` (Android 11
///   and later), a short click before that. Android skips them when the
///   user turned touch feedback off.
///
/// Without the channel (tests, an older build) success and error fall back
/// to impact feedback. Haptics never throw.
class PlatformHaptics implements Haptics {
  PlatformHaptics({DateTime Function()? clock, this.feedback})
    : _clock = clock ?? DateTime.now;

  static const _channel = MethodChannel('crossdrop/haptics');

  /// Device found is throttled so a busy radar does not buzz constantly.
  static const foundInterval = Duration(seconds: 1);

  final DateTime Function() _clock;

  /// Replaces the calls to [HapticFeedback] and the channel in tests.
  final void Function(String kind)? feedback;

  DateTime? _lastFound;

  @override
  void play(HapticMoment moment) {
    switch (moment) {
      case HapticMoment.deviceFound:
        final now = _clock();
        final last = _lastFound;
        if (last != null && now.difference(last) < foundInterval) return;
        _lastFound = now;
        _emit('selection');
      case HapticMoment.lockOn:
        _emit('light');
      case HapticMoment.accepted:
        _emit('medium');
      case HapticMoment.done:
        _emit('success');
      case HapticMoment.failed:
        _emit('error');
    }
  }

  void _emit(String kind) {
    final test = feedback;
    if (test != null) return test(kind);
    switch (kind) {
      case 'selection':
        HapticFeedback.selectionClick();
      case 'light':
        HapticFeedback.lightImpact();
      case 'medium':
        HapticFeedback.mediumImpact();
      default:
        _notify(kind);
    }
  }

  Future<void> _notify(String kind) async {
    try {
      await _channel.invokeMethod<void>('notify', {'kind': kind});
    } on MissingPluginException {
      await (kind == 'success'
          ? HapticFeedback.mediumImpact()
          : HapticFeedback.heavyImpact());
    } on PlatformException {
      // A haptic is never worth an error.
    }
  }
}
