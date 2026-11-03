import 'dart:io';

import 'package:path/path.dart' as p;

/// SQLite files that belong to one database: the main file and its
/// write-ahead log, shared memory and rollback journal.
const List<String> _suffixes = ['', '-wal', '-shm', '-journal'];

/// Moves the database `<name>.sqlite` and its side files from [fromDir] to
/// [toDir], once.
///
/// Up to Phase 4 the database lived in the app's Documents folder, which
/// iOS shows in the Files app (`UIFileSharingEnabled`), where the user
/// could delete or open it. It now lives in Application Support (D-034).
///
/// Does nothing if [toDir] already holds the database, so a later launch
/// never overwrites newer data with an old copy. Returns true if it moved.
Future<bool> moveDatabaseFiles({
  required String fromDir,
  required String toDir,
  required String name,
}) async {
  final main = '$name.sqlite';
  if (p.equals(fromDir, toDir)) return false;
  if (!await File(p.join(fromDir, main)).exists()) return false;
  if (await File(p.join(toDir, main)).exists()) return false;
  await Directory(toDir).create(recursive: true);
  // Side files first: once the main file is in place, a crash before the
  // rest moved would open it without its write-ahead log.
  for (final suffix in [..._suffixes.skip(1), _suffixes.first]) {
    final from = File(p.join(fromDir, '$main$suffix'));
    if (!await from.exists()) continue;
    final to = p.join(toDir, '$main$suffix');
    try {
      await from.rename(to);
    } on FileSystemException {
      // Different volume (never expected inside one app container).
      await from.copy(to);
      await from.delete();
    }
  }
  return true;
}
