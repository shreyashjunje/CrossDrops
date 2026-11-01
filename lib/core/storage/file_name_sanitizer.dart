import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Maximum length of a saved file name, in UTF-8 bytes. Most file systems
/// allow 255; we keep headroom for " (n)" suffixes.
const int maxFileNameBytes = 200;

const String _fallbackName = 'file';

final RegExp _forbiddenChars = RegExp(r'[\x00-\x1F\x7F<>:"/\\|?*]');

final RegExp _reservedWindowsName = RegExp(
  r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])$',
  caseSensitive: false,
);

/// Turns a name received from the network into a safe single file name.
///
/// Strips any directory part, control and reserved characters, leading dots
/// and trailing dots or spaces; renames reserved device names; limits the
/// length while keeping the extension. Never returns an empty name, `.` or
/// `..`.
String sanitizeFileName(String input) {
  // Keep only the last path segment, for both separators.
  var name = input.split(RegExp(r'[/\\]')).last;
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
/// [dir].
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
