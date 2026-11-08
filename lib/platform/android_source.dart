import 'package:flutter/services.dart';

import '../core/engine/chunked_reader.dart';
import '../core/engine/fd_file.dart';
import '../core/engine/source_opener.dart';
import '../core/media/format_plan.dart';
import '../core/media/prepare.dart';
import '../core/protocol/models.dart';

/// What Android reports about a content URI before it is opened.
class ContentInfo {
  const ContentInfo({
    required this.uri,
    this.name,
    this.size,
    this.mime,
    this.modified,
    this.taken,
  });

  factory ContentInfo.fromMap(Map<Object?, Object?> m) {
    final size = (m['size'] as num?)?.toInt();
    DateTime? ms(Object? v) => v is num && v > 0
        ? DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true)
        : null;
    return ContentInfo(
      uri: m['uri']! as String,
      name: m['name'] as String?,
      size: size == null || size < 0 ? null : size,
      mime: m['mime'] as String?,
      modified: ms(m['modifiedMs']),
      taken: ms(m['takenMs']),
    );
  }

  final String uri;
  final String? name;

  /// Null when the provider does not say.
  final int? size;
  final String? mime;
  final DateTime? modified;

  /// MediaStore DATE_TAKEN (when the photo or video was shot).
  final DateTime? taken;

  /// The best creation date Android has for this item.
  DateTime? get created => taken ?? modified;
}

/// Error codes from the `crossdrop/source` channel.
abstract final class SourceErrors {
  static const notFound = 'not_found';
  static const permission = 'permission';
  static const notSeekable = 'not_seekable';
  static const noSpace = 'no_space';
  static const cancelled = 'cancelled';
}

/// Dart side of `crossdrop/source` (android/.../SourceChannel.kt).
class AndroidSources {
  AndroidSources([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('crossdrop/source');

  final MethodChannel _channel;

  /// Opens [uri] for reading. Throws [PlatformException] with a
  /// [SourceErrors] code.
  Future<({int fd, int size, bool original})> open(String uri) async {
    final m = (await _channel.invokeMapMethod<String, Object?>('open', {
      'uri': uri,
    }))!;
    return (
      fd: (m['fd']! as num).toInt(),
      size: (m['size']! as num).toInt(),
      original: m['original'] as bool? ?? true,
    );
  }

  Future<List<ContentInfo>> describe(List<String> uris) async {
    if (uris.isEmpty) return const [];
    final list = await _channel.invokeListMethod<Object?>('describe', {
      'uris': uris,
    });
    return [
      for (final m in list ?? const <Object?>[])
        ContentInfo.fromMap(m! as Map<Object?, Object?>),
    ];
  }

  /// The system document picker (Storage Access Framework). Empty if the
  /// user backed out.
  Future<List<String>> pickDocuments() async =>
      await _channel.invokeListMethod<String>('pickDocuments') ?? const [];

  /// Gives back the persistable read grants taken by [pickDocuments].
  Future<void> release(List<String> uris) async {
    if (uris.isEmpty) return;
    await _channel.invokeMethod<void>('release', {'uris': uris});
  }

  /// Streams [uri] into [dest] on the native side. For providers that
  /// cannot seek or have no size. Returns the byte count.
  Future<int> copy(String uri, String dest, String id) async =>
      (await _channel.invokeMethod<num>('copy', {
        'uri': uri,
        'dest': dest,
        'id': id,
      }))!.toInt();

  Future<void> cancelCopy(String id) =>
      _channel.invokeMethod<void>('cancelCopy', {'id': id});
}

/// Opens `content://` URIs as descriptors and everything else as files.
class AndroidSourceOpener implements SourceOpener {
  AndroidSourceOpener(this._sources);

  final AndroidSources _sources;

  @override
  Future<OpenedSource> open(String ref) async {
    if (!ref.startsWith('content://')) {
      return const FileSourceOpener().open(ref);
    }
    try {
      final o = await _sources.open(ref);
      return OpenedSource(
        FdSource(o.fd),
        o.size,
        () async => (await FdWorker.instance).close(o.fd),
      );
    } on PlatformException catch (e) {
      throw SourceUnavailable(e.code);
    }
  }
}

/// Android library items are read in place through their content URI;
/// nothing is exported (D-036).
class AndroidMedia implements MediaPlatform {
  AndroidMedia(this._sources, {required this.uriFor});

  final AndroidSources _sources;

  /// The MediaStore content URI for a photo_manager asset id.
  final Future<String?> Function(String assetId) uriFor;

  @override
  Future<List<ResolvedFile>> resolveAsset(
    LibraryAsset asset,
    ExportPlan plan,
    String dir,
    PrepareControl control,
    void Function(double fraction) onProgress,
  ) async {
    final uri = await uriFor(asset.id);
    if (uri == null) throw const MediaUnavailable('not_found');
    final ContentInfo info;
    final int size;
    try {
      info = (await _sources.describe([uri])).single;
      // The descriptor's size is the truth; the column can be stale.
      final o = await _sources.open(uri);
      size = o.size;
      await (await FdWorker.instance).close(o.fd);
    } on PlatformException catch (e) {
      throw MediaUnavailable(e.code);
    } on StateError {
      throw const MediaUnavailable('not_found');
    }
    final name = info.name ?? asset.originalName;
    return [
      ResolvedFile(
        ref: uri,
        size: size,
        role: asset.kind == FileKind.video
            ? ResolvedRole.video
            : ResolvedRole.still,
        resourceName: name,
        originalName: name,
        mime: info.mime,
        created: info.created,
      ),
    ];
  }

  /// The picker already has MediaStore's display names on Android.
  @override
  Future<Map<String, String>> originalNames(List<String> ids) async => const {};

  @override
  Future<int> copyIntoStaging(
    String ref,
    String dest,
    PrepareControl control,
  ) async {
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    final remove = control.onCancel(() => _sources.cancelCopy(id));
    try {
      return await _sources.copy(ref, dest, id);
    } on PlatformException catch (e) {
      throw MediaUnavailable(e.code);
    } finally {
      remove();
    }
  }
}
