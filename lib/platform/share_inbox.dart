import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/log.dart';
import '../core/media/prepare.dart';
import '../core/protocol/models.dart';
import 'android_source.dart';

/// Files another app shared to CrossDrop (D-044, D-045).
class SharedFiles {
  const SharedFiles({
    this.files = const [],
    this.textOnly = false,
    this.rejected = 0,
    this.truncated = 0,
  });

  final List<PickedFile> files;

  /// Only text or a link was shared; CrossDrop sends files.
  final bool textOnly;

  /// Items refused for safety (not a content URI, or CrossDrop's own).
  final int rejected;

  /// Items beyond [maxFilesPerOffer], left out.
  final int truncated;

  bool get isEmpty => files.isEmpty && !textOnly && rejected == 0;

  /// Several shares that arrived together, as one.
  static SharedFiles merge(Iterable<SharedFiles> all) {
    final files = <PickedFile>[];
    var text = false, rejected = 0, truncated = 0;
    for (final s in all) {
      files.addAll(s.files);
      text = text || s.textOnly;
      rejected += s.rejected;
      truncated += s.truncated;
    }
    return capped(
      files,
      textOnly: text && files.isEmpty,
      rejected: rejected,
      truncated: truncated,
    );
  }

  /// Keeps at most [max] files, counting the rest in [truncated].
  static SharedFiles capped(
    List<PickedFile> files, {
    bool textOnly = false,
    int rejected = 0,
    int truncated = 0,
    int max = maxFilesPerOffer,
  }) => SharedFiles(
    files: files.length > max ? files.sublist(0, max) : files,
    textOnly: textOnly,
    rejected: rejected,
    truncated: truncated + (files.length > max ? files.length - max : 0),
  );
}

/// Where shares from other apps arrive.
abstract interface class ShareInbox {
  /// Shares received since the last call (the app may have been started
  /// by one). Each is returned once.
  Future<SharedFiles> takePending();

  /// Fires when a share arrives while the app runs.
  Stream<void> get arrivals;
}

/// Android: SEND and SEND_MULTIPLE intents (android/.../ShareChannel.kt).
class AndroidShareInbox implements ShareInbox {
  AndroidShareInbox(this._sources, [MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('crossdrop/share') {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'arrived') _arrivals.add(null);
      return null;
    });
  }

  final AndroidSources _sources;
  final MethodChannel _channel;
  final _arrivals = StreamController<void>.broadcast();

  @override
  Stream<void> get arrivals => _arrivals.stream;

  @override
  Future<SharedFiles> takePending() async {
    final batches =
        await _channel.invokeListMethod<Map<Object?, Object?>>('takePending') ??
        const [];
    final out = <SharedFiles>[];
    for (final b in batches) {
      final uris = (b['uris'] as List? ?? const []).cast<String>();
      List<ContentInfo> infos;
      try {
        infos = await _sources.describe(uris);
      } on PlatformException catch (e) {
        logEvent('share', 'describe failed (${e.code})');
        infos = [for (final u in uris) ContentInfo(uri: u)];
      }
      out.add(
        SharedFiles(
          files: [
            for (final i in infos)
              PickedFile(
                ref: i.uri,
                name: i.name ?? 'file',
                mime: i.mime,
                created: i.created,
                platformKind: _kindFromMime(i.mime),
                size: i.size,
              ),
          ],
          textOnly: b['textOnly'] == true,
          rejected: (b['rejected'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return SharedFiles.merge(out);
  }

  /// A gallery shares MediaStore items with an image or video type.
  static String? _kindFromMime(String? mime) => mime == null
      ? null
      : mime.startsWith('image/')
      ? FileKind.photo
      : mime.startsWith('video/')
      ? FileKind.video
      : null;
}

/// One file listed in a Share Extension manifest.
class ManifestItem {
  const ManifestItem({required this.path, required this.name, this.kind});

  /// Absolute path, checked to be inside the share's folder.
  final String path;
  final String name;

  /// "photo", "video" or null.
  final String? kind;
}

/// Parses `manifest.json` written by the Share Extension (D-045) for the
/// share folder [dir]. Throws [FormatException] for anything unexpected:
/// a path outside [dir], a link, a missing file, too many items. The
/// extension is our own code, but the folder is shared, so it is checked
/// like any input.
({List<ManifestItem> items, int failed}) parseShareManifest(
  String json,
  String dir,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    throw const FormatException('manifest is not JSON');
  }
  if (decoded is! Map || decoded['v'] != 1) {
    throw const FormatException('unknown manifest version');
  }
  final list = decoded['items'];
  if (list is! List || list.length > maxFilesPerOffer) {
    throw const FormatException('bad items');
  }
  final failed = decoded['failed'];
  final items = <ManifestItem>[];
  for (final raw in list) {
    if (raw is! Map) throw const FormatException('bad item');
    final file = raw['file'];
    final name = raw['name'];
    final kind = raw['kind'];
    if (file is! String || file.isEmpty || p.isAbsolute(file)) {
      throw const FormatException('bad file path');
    }
    if (p.split(file).any((s) => s == '..' || s == '.')) {
      throw const FormatException('path escapes the share folder');
    }
    final path = p.normalize(p.join(dir, file));
    if (!p.isWithin(dir, path)) {
      throw const FormatException('path escapes the share folder');
    }
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException('missing file or a link');
    }
    final base = name is String ? p.basename(name.trim()) : '';
    items.add(
      ManifestItem(
        path: path,
        name: base.isEmpty ? p.basename(path) : base,
        kind: kind == FileKind.photo || kind == FileKind.video
            ? kind as String
            : null,
      ),
    );
  }
  return (items: items, failed: failed is int && failed > 0 ? failed : 0);
}

/// iOS: the Share Extension leaves files in the App Group inbox
/// (ios/ShareExtension, D-045). Each complete share (it has a manifest)
/// is moved into the staging folder and offered once. Shares without a
/// manifest for an hour were abandoned half-way and are deleted.
class IosShareInbox implements ShareInbox {
  IosShareInbox({
    required this.stagingRoot,
    MethodChannel? channel,
    DateTime Function()? clock,
  }) : _channel = channel ?? const MethodChannel('crossdrop/share'),
       _clock = clock ?? DateTime.now {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'arrived') _arrivals.add(null);
      return null;
    });
  }

  final String stagingRoot;
  final MethodChannel _channel;
  final DateTime Function() _clock;
  final _arrivals = StreamController<void>.broadcast();

  @override
  Stream<void> get arrivals => _arrivals.stream;

  @override
  Future<SharedFiles> takePending() async {
    final container = await _channel.invokeMethod<String>('containerPath');
    if (container == null) return const SharedFiles();
    return takeFrom(p.join(container, 'Inbox'));
  }

  /// [takePending] for an inbox folder; for tests.
  Future<SharedFiles> takeFrom(String inbox) async {
    final root = Directory(inbox);
    if (!await root.exists()) return const SharedFiles();
    final out = <SharedFiles>[];
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory) {
        await _delete(entry);
        continue;
      }
      final manifest = File(p.join(entry.path, 'manifest.json'));
      if (!await manifest.exists()) {
        final age = _clock().difference((await entry.stat()).modified);
        if (age > const Duration(hours: 1)) await _delete(entry);
        continue;
      }
      out.add(await _take(entry, manifest));
    }
    return SharedFiles.merge(out);
  }

  Future<SharedFiles> _take(Directory share, File manifest) async {
    final ({List<ManifestItem> items, int failed}) parsed;
    try {
      parsed = parseShareManifest(await manifest.readAsString(), share.path);
    } on Object catch (e) {
      logEvent('share', 'bad share manifest: ${e.runtimeType}');
      await _delete(share);
      return const SharedFiles(rejected: 1);
    }
    final dest = p.join(stagingRoot, 'share-${p.basename(share.path)}');
    try {
      await Directory(stagingRoot).create(recursive: true);
      await share.rename(dest);
    } on FileSystemException {
      // Another volume or container rules: copy, then delete.
      try {
        await _copyTree(share, dest);
        await _delete(share);
      } on FileSystemException catch (e) {
        logEvent('share', 'could not take a share (${e.osError?.errorCode})');
        await deleteStaging(dest);
        await _delete(share);
        return SharedFiles(rejected: parsed.items.length);
      }
    }
    return SharedFiles(
      files: [
        for (final i in parsed.items)
          PickedFile(
            ref: p.join(dest, p.relative(i.path, from: share.path)),
            name: i.name,
            platformKind: i.kind,
          ),
      ],
      rejected: parsed.failed,
    );
  }

  static Future<void> _copyTree(Directory from, String to) async {
    await for (final e in from.list(recursive: true, followLinks: false)) {
      final target = p.join(to, p.relative(e.path, from: from.path));
      if (e is Directory) {
        await Directory(target).create(recursive: true);
      } else if (e is File) {
        await Directory(p.dirname(target)).create(recursive: true);
        await e.copy(target);
      }
    }
  }

  static Future<void> _delete(FileSystemEntity e) async {
    try {
      await e.delete(recursive: true);
    } on FileSystemException {
      // Next time.
    }
  }
}
