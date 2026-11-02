import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/log.dart';

/// What the OS offers to keep a transfer alive (ARCHITECTURE.md, "Screen
/// lock during transfer"). Behind an interface so the coordinator is
/// testable (CLAUDE.md hard rule 9).
abstract interface class KeepAlivePlatform {
  /// Keeps the screen on (both platforms).
  Future<void> setScreenOn(bool on);

  /// Android: asks for POST_NOTIFICATIONS (Android 13+) so the service's
  /// progress notification shows. Returns whether it is granted. The
  /// service runs either way.
  Future<bool> ensureNotificationPermission();

  /// Android: foreground service of type dataSync with a notification.
  Future<void> startService({required String title, required String text});
  Future<void> updateService({required String text});
  Future<void> stopService();

  /// iOS: asks for a little time after the app leaves the screen, to finish
  /// the current chunk and save progress. [onExpiring] runs if iOS takes the
  /// time back early.
  Future<void> beginBackgroundTask({required void Function() onExpiring});
  Future<void> endBackgroundTask();
}

/// The real platform: wakelock_plus, flutter_foreground_task (Android) and
/// the `crossdrop/background` channel (ios/Runner/AppDelegate.swift).
class PlatformKeepAlive implements KeepAlivePlatform {
  PlatformKeepAlive() {
    if (Platform.isIOS) _channel.setMethodCallHandler(_onCall);
    if (Platform.isAndroid) {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'crossdrop_transfer',
          channelName: 'Transfers',
          channelDescription: 'Progress of files being sent or received',
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(),
        foregroundTaskOptions: ForegroundTaskOptions(
          // No periodic task: the service only keeps the process alive
          // while the transfer runs in the app's own isolate.
          eventAction: ForegroundTaskEventAction.nothing(),
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
    }
  }

  static const _channel = MethodChannel('crossdrop/background');
  void Function()? _onExpiring;

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method == 'expiring') {
      logEvent('keepalive', 'background time expiring');
      _onExpiring?.call();
    }
    return null;
  }

  @override
  Future<void> setScreenOn(bool on) async {
    try {
      on ? await WakelockPlus.enable() : await WakelockPlus.disable();
    } on MissingPluginException {
      // Desktop.
    }
  }

  @override
  Future<bool> ensureNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    var p = await FlutterForegroundTask.checkNotificationPermission();
    if (p != NotificationPermission.granted) {
      p = await FlutterForegroundTask.requestNotificationPermission();
    }
    return p == NotificationPermission.granted;
  }

  @override
  Future<void> startService({
    required String title,
    required String text,
  }) async {
    if (!Platform.isAndroid) return;
    final result = await FlutterForegroundTask.startService(
      serviceId: 3017,
      serviceTypes: const [ForegroundServiceTypes.dataSync],
      notificationTitle: title,
      notificationText: text,
    );
    if (result is ServiceRequestFailure) {
      logEvent(
        'keepalive',
        'service start failed: ${result.error.runtimeType}',
      );
    }
  }

  @override
  Future<void> updateService({required String text}) async {
    if (!Platform.isAndroid) return;
    await FlutterForegroundTask.updateService(notificationText: text);
  }

  @override
  Future<void> stopService() async {
    if (!Platform.isAndroid) return;
    await FlutterForegroundTask.stopService();
  }

  @override
  Future<void> beginBackgroundTask({
    required void Function() onExpiring,
  }) async {
    if (!Platform.isIOS) return;
    _onExpiring = onExpiring;
    await _channel.invokeMethod<void>('begin');
  }

  @override
  Future<void> endBackgroundTask() async {
    if (!Platform.isIOS) return;
    _onExpiring = null;
    await _channel.invokeMethod<void>('end');
  }
}
