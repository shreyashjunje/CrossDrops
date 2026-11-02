import 'models.dart';

/// MIME type and [FileKind] from a file name's extension, for the offer
/// manifest. Only a hint for the receiver; unknown types are plain files.
({String? mime, String kind}) guessFileType(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  final mime = _mimeByExtension[ext];
  final kind = mime == null
      ? FileKind.file
      : mime.startsWith('image/')
      ? FileKind.photo
      : mime.startsWith('video/')
      ? FileKind.video
      : FileKind.file;
  return (mime: mime, kind: kind);
}

const Map<String, String> _mimeByExtension = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'dng': 'image/x-adobe-dng',
  'mov': 'video/quicktime',
  'mp4': 'video/mp4',
  'm4v': 'video/x-m4v',
  '3gp': 'video/3gpp',
  'webm': 'video/webm',
  'mkv': 'video/x-matroska',
  'pdf': 'application/pdf',
  'zip': 'application/zip',
  'txt': 'text/plain',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
};
