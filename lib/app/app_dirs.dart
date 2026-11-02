import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where partial and received files live.
///
/// Partial files: `<app support>/crossdrop_incoming/<sessionId>/`, kept
/// across restarts for resume and removed by the 24-hour cleanup.
///
/// Received files are saved in an app folder, not the gallery or Downloads
/// (that comes with the platform modules in a later phase):
/// - iOS: Documents/CrossDrop, visible in the Files app under
///   On My iPhone > crossdrop.
/// - Android: the app's external files folder
///   (`Android/data/<package>/files/CrossDrop`), visible over USB.
class AppDirs {
  const AppDirs({required this.incomingTemp, required this.received});

  final String incomingTemp;
  final String received;

  static Future<AppDirs> resolve() async {
    // Not the OS temp or cache folder: both may be purged while the app is
    // closed, which would lose partial files a sender wants to resume.
    final support = await getApplicationSupportDirectory();
    Directory base;
    if (Platform.isAndroid) {
      base =
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      base = await getApplicationDocumentsDirectory();
    }
    return AppDirs(
      incomingTemp: p.join(support.path, 'crossdrop_incoming'),
      received: p.join(base.path, 'CrossDrop'),
    );
  }
}
