import 'package:flutter/services.dart';

import '../core/log.dart';

/// Opens a received file in the system viewer (D-051). Takes the saved
/// location the store reported, never file bytes (CLAUDE.md hard rule 2).
abstract interface class FileOpener {
  /// True if something was shown. A location the platform does not own
  /// (outside CrossDrop's saved files) is refused.
  Future<bool> open(String location);
}

/// [FileOpener] over the `crossdrop/open` channel:
///
/// - Android: a MediaStore `content://media/...` URI, viewed with
///   `ACTION_VIEW` and a read grant.
/// - iOS: `photos:<id>` opens the Photos app (it cannot jump to one
///   photo); a path inside Documents is previewed with Quick Look.
class ChannelFileOpener implements FileOpener {
  static const _channel = MethodChannel('crossdrop/open');

  @override
  Future<bool> open(String location) async {
    try {
      return await _channel.invokeMethod<bool>('open', {
            'location': location,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      logEvent('open', 'failed: ${e.code}');
      return false;
    }
  }
}
