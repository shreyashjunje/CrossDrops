import 'package:flutter/services.dart';

import '../core/log.dart';

/// Free bytes on the volume holding a path. Dart has no API for this.
abstract interface class FreeSpace {
  /// Null if unknown (desktop, tests, or the OS would not say).
  Future<int?> freeBytes(String path);
}

/// [FreeSpace] over the `crossdrop/storage` channel
/// (ios/Runner/AppDelegate.swift, android/.../MainActivity.kt).
///
/// iOS reports "available for important usage", which counts space the
/// system can free by purging caches; that is what Files and Photos use
/// for user-initiated saves. Android reports StatFs available bytes.
class ChannelFreeSpace implements FreeSpace {
  static const _channel = MethodChannel('crossdrop/storage');

  @override
  Future<int?> freeBytes(String path) async {
    try {
      return await _channel.invokeMethod<int>('freeBytes', {'path': path});
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      logEvent('storage', 'free space query failed: ${e.code}');
      return null;
    }
  }
}
