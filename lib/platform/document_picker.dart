import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../core/log.dart';
import '../core/media/prepare.dart';
import '../core/storage/file_name_sanitizer.dart';
import 'android_source.dart';

/// The system picker for "any file" (D-041).
abstract interface class DocumentPicker {
  /// Empty if the user backed out.
  Future<List<PickedFile>> pick();

  /// The picks are no longer needed (sent for good, or cleared): give back
  /// grants and delete copies.
  Future<void> release(List<PickedFile> files);
}

/// Storage Access Framework: content URIs read in place, no copy. Each
/// gets a persistable read grant so a resume after a restart still works.
class AndroidDocumentPicker implements DocumentPicker {
  AndroidDocumentPicker(this._sources);

  final AndroidSources _sources;

  @override
  Future<List<PickedFile>> pick() async {
    final uris = await _sources.pickDocuments();
    final infos = await _sources.describe(uris);
    return [
      for (final i in infos)
        PickedFile(
          ref: i.uri,
          name: i.name ?? 'file',
          mime: i.mime,
          created: i.modified,
          size: i.size,
        ),
    ];
  }

  @override
  Future<void> release(List<PickedFile> files) => _sources.release([
    for (final f in files)
      if (f.ref.startsWith('content://')) f.ref,
  ]);
}

/// iOS document picker (file_picker, import mode): iOS hands over a copy
/// and downloads iCloud Drive files first. The copy is moved out of the
/// temporary folder, which iOS may empty, into the staging folder.
class IosDocumentPicker implements DocumentPicker {
  IosDocumentPicker(this.stagingRoot);

  final String stagingRoot;

  @override
  Future<List<PickedFile>> pick() async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return const [];
    final batch = p.join(stagingRoot, 'doc-${_id()}');
    final out = <PickedFile>[];
    for (final (i, f) in picked.indexed) {
      final from = f.path;
      if (from == null) continue;
      final dest = p.join(batch, '$i', sanitizeFileName(f.name));
      try {
        await Directory(p.dirname(dest)).create(recursive: true);
        await File(from).rename(dest);
      } on FileSystemException catch (e) {
        // Keep reading from where the picker left it.
        logEvent('picker', 'could not move a pick (${e.osError?.errorCode})');
        out.add(
          PickedFile(
            ref: from,
            name: f.name,
            created: _modified(from),
            size: _length(from),
          ),
        );
        continue;
      }
      out.add(
        PickedFile(
          ref: dest,
          name: f.name,
          created: _modified(dest),
          size: _length(dest),
        ),
      );
    }
    return out;
  }

  @override
  Future<void> release(List<PickedFile> files) async {
    final batches = {
      for (final f in files) ?stagingBatchOf(f.ref, stagingRoot),
    };
    for (final b in batches) {
      await deleteStaging(b);
    }
  }

  static DateTime? _modified(String path) {
    try {
      return File(path).lastModifiedSync().toUtc();
    } on FileSystemException {
      return null;
    }
  }

  static int? _length(String path) {
    try {
      return File(path).lengthSync();
    } on FileSystemException {
      return null;
    }
  }

  static String _id() {
    final r = Random.secure();
    return [for (var i = 0; i < 6; i++) r.nextInt(256).toRadixString(16)]
        .join();
  }
}
