import '../protocol/file_type.dart';
import '../protocol/models.dart';
import '../security/device_identity.dart';

/// The user's format settings for sending (ARCHITECTURE.md, "HEIC photos"
/// and "Live Photos"). Both off by default: send the original still.
class FormatSettings {
  const FormatSettings({
    this.convertHeicToJpeg = false,
    this.sendLivePhotoVideo = false,
  });

  final bool convertHeicToJpeg;
  final bool sendLivePhotoVideo;

  @override
  bool operator ==(Object other) =>
      other is FormatSettings &&
      other.convertHeicToJpeg == convertHeicToJpeg &&
      other.sendLivePhotoVideo == sendLivePhotoVideo;

  @override
  int get hashCode => Object.hash(convertHeicToJpeg, sendLivePhotoVideo);
}

/// A photo-library item as the picker describes it, before export.
class LibraryAsset {
  const LibraryAsset({
    required this.id,
    required this.kind,
    this.originalName,
    this.mime,
    this.isLivePhoto = false,
    this.created,
  });

  /// PhotoKit local identifier (iOS) or MediaStore id (Android).
  final String id;

  /// [FileKind.photo] or [FileKind.video].
  final String kind;

  /// The original file name in the library, e.g. `IMG_1234.HEIC`.
  final String? originalName;
  final String? mime;
  final bool isLivePhoto;

  /// When it was taken, for a label while the name is not known yet.
  final DateTime? created;

  LibraryAsset withName(String? name) => name == null || name.isEmpty
      ? this
      : LibraryAsset(
          id: id,
          kind: kind,
          originalName: name,
          mime: mime,
          isLivePhoto: isLivePhoto,
          created: created,
        );

  bool get isHeic {
    final m = normalizeMime(mime) ?? mimeForName(originalName ?? '');
    return m == 'image/heic' || m == 'image/heif';
  }
}

/// What to export for one [LibraryAsset].
class ExportPlan {
  const ExportPlan({
    required this.assetId,
    this.convertToJpeg = false,
    this.includePairedVideo = false,
  });

  final String assetId;

  /// Re-encode the still as JPEG (HEIC only).
  final bool convertToJpeg;

  /// Also export the Live Photo's video, as a second file.
  final bool includePairedVideo;

  @override
  bool operator ==(Object other) =>
      other is ExportPlan &&
      other.assetId == assetId &&
      other.convertToJpeg == convertToJpeg &&
      other.includePairedVideo == includePairedVideo;

  @override
  int get hashCode => Object.hash(assetId, convertToJpeg, includePairedVideo);

  @override
  String toString() =>
      'ExportPlan($assetId, jpeg: $convertToJpeg, video: $includePairedVideo)';
}

/// Decides how to send [asset] to a [receiver] (D-039).
///
/// Format settings apply only from iPhone to Android, the case they exist
/// for. Everything else is sent as the original: HEVC and HDR video
/// unchanged, no transcoding in v1. A receiver of unknown platform is
/// treated as Android, the only other platform in v1.
ExportPlan planExport(
  LibraryAsset asset,
  FormatSettings settings, {
  required DevicePlatform? receiver,
}) {
  final toAndroid = receiver != DevicePlatform.ios;
  final photo = asset.kind == FileKind.photo;
  return ExportPlan(
    assetId: asset.id,
    convertToJpeg:
        toAndroid && photo && settings.convertHeicToJpeg && asset.isHeic,
    includePairedVideo:
        toAndroid && photo && settings.sendLivePhotoVideo && asset.isLivePhoto,
  );
}

/// The name to offer for an exported library still or video.
///
/// [originalName] is the library's original file name (`IMG_1234.HEIC`).
/// [exportedName] is the name of the resource actually exported, which
/// differs for edited items (`FullSizeRender.jpg`) and conversions. The
/// result keeps the original base and takes the exported extension, in
/// the original's letter case: `IMG_1234.JPG`, not `FullSizeRender.jpg`.
String exportedFileName({
  required String? originalName,
  required String exportedName,
  bool convertedToJpeg = false,
}) {
  final original = _split(originalName ?? '');
  final exported = _split(exportedName);
  final base = original.base.isNotEmpty ? original.base : exported.base;
  var ext = convertedToJpeg
      ? 'jpg'
      : exported.ext.isNotEmpty
      ? exported.ext
      : original.ext;
  if (original.ext.isNotEmpty && original.ext == original.ext.toUpperCase()) {
    ext = ext.toUpperCase();
  } else {
    ext = ext.toLowerCase();
  }
  final safeBase = base.isEmpty ? 'IMG' : base;
  return ext.isEmpty ? safeBase : '$safeBase.$ext';
}

/// The name for a Live Photo's video: the still's base with the video's
/// extension, so both sort together (`IMG_1234.HEIC`, `IMG_1234.MOV`).
String pairedVideoName({
  required String? originalName,
  required String videoResourceName,
}) => exportedFileName(
  originalName: originalName,
  exportedName: videoResourceName,
);

({String base, String ext}) _split(String name) {
  final slash = name.lastIndexOf(RegExp(r'[/\\]'));
  final file = slash < 0 ? name : name.substring(slash + 1);
  final dot = file.lastIndexOf('.');
  if (dot <= 0) return (base: file, ext: '');
  return (base: file.substring(0, dot), ext: file.substring(dot + 1));
}
