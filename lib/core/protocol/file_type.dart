import 'models.dart';

/// MIME type and [FileKind] from a file name's extension, for the offer
/// manifest. Only a hint for the receiver; unknown types are plain files.
({String? mime, String kind}) guessFileType(String name) =>
    detectFileType(name: name);

/// MIME type and [FileKind] for a file about to be offered.
///
/// Precedence:
/// 1. [platformKind]: the photo library said "photo" or "video" (a Live
///    Photo still, a screenshot, a video). Trusted for the kind.
/// 2. [platformMime]: what the OS reports (ContentResolver, UTType), if it
///    is a real type. `application/octet-stream` means "unknown".
/// 3. The extension of [name].
///
/// The kind follows the MIME type when the library gave none: `image/*`
/// that a gallery can show is a photo, `video/*` a video, the rest a file
/// (audio, SVG, documents).
({String? mime, String kind}) detectFileType({
  required String name,
  String? platformMime,
  String? platformKind,
}) {
  final fromName = mimeForName(name);
  final reported = normalizeMime(platformMime);
  final mime = reported ?? fromName;
  final kind = switch (platformKind) {
    FileKind.photo || FileKind.video => platformKind!,
    _ => kindForMime(mime),
  };
  return (mime: mime, kind: kind);
}

/// The lower-case extension of [name] without the dot, or '' if it has
/// none. A leading dot alone (".hidden") is not an extension.
String extensionOf(String name) {
  final slash = name.lastIndexOf(RegExp(r'[/\\]'));
  final base = slash < 0 ? name : name.substring(slash + 1);
  final dot = base.lastIndexOf('.');
  if (dot <= 0 || dot == base.length - 1) return '';
  return base.substring(dot + 1).toLowerCase();
}

/// MIME type for [name]'s extension, or null if unknown.
String? mimeForName(String name) => _mimeByExtension[extensionOf(name)];

/// `type/subtype` in lower case without parameters, or null for missing,
/// malformed or "unknown" (`application/octet-stream`) types.
String? normalizeMime(String? mime) {
  if (mime == null) return null;
  final bare = mime.split(';').first.trim().toLowerCase();
  if (!RegExp(r'^[a-z0-9][a-z0-9.+-]*/[a-z0-9][a-z0-9.+-]*$').hasMatch(bare)) {
    return null;
  }
  if (bare == 'application/octet-stream' || bare.endsWith('/*')) return null;
  return bare;
}

/// [FileKind] for a MIME type. Images that galleries do not show as photos
/// (SVG, icons, PSD) are files.
String kindForMime(String? mime) {
  if (mime == null) return FileKind.file;
  if (mime.startsWith('image/')) {
    return _nonGalleryImages.contains(mime) ? FileKind.file : FileKind.photo;
  }
  if (mime.startsWith('video/')) return FileKind.video;
  return FileKind.file;
}

const Set<String> _nonGalleryImages = {
  'image/svg+xml',
  'image/x-icon',
  'image/vnd.microsoft.icon',
  'image/vnd.adobe.photoshop',
};

const Map<String, String> _mimeByExtension = {
  // Photos.
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'jpe': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heics': 'image/heic-sequence',
  'heif': 'image/heif',
  'hif': 'image/heif',
  'avif': 'image/avif',
  'bmp': 'image/bmp',
  'tif': 'image/tiff',
  'tiff': 'image/tiff',
  'dng': 'image/x-adobe-dng',
  'cr2': 'image/x-canon-cr2',
  'cr3': 'image/x-canon-cr3',
  'nef': 'image/x-nikon-nef',
  'arw': 'image/x-sony-arw',
  'svg': 'image/svg+xml',
  'ico': 'image/x-icon',
  'psd': 'image/vnd.adobe.photoshop',
  // Videos.
  'mov': 'video/quicktime',
  'qt': 'video/quicktime',
  'mp4': 'video/mp4',
  'm4v': 'video/x-m4v',
  '3gp': 'video/3gpp',
  '3g2': 'video/3gpp2',
  'webm': 'video/webm',
  'mkv': 'video/x-matroska',
  'avi': 'video/x-msvideo',
  'mts': 'video/mp2t',
  'm2ts': 'video/mp2t',
  'hevc': 'video/hevc',
  // Audio (saved as files).
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'wav': 'audio/wav',
  'flac': 'audio/flac',
  'ogg': 'audio/ogg',
  'opus': 'audio/opus',
  'amr': 'audio/amr',
  // Documents and archives.
  'pdf': 'application/pdf',
  'zip': 'application/zip',
  '7z': 'application/x-7z-compressed',
  'rar': 'application/vnd.rar',
  'gz': 'application/gzip',
  'tar': 'application/x-tar',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'json': 'application/json',
  'html': 'text/html',
  'rtf': 'application/rtf',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'pages': 'application/vnd.apple.pages',
  'numbers': 'application/vnd.apple.numbers',
  'key': 'application/vnd.apple.keynote',
  'epub': 'application/epub+zip',
  'apk': 'application/vnd.android.package-archive',
  'vcf': 'text/vcard',
  'ics': 'text/calendar',
};
