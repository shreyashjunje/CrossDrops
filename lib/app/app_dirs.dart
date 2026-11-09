import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../platform/free_space.dart';

/// Where partial and received files live.
///
/// Partial files: `<app support>/crossdrop_incoming/<sessionId>/`, kept
/// across restarts for resume and removed by the 24-hour cleanup.
///
/// Received files (D-040, D-043):
/// - iOS: photos and videos go to the Photos library; everything else to
///   the Documents folder itself, shown in the Files app as
///   On My iPhone > CrossDrop. The database is not there (D-034).
/// - Android: MediaStore (Pictures, Movies and Download, each in a
///   CrossDrop folder). [received] is then the app's external files
///   folder, used only to check free space on that volume.
///
/// Files prepared for sending (iOS exports, copies of iOS documents and of
/// Android providers that cannot seek):
/// `<app support>/crossdrop_outgoing/<batch>/`, kept while a send may
/// still resume (D-038).
class AppDirs {
  const AppDirs({
    required this.incomingTemp,
    required this.received,
    required this.outgoingStaging,
  });

  final String incomingTemp;
  final String received;
  final String outgoingStaging;

  static bool _excluded = false;

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
    final dirs = AppDirs(
      incomingTemp: p.join(support.path, 'crossdrop_incoming'),
      received: Platform.isIOS ? base.path : p.join(base.path, 'CrossDrop'),
      outgoingStaging: p.join(support.path, 'crossdrop_outgoing'),
    );
    // Android turns backup off in its manifest; iOS needs it per folder.
    if (Platform.isIOS && !_excluded) {
      _excluded = true;
      await excludeFromBackup(dirs.incomingTemp);
      await excludeFromBackup(dirs.outgoingStaging);
    }
    return dirs;
  }
}
