import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/log.dart';
import '../core/media/prepare.dart';
import '../core/storage/file_name_sanitizer.dart';
import 'android_source.dart';

/// The files of a picked folder (D-075), and how many were left out
/// (iCloud files not on the phone, unreadable files, more than 10,000).
typedef FolderPick = ({List<PickedFile> files, int skipped});

/// Reads a native `pickFolder` answer; [refKey] names the field that
/// holds the file's reference (`uri` on Android, `path` on iOS). Entries
/// missing a field are left out and counted.
FolderPick parseFolderPick(Map<Object?, Object?>? m, {required String refKey}) {
  final raw = m?['files'] as List<Object?>? ?? const [];
  var skipped = (m?['skipped'] as num?)?.toInt() ?? 0;
  final files = <PickedFile>[];
  for (final e in raw) {
    if (e is! Map<Object?, Object?>) {
      skipped++;
      continue;
    }
    final ref = e[refKey];
    final name = e['name'];
    final folder = e['folder'];
    if (ref is! String || name is! String || folder is! String) {
      skipped++;
      continue;
    }
    final size = (e['size'] as num?)?.toInt();
    final modified = (e['modifiedMs'] as num?)?.toInt();
    files.add(
      PickedFile(
        ref: ref,
        name: name,
        mime: e['mime'] as String?,
        size: size == null || size < 0 ? null : size,
        created: modified == null || modified <= 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(modified, isUtc: true),
        folder: folder,
      ),
    );
  }
  return (files: files, skipped: skipped);
}

/// The system picker for "any file" (D-041), and for a folder (D-075).
abstract interface class DocumentPicker {
  /// Empty if the user backed out.
  Future<List<PickedFile>> pick();

  /// Every file in a folder the user picks, subfolders included, each with
  /// its folder path. No files if the user backed out.
  Future<FolderPick> pickFolder();

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
  Future<FolderPick> pickFolder() async =>
      parseFolderPick(await _sources.pickFolder(), refKey: 'uri');

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

  /// Cloned into a new staging batch by OpenFileChannel.swift, so the
  /// folder stays readable after the picker's access ends.
  @override
  Future<FolderPick> pickFolder() async {
    final batch = p.join(stagingRoot, 'doc-${_id()}');
    await Directory(batch).create(recursive: true);
    final m = await _channel.invokeMapMethod<Object?, Object?>('pickFolder', {
      'staging': batch,
    });
    final pick = parseFolderPick(m, refKey: 'path');
    if (pick.files.isEmpty) await deleteStaging(batch);
    return pick;
  }

  static const _channel = MethodChannel('crossdrop/open');

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
