import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Maximum length of a saved file name, in UTF-8 bytes. Most file systems
/// allow 255; we keep headroom for " (n)" suffixes.
const int maxFileNameBytes = 200;

const String _fallbackName = 'file';

final RegExp _forbiddenChars = RegExp(r'[\x00-\x1F\x7F-\x9F<>:"/\\|?*]');

/// Characters that change how a name is shown without being seen: bidi
/// embeddings, overrides, isolates and marks, zero-width characters, the
/// soft hyphen and the BOM. `photo\u202Egpj.exe` shows as `photoexe.jpg`
/// (review L8). They are removed; the name then shows what it is.
final RegExp _invisibleChars = RegExp(
  '[\u00AD\u061C\u180E\u200B-\u200F\u202A-\u202E\u2060-\u2064'
  '\u2066-\u2069\uFEFF\uFFF9-\uFFFB]',
);

final RegExp _reservedWindowsName = RegExp(
  r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])$',
  caseSensitive: false,
);

/// Turns a name received from the network into a safe single file name.
///
/// Strips any directory part, control and reserved characters, invisible
/// formatting characters, leading dots and trailing dots or spaces;
/// renames reserved device names; limits the length while keeping the
/// extension. Never returns an empty name, `.` or `..`.
String sanitizeFileName(String input) {
  // Keep only the last path segment, for both separators.
  var name = input.split(RegExp(r'[/\\]')).last;
  name = name.replaceAll(_invisibleChars, '');
  name = name.replaceAll(_forbiddenChars, '_');
  name = name.trim();
  // Leading dots would hide the file or form "..".
  name = name.replaceFirst(RegExp(r'^\.+'), '');
  // Windows and some Android storage drop trailing dots and spaces.
  name = name.replaceFirst(RegExp(r'[. ]+$'), '');
  if (name.isEmpty) return _fallbackName;

  final dot = name.lastIndexOf('.');
  var base = dot > 0 ? name.substring(0, dot) : name;
  var ext = dot > 0 ? name.substring(dot) : '';
  if (_reservedWindowsName.hasMatch(base)) base = '_$base';

  if (utf8.encode(ext).length > 20) {
    // An absurd "extension" is part of the name; truncate it with the rest.
    base = '$base$ext';
    ext = '';
  }
  base = _truncateUtf8(base, maxFileNameBytes - utf8.encode(ext).length);
  if (base.isEmpty) base = _fallbackName;
  return '$base$ext';
}

String _truncateUtf8(String s, int maxBytes) {
  if (utf8.encode(s).length <= maxBytes) return s;
  final out = StringBuffer();
  var used = 0;
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    final len = utf8.encode(ch).length;
    if (used + len > maxBytes) break;
    out.write(ch);
    used += len;
  }
  return out.toString();
}

/// Returns a path inside [dir] for [safeName] that does not exist yet,
/// adding " (1)", " (2)", ... before the extension if needed.
///
/// [safeName] must already be sanitized. Throws if the result would escape
/// [dir]. Only a guess: another writer may take the name before the caller
/// does. To write there, use [claimPath].
String availablePath(String dir, String safeName) {
  final ext = p.extension(safeName);
  final base = p.basenameWithoutExtension(safeName);
  var candidate = p.join(dir, safeName);
  for (
    var i = 1;
    File(candidate).existsSync() || Directory(candidate).existsSync();
    i++
  ) {
    candidate = p.join(dir, '$base ($i)$ext');
  }
  if (!p.isWithin(dir, candidate)) {
    throw StateError('refusing to write outside $dir');
  }
  return candidate;
}

/// Like [availablePath], but creates the file, empty and exclusively, and
/// returns its path. Two saves of the same name at once get two names;
/// with [availablePath] both could pick one and the second rename would
/// silently replace the first file (review L1). The caller moves its file
/// over the placeholder, or deletes it on failure.
Future<String> claimPath(String dir, String safeName) async {
  final ext = p.extension(safeName);
  final base = p.basenameWithoutExtension(safeName);
  for (var i = 0; i < 100000; i++) {
    final candidate = p.join(dir, i == 0 ? safeName : '$base ($i)$ext');
    if (!p.isWithin(dir, candidate)) {
      throw StateError('refusing to write outside $dir');
    }
    if (await Directory(candidate).exists()) continue;
    try {
      await File(candidate).create(exclusive: true);
      return candidate;
    } on PathExistsException {
      continue; // taken, maybe a moment ago
    }
  }
  throw FileSystemException('no free name', p.join(dir, safeName));
}
