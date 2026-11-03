import '../protocol/file_type.dart';
import '../protocol/models.dart';
import '../security/device_identity.dart';

/// Where a received file goes after it is verified.
enum SaveCollection {
  /// iOS: the Photos library. Android: MediaStore Images, `Pictures/CrossDrop`.
  photos,

  /// iOS: the Photos library. Android: MediaStore Video, `Movies/CrossDrop`.
  videos,

  /// iOS: the app's Documents folder (Files app). Android: MediaStore
  /// Downloads, `Download/CrossDrop`.
  files,
}

/// Chooses the collection for a received file on [platform].
///
/// Decided from the **sanitized** name's extension, never from the MIME
/// type the sender declared (a sender could label anything "image/jpeg").
/// The sender's [declaredKind] counts only as intent: a file the sender
/// offered as a plain file stays a file, and a kind that does not match
/// the extension (a "video" called `.jpg`) goes to files.
///
/// Formats the gallery on [platform] is not known to open go to files
/// straight away. The gallery can still refuse a file at save time; the
/// platform saver then falls back to files and says so.
SaveCollection saveCollectionFor({
  required String safeName,
  required String declaredKind,
  required DevicePlatform platform,
}) {
  final mime = mimeForName(safeName);
  if (mime == null) return SaveCollection.files;
  final kind = kindForMime(mime);
  if (kind == FileKind.file || kind != declaredKind) {
    return SaveCollection.files;
  }
  final accepted = switch (platform) {
    DevicePlatform.ios => _iosPhotos.contains(mime),
    // MediaStore takes any image/* or video/* MIME into Images or Video.
    DevicePlatform.android => !_androidNotInGallery.contains(mime),
  };
  if (!accepted) return SaveCollection.files;
  return kind == FileKind.photo ? SaveCollection.photos : SaveCollection.videos;
}

/// What the iOS Photos library imports. Others (WebM, Matroska, AVI,
/// MPEG-TS, raw HEVC streams) are refused by `PHAssetCreationRequest`.
const Set<String> _iosPhotos = {
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/heic',
  'image/heif',
  'image/heic-sequence',
  'image/webp',
  'image/avif',
  'image/tiff',
  'image/bmp',
  'image/x-adobe-dng',
  'image/x-canon-cr2',
  'image/x-canon-cr3',
  'image/x-nikon-nef',
  'image/x-sony-arw',
  'video/quicktime',
  'video/mp4',
  'video/x-m4v',
  'video/3gpp',
  'video/3gpp2',
};

/// MediaStore accepts these MIME types, but galleries cannot show them.
const Set<String> _androidNotInGallery = {'video/hevc', 'image/heic-sequence'};
