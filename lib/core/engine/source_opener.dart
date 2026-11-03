import 'dart:io';

import 'chunked_reader.dart';

/// A file to send, opened for reading.
class OpenedSource {
  OpenedSource(this.source, this.length, [Future<void> Function()? release])
    : _release = release;

  final ByteSource source;

  /// Size in bytes now; compared with the offered size before sending.
  final int length;

  final Future<void> Function()? _release;
  bool _closed = false;

  /// Releases the descriptor, if any. Safe to call twice.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _release?.call();
  }
}

/// The file to send is gone, unreadable, or permission was revoked.
class SourceUnavailable implements Exception {
  const SourceUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'SourceUnavailable($reason)';
}

/// Opens what a [SendItem] points at: a file path, or a `content://` URI
/// on Android (D-036). Platform openers live in `lib/platform/`.
abstract interface class SourceOpener {
  /// Throws [SourceUnavailable].
  Future<OpenedSource> open(String ref);
}

/// Plain files: picked documents, iOS exports, tests and tools.
class FileSourceOpener implements SourceOpener {
  const FileSourceOpener();

  @override
  Future<OpenedSource> open(String ref) async {
    if (ref.isEmpty) throw const SourceUnavailable('no path');
    try {
      return OpenedSource(PathSource(ref), await File(ref).length());
    } on FileSystemException {
      throw const SourceUnavailable('not readable');
    }
  }
}
