import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Folders used in Phase 1.
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
    final temp = await getTemporaryDirectory();
    Directory base;
    if (Platform.isAndroid) {
      base =
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      base = await getApplicationDocumentsDirectory();
    }
    return AppDirs(
      incomingTemp: p.join(temp.path, 'crossdrop_incoming'),
      received: p.join(base.path, 'CrossDrop'),
    );
  }
}
