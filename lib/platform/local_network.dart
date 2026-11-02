import 'package:flutter/services.dart';

import '../core/log.dart';

enum LocalNetworkStatus {
  granted,

  /// iOS only: the user turned off Local Network for CrossDrop.
  denied,

  /// Could not tell (probe timed out without a clear answer, or the
  /// first-run prompt is still open).
  unknown,
}

/// Local Network permission (iOS) and the app's system settings page.
abstract interface class LocalNetwork {
  Future<LocalNetworkStatus> probe();

  /// Opens this app's page in system Settings (iOS) or App info (Android).
  Future<void> openSettings();
}

/// [LocalNetwork] over the `crossdrop/local_network` channel
/// (ios/Runner/AppDelegate.swift, android/.../MainActivity.kt).
class ChannelLocalNetwork implements LocalNetwork {
  static const _channel = MethodChannel('crossdrop/local_network');

  @override
  Future<LocalNetworkStatus> probe({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final answer = await _channel.invokeMethod<String>('probe', {
        'timeoutMs': timeout.inMilliseconds,
      });
      final status = LocalNetworkStatus.values.firstWhere(
        (s) => s.name == answer,
        orElse: () => LocalNetworkStatus.unknown,
      );
      logEvent('discovery', 'local network probe: ${status.name}');
      return status;
    } on MissingPluginException {
      // Desktop builds and tests: no permission to check.
      return LocalNetworkStatus.granted;
    } on PlatformException catch (e) {
      logEvent('discovery', 'local network probe failed: ${e.code}');
      return LocalNetworkStatus.unknown;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on MissingPluginException {
      // Nothing to open on desktop.
    }
  }
}
