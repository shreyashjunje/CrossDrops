import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../engine/chunked_reader.dart';
import '../media/save_target.dart';
import '../protocol/models.dart';
import '../security/device_identity.dart';
import '../storage/file_name_sanitizer.dart';

/// A partial file being received, open for appending.
abstract interface class PartFile {
  /// Bytes in the partial file now.
  Future<int> length();

  /// Appends [bytes] at the end.
  Future<void> append(Uint8List bytes);

  /// Forces written bytes to disk before a checkpoint is stored (D-022).
  Future<void> sync();

  Future<void> truncate(int length);

  /// Sets the file's modification time (the sender's creation date).
  Future<void> setModified(DateTime time);

  /// For hashing the bytes on disk; valid until [close].
  ByteSource get source;

  Future<void> close();
}

/// Where a verified file ended up.
class SaveResult {
  const SaveResult({
    required this.location,
    required this.collection,
    this.fallback,
  });

  /// A path, a content URI, or `photos:<localIdentifier>` (iOS). Stored as
  /// `finalLocation`; shown to the user only as [collection].
  final String location;
  final SaveCollection collection;

  /// Why the file is not where its kind would go: the gallery refused
  /// it ([SaveFallback.unsupported]) or has no permission
  /// ([SaveFallback.permission]).
  final String? fallback;
}

abstract final class SaveFallback {
  static const unsupported = 'unsupported';
  static const permission = 'permission';
}

/// The save failed for lack of space; the partial file is kept.
class StoreFull implements Exception {
  const StoreFull();
}

/// Holds partial files and saves verified ones (ARCHITECTURE.md, "Transfer
/// rules" 2 and 7).
///
/// A file's *location* is an opaque string stored in `session_files.
/// tempPath`: a path for [FolderStore], a MediaStore content URI on
/// Android (D-040). It starts as [initialLocation] and may change the
/// first time the part is created.
///
/// Errors are [FileSystemException]s with the OS error code, so the server
/// can tell a full disk (ENOSPC) from other failures.
abstract interface class ReceivedFileStore {
  /// The location of a file before anything was written.
  String initialLocation(String sessionDir, FileOffer offer);

  /// Opens the part at [location], creating it if needed. Returns the
  /// part and its location, which the caller stores if it changed.
  Future<(PartFile, String)> open(
    String location, {
    required String sessionDir,
    required FileOffer offer,
  });

  /// Bytes at [location]; 0 if nothing was created yet.
  Future<int> length(String location);

  /// After a restart: cuts the part back to [checkpoint] bytes and returns
  /// what is kept. A part that vanished counts as 0.
  Future<int> restore(String location, int checkpoint);

  /// Deletes the part. Never throws for a missing part.
  Future<void> delete(String location);

  /// Moves the verified part into its final place. Throws [StoreFull]
  /// when the disk is full (the part stays).
  Future<SaveResult> save(String location, FileOffer offer);
}

/// Partial files in `<tempDir>/<sessionId>/<fileId>.part`, saved by a
/// rename into [saveDir] (or handed to a [MediaSaver] first).
///
/// Used by tests, the dev CLI and iOS. iOS passes a [MediaSaver] for the
/// Photos library; anything it does not take goes to [saveDir], the
/// Documents folder shown in the Files app.
class FolderStore implements ReceivedFileStore {
  FolderStore(this.saveDir, {this.mediaSaver, DevicePlatform? platform})
    : platform = platform ?? DevicePlatform.current;

  final String saveDir;
  final MediaSaver? mediaSaver;

  /// Whose gallery rules decide the [SaveCollection].
  final DevicePlatform platform;

  @override
  String initialLocation(String sessionDir, FileOffer offer) =>
      p.join(sessionDir, '${offer.fileId}.part');

  @override
  Future<(PartFile, String)> open(
    String location, {
    required String sessionDir,
    required FileOffer offer,
  }) async {
    final file = File(location);
    if (!await file.exists()) await file.create(recursive: true);
    return (
      _FilePart(location, await file.open(mode: FileMode.append)),
      location,
    );
  }

  @override
  Future<int> length(String location) async {
    final file = File(location);
    return await file.exists() ? file.length() : 0;
  }

  @override
  Future<int> restore(String location, int checkpoint) async {
    final file = File(location);
    if (!await file.exists()) {
      await file.create(recursive: true);
      return 0;
    }
    final length = await file.length();
    final keep = min(length, checkpoint);
    if (keep != length) {
      final raf = await file.open(mode: FileMode.append);
      try {
        await raf.truncate(keep);
      } finally {
        await raf.close();
      }
    }
    return keep;
  }

  @override
  Future<void> delete(String location) async {
    try {
      await File(location).delete();
    } on FileSystemException {
      // Already gone.
    }
  }

  @override
  Future<SaveResult> save(String location, FileOffer offer) async {
    final safeName = sanitizeFileName(offer.name);
    final collection = saveCollectionFor(
      safeName: safeName,
      declaredKind: offer.kind,
      platform: platform,
    );
    String? fallback;
    final saver = mediaSaver;
    if (saver != null && collection != SaveCollection.files) {
      // Photos judges a file partly by its extension: hand it over under
      // its real name, not `f1.part`. Same folder, so this is a rename.
      final named = p.join(p.dirname(location), offer.fileId, safeName);
      await Directory(p.dirname(named)).create(recursive: true);
      await File(location).rename(named);
      final GallerySave r;
      try {
        r = await saver.saveToGallery(
          named,
          safeName: safeName,
          kind: offer.kind,
          created: offer.created,
        );
      } catch (_) {
        await File(named).rename(location);
        rethrow;
      }
      if (r.savedAs != null) {
        return SaveResult(location: r.savedAs!, collection: collection);
      }
      // Not taken: the part is back where the session expects it.
      await File(named).rename(location);
      if (r.noSpace) throw const StoreFull();
      fallback = r.fallback;
    }
    await Directory(saveDir).create(recursive: true);
    final dest = await claimPath(saveDir, safeName);
    try {
      await _move(location, dest);
    } on FileSystemException catch (e) {
      // The empty placeholder; the part is still where it was.
      try {
        await File(dest).delete();
      } on FileSystemException {
        // Gone already.
      }
      if (isNoSpace(e)) throw const StoreFull();
      rethrow;
    }
    final created = offer.created;
    if (created != null) {
      try {
        // Files has no settable creation date; modified is what it shows.
        await File(dest).setLastModified(created);
      } on FileSystemException {
        // Best effort.
      }
    }
    return SaveResult(
      location: dest,
      collection: SaveCollection.files,
      fallback: fallback,
    );
  }

  static Future<void> _move(String from, String to) async {
    try {
      await File(from).rename(to);
    } on FileSystemException {
      // Different volume: copy (streamed by the OS), then delete.
      await File(from).copy(to);
      await File(from).delete();
    }
  }
}

/// ENOSPC on Linux, Android and iOS; ERROR_DISK_FULL / HANDLE_DISK_FULL
/// on Windows test hosts; EDQUOT.
bool isNoSpace(FileSystemException e) {
  final code = e.osError?.errorCode;
  return code == 28 || code == 112 || code == 39 || code == 122;
}

/// Outcome of [MediaSaver.saveToGallery].
class GallerySave {
  const GallerySave.saved(String this.savedAs)
    : fallback = null,
      noSpace = false;
  const GallerySave.refused(String this.fallback)
    : savedAs = null,
      noSpace = false;
  const GallerySave.full() : savedAs = null, fallback = null, noSpace = true;

  /// Set when the gallery took the file (it was moved, not copied).
  final String? savedAs;

  /// [SaveFallback] reason when it did not; the file is still at its path.
  final String? fallback;
  final bool noSpace;
}

/// Adds a verified file to the photo library (iOS Photos), moving it.
abstract interface class MediaSaver {
  Future<GallerySave> saveToGallery(
    String path, {
    required String safeName,
    required String kind,
    DateTime? created,
  });
}

class _FilePart implements PartFile {
  _FilePart(this.path, this._raf);

  final String path;
  final RandomAccessFile _raf;

  @override
  Future<int> length() => _raf.length();

  @override
  Future<void> append(Uint8List bytes) => _raf.writeFrom(bytes);

  @override
  Future<void> sync() => _raf.flush();

  @override
  Future<void> truncate(int length) => _raf.truncate(length);

  @override
  Future<void> setModified(DateTime time) => File(path).setLastModified(time);

  @override
  ByteSource get source => PathSource(path);

  @override
  Future<void> close() => _raf.close();
}
