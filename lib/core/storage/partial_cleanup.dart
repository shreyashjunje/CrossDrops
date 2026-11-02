import 'dart:io';

import 'package:path/path.dart' as p;

import '../log.dart';
import '../protocol/models.dart';
import 'transfer_repository.dart';

/// Reason stored on sessions that the cleanup gave up on.
const String expiredReason = 'expired';

/// Deletes partial files nobody will finish (ARCHITECTURE.md, "App crash
/// or phone restart": partial files older than 24 hours).
///
/// Run it at app start, before the receive server starts, so it never
/// races a live upload.
class PartialCleanup {
  PartialCleanup({
    required TransferRepository repository,
    required this.incomingTemp,
    this.maxAge = const Duration(hours: 24),
    DateTime Function()? clock,
  }) : _repo = repository,
       _clock = clock ?? DateTime.now;

  final TransferRepository _repo;

  /// Holds one folder per received session: `<sessionId>/<fileId>.part`.
  final String incomingTemp;
  final Duration maxAge;
  final DateTime Function() _clock;

  /// Returns the number of session folders deleted.
  Future<int> run() async {
    final cutoff = _clock().subtract(maxAge);
    final keep = <String>{};
    final expired = <String>{};
    for (final s in await _repo.unfinished()) {
      if (s.updatedAt.isBefore(cutoff)) {
        await _repo.updateSession(
          s.rowId,
          status: SessionStatus.failed,
          reason: expiredReason,
        );
        if (s.direction == TransferDirection.receive) expired.add(s.sessionId);
        logEvent('storage', 'session ${s.sessionId}: expired after 24 h');
      } else if (s.direction == TransferDirection.receive) {
        keep.add(s.sessionId);
      }
    }

    final root = Directory(incomingTemp);
    if (!await root.exists()) return 0;
    var deleted = 0;
    await for (final entry in root.list(followLinks: false)) {
      final name = p.basename(entry.path);
      if (keep.contains(name)) continue;
      // Folders of finished sessions are removed by the server already;
      // what is left belongs to nobody. Still spare anything touched
      // recently, in case another component is writing.
      if (!expired.contains(name) &&
          (await _newestChange(entry)).isAfter(cutoff)) {
        continue;
      }
      try {
        await entry.delete(recursive: true);
        deleted++;
      } on FileSystemException catch (e) {
        logEvent('storage', 'cleanup could not delete a folder: ${e.osError}');
      }
    }
    if (deleted > 0) logEvent('storage', 'cleanup deleted $deleted folder(s)');
    return deleted;
  }

  static Future<DateTime> _newestChange(FileSystemEntity entry) async {
    var newest = (await entry.stat()).modified;
    if (entry is Directory) {
      await for (final f in entry.list(recursive: true, followLinks: false)) {
        final m = (await f.stat()).modified;
        if (m.isAfter(newest)) newest = m;
      }
    }
    return newest;
  }
}
