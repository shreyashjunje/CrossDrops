import '../protocol/file_type.dart';
import '../protocol/models.dart';

/// What a small preview is made from. Only references cross the platform
/// channel, never file bytes (CLAUDE.md hard rule 2). Never logged: it can
/// hold a file name (hard rule 7).
sealed class ThumbRef {
  const ThumbRef();

  /// [FileKind.photo], [FileKind.video] or [FileKind.file]: the icon shown
  /// while the preview loads, or when there is none.
  String get kind;
}

/// A photo-library item: PhotoKit local identifier (iOS) or MediaStore id
/// (Android). The OS keeps these previews cached, so they are the fastest.
final class LibraryThumb extends ThumbRef {
  const LibraryThumb(this.assetId, {required this.kind});

  final String assetId;
  @override
  final String kind;

  @override
  bool operator ==(Object other) =>
      other is LibraryThumb && other.assetId == assetId;

  @override
  int get hashCode => Object.hash('lib', assetId);
}

/// A file path, or a `content://` URI on Android. The OS thumbnailer makes
/// the preview (Android `loadThumbnail`, iOS QuickLook).
final class FileThumb extends ThumbRef {
  const FileThumb(this.ref, {required this.kind});

  final String ref;
  @override
  final String kind;

  @override
  bool operator ==(Object other) => other is FileThumb && other.ref == ref;

  @override
  int get hashCode => Object.hash('file', ref);
}

/// The preview of a received file at its saved [location]: a path, a
/// content URI, or `photos:<id>` for the iPhone Photos library. Null when
/// there is nothing to show yet.
ThumbRef? thumbForLocation(String? location, {required String kind}) {
  if (location == null || location.isEmpty) return null;
  if (location.startsWith('photos:')) {
    final id = location.substring('photos:'.length);
    return id.isEmpty ? null : LibraryThumb(id, kind: kind);
  }
  return FileThumb(location, kind: kind);
}

/// The kind to show for a file the user picked, from what the OS said and
/// its name.
String pickedKind({required String name, String? mime, String? platformKind}) =>
    detectFileType(
      name: name,
      platformMime: mime,
      platformKind: platformKind,
    ).kind;
