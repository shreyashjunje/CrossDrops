import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../engine/send_session.dart';
import '../engine/source_opener.dart';
import '../log.dart';
import '../protocol/file_type.dart';
import '../protocol/models.dart';
import '../security/device_identity.dart';
import '../storage/file_name_sanitizer.dart';
import 'format_plan.dart';

/// Something the user picked, before it is ready to send.
sealed class PickedItem {
  const PickedItem();

  /// Shown in lists and skip messages. Never logged (hard rule 7).
  String get label;
}

/// A photo-library item (photo_manager asset).
final class PickedAsset extends PickedItem {
  const PickedAsset(this.asset);
  final LibraryAsset asset;

  @override
  String get label =>
      asset.originalName ?? (asset.kind == FileKind.video ? 'Video' : 'Photo');
}

/// A document, a shared file, or an Android content URI.
final class PickedFile extends PickedItem {
  const PickedFile({
    required this.ref,
    required this.name,
    this.mime,
    this.created,
    this.platformKind,
    this.size,
  });

  /// A file path, or a `content://` URI on Android.
  final String ref;
  final String name;
  final String? mime;
  final DateTime? created;

  /// "photo" or "video" when the OS says so (a share from a gallery).
  final String? platformKind;

  /// For the Send screen's total, when the platform said; the size sent
  /// is measured again when preparing.
  final int? size;

  @override
  String get label => name;
}

/// Why a picked item is not sent.
enum SkipReason {
  /// Deleted since it was picked, or hidden by Limited photo access.
  notFound,

  /// Only in iCloud, and the download failed or stalled.
  icloud,

  /// This phone has no space for the export.
  noSpace,

  /// The file cannot be read (permission revoked, provider error).
  unreadable,
}

class SkippedItem {
  const SkippedItem(this.label, this.reason);
  final String label;
  final SkipReason reason;
}

/// One file produced for a picked library item.
class ResolvedFile {
  const ResolvedFile({
    required this.ref,
    required this.size,
    required this.role,
    this.resourceName,
    this.originalName,
    this.mime,
    this.created,
    this.converted = false,
  });

  /// A staged file path (iOS) or a content URI (Android).
  final String ref;
  final int size;

  /// [ResolvedRole.still], [ResolvedRole.video] or [ResolvedRole.paired].
  final String role;

  /// The library resource's own name (`FullSizeRender.jpg` when edited).
  final String? resourceName;

  /// The item's original name in the library (`IMG_1234.HEIC`).
  final String? originalName;
  final String? mime;
  final DateTime? created;

  /// Re-encoded as JPEG.
  final bool converted;
}

abstract final class ResolvedRole {
  static const still = 'still';
  static const video = 'video';
  static const paired = 'paired';
}

/// A platform failure while preparing; [code] is a channel error code.
class MediaUnavailable implements Exception {
  const MediaUnavailable(this.code);
  final String code;

  SkipReason get reason => switch (code) {
    'not_found' => SkipReason.notFound,
    'icloud' => SkipReason.icloud,
    'no_space' => SkipReason.noSpace,
    _ => SkipReason.unreadable,
  };

  @override
  String toString() => 'MediaUnavailable($code)';
}

/// Lets the user stop a long preparation (iCloud downloads, big exports).
class PrepareControl {
  bool _cancelled = false;
  final List<Future<void> Function()> _onCancel = [];

  bool get isCancelled => _cancelled;

  /// Registers what stops the current platform call; returns a remover.
  void Function() onCancel(Future<void> Function() stop) {
    _onCancel.add(stop);
    return () => _onCancel.remove(stop);
  }

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    for (final stop in [..._onCancel]) {
      await stop();
    }
  }
}

/// Where preparation stands, for the "Preparing" screen.
class PrepareProgress {
  const PrepareProgress(this.index, this.count, this.fraction);

  /// 0-based item being prepared.
  final int index;
  final int count;

  /// Download progress of the current item (iCloud), or null.
  final double? fraction;
}

/// Platform part of preparing: exporting library items and copying
/// content that cannot be read in place.
abstract interface class MediaPlatform {
  /// iOS exports [asset] into [dir] (D-038); Android returns its content
  /// URI without copying. Throws [MediaUnavailable].
  Future<List<ResolvedFile>> resolveAsset(
    LibraryAsset asset,
    ExportPlan plan,
    String dir,
    PrepareControl control,
    void Function(double fraction) onProgress,
  );

  /// Streams [ref] into the file [dest]; returns its size. Throws
  /// [MediaUnavailable].
  Future<int> copyIntoStaging(String ref, String dest, PrepareControl control);
}

class PrepareResult {
  const PrepareResult({
    required this.items,
    required this.skipped,
    this.stagingDir,
    this.cancelled = false,
  });

  final List<SendItem> items;
  final List<SkippedItem> skipped;

  /// This batch's folder under the staging root, if anything was staged.
  /// Delete it when the send ends for good.
  final String? stagingDir;
  final bool cancelled;

  bool get ranOutOfSpace => skipped.any((s) => s.reason == SkipReason.noSpace);
}

/// Turns picked items into [SendItem]s before the offer (D-038).
///
/// Every failure skips that item with a reason, before anything is
/// offered: the session never has to skip a file half-way. Running out of
/// space skips the item and all after it.
class Preparer {
  Preparer({
    required MediaPlatform platform,
    required SourceOpener opener,
    required this.stagingRoot,
    this.settings = const FormatSettings(),
    this.receiver,
    String Function()? newBatchId,
  }) : _media = platform,
       _sources = opener,
       _newBatchId = newBatchId ?? _randomId;

  final MediaPlatform _media;
  final SourceOpener _sources;

  /// `<app support>/crossdrop_outgoing`; never the OS temp folder, which
  /// iOS may empty while a paused send waits to resume.
  final String stagingRoot;
  final FormatSettings settings;
  final DevicePlatform? receiver;
  final String Function() _newBatchId;

  Future<PrepareResult> prepare(
    List<PickedItem> picked, {
    PrepareControl? control,
    void Function(PrepareProgress)? onProgress,
  }) async {
    final ctl = control ?? PrepareControl();
    final batch = p.join(stagingRoot, _newBatchId());
    final items = <SendItem>[];
    final skipped = <SkippedItem>[];
    var noSpace = false;
    for (final (i, item) in picked.indexed) {
      if (ctl.isCancelled) break;
      if (noSpace) {
        skipped.add(SkippedItem(item.label, SkipReason.noSpace));
        continue;
      }
      onProgress?.call(PrepareProgress(i, picked.length, null));
      try {
        items.addAll(switch (item) {
          PickedAsset() => await _asset(item, i, batch, ctl, (f) {
            onProgress?.call(PrepareProgress(i, picked.length, f));
          }),
          PickedFile() => [await _file(item, i, batch, ctl)],
        });
      } on MediaUnavailable catch (e) {
        if (ctl.isCancelled || e.code == 'cancelled') break;
        logEvent('prepare', 'item $i skipped (${e.code})');
        skipped.add(SkippedItem(item.label, e.reason));
        if (e.reason == SkipReason.noSpace) noSpace = true;
      }
    }
    final staged = await _keepIfUsed(batch);
    if (ctl.isCancelled) {
      if (staged != null) await deleteStaging(staged);
      return PrepareResult(items: const [], skipped: skipped, cancelled: true);
    }
    return PrepareResult(items: items, skipped: skipped, stagingDir: staged);
  }

  Future<List<SendItem>> _asset(
    PickedAsset picked,
    int index,
    String batch,
    PrepareControl ctl,
    void Function(double) onProgress,
  ) async {
    final asset = picked.asset;
    final plan = planExport(asset, settings, receiver: receiver);
    final files = await _media.resolveAsset(
      asset,
      plan,
      p.join(batch, '$index'),
      ctl,
      onProgress,
    );
    if (files.isEmpty) throw const MediaUnavailable('not_found');
    final group =
        files.any((f) => f.role == ResolvedRole.paired) && files.length > 1
        ? 'lp$index'
        : null;
    return [
      for (final f in files)
        _item(asset, f, group: f.role == ResolvedRole.video ? null : group),
    ];
  }

  SendItem _item(LibraryAsset asset, ResolvedFile f, {String? group}) {
    final original = f.originalName ?? asset.originalName;
    final resource = f.resourceName ?? original ?? '';
    final name = f.role == ResolvedRole.paired
        ? pairedVideoName(originalName: original, videoResourceName: resource)
        : exportedFileName(
            originalName: original,
            exportedName: resource,
            convertedToJpeg: f.converted,
          );
    final kind = f.role == ResolvedRole.still ? asset.kind : FileKind.video;
    final type = detectFileType(
      name: name,
      platformMime: f.converted ? 'image/jpeg' : f.mime,
      platformKind: kind,
    );
    return SendItem(
      path: f.ref,
      name: name,
      size: f.size,
      mime: type.mime,
      kind: type.kind,
      created: f.created,
      livePhotoGroup: group,
    );
  }

  Future<SendItem> _file(
    PickedFile picked,
    int index,
    String batch,
    PrepareControl ctl,
  ) async {
    var ref = picked.ref;
    int size;
    try {
      final o = await _sources.open(ref);
      size = o.length;
      await o.close();
    } on SourceUnavailable catch (e) {
      if (e.reason != 'not_seekable') {
        throw MediaUnavailable(
          e.reason == 'not_found' ? 'not_found' : 'unreadable',
        );
      }
      // A streaming provider (some cloud apps): copy it once.
      final dest = p.join(batch, '$index', sanitizeFileName(picked.name));
      await Directory(p.dirname(dest)).create(recursive: true);
      size = await _media.copyIntoStaging(ref, dest, ctl);
      ref = dest;
    }
    final type = detectFileType(
      name: picked.name,
      platformMime: picked.mime,
      platformKind: picked.platformKind,
    );
    return SendItem(
      path: ref,
      name: picked.name,
      size: size,
      mime: type.mime,
      kind: type.kind,
      created: picked.created,
    );
  }

  /// Returns [batch] if anything was written there; removes it otherwise.
  static Future<String?> _keepIfUsed(String batch) async {
    final dir = Directory(batch);
    if (!await dir.exists()) return null;
    if (await dir.list(recursive: true).any((e) => e is File)) return batch;
    await deleteStaging(batch);
    return null;
  }

  static String _randomId() {
    final r = Random.secure();
    return [
      for (var i = 0; i < 8; i++)
        r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }
}

/// Deletes one staging batch folder. Never throws.
Future<void> deleteStaging(String dir) async {
  try {
    await Directory(dir).delete(recursive: true);
  } on FileSystemException {
    // Already gone.
  }
}

/// The staging batch folder [path] lives in, or null if it is not under
/// [stagingRoot].
String? stagingBatchOf(String path, String stagingRoot) {
  if (!p.isWithin(stagingRoot, path)) return null;
  final rel = p.split(p.relative(path, from: stagingRoot));
  return rel.isEmpty ? null : p.join(stagingRoot, rel.first);
}

/// Deletes staging batches that no unfinished send still reads from.
/// Run at app start, before anything prepares. Returns how many went.
Future<int> cleanStaging(String stagingRoot, Iterable<String> inUse) async {
  final keep = {for (final path in inUse) ?stagingBatchOf(path, stagingRoot)};
  final root = Directory(stagingRoot);
  if (!await root.exists()) return 0;
  var deleted = 0;
  await for (final entry in root.list(followLinks: false)) {
    if (keep.any((k) => p.equals(k, entry.path))) continue;
    try {
      await entry.delete(recursive: true);
      deleted++;
    } on FileSystemException {
      // Busy or gone; next launch tries again.
    }
  }
  if (deleted > 0) logEvent('storage', 'staging: deleted $deleted batch(es)');
  return deleted;
}
