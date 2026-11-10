import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'fd_file.dart';

/// Default read/write buffer size. See ARCHITECTURE.md, "Performance design".
const int defaultChunkSize = 1024 * 1024;

/// Where the bytes of a file to send come from. Plain data, so it can be
/// handed to the hash isolate.
sealed class ByteSource {
  const ByteSource();
}

/// A file on disk: picked documents, iOS exports, tests and tools.
final class PathSource extends ByteSource {
  const PathSource(this.path);
  final String path;

  @override
  String toString() => 'PathSource';
}

/// An open file descriptor (Android content URIs, D-036). Whoever opened
/// it closes it; readers never do.
final class FdSource extends ByteSource {
  const FdSource(this.fd);
  final int fd;

  @override
  String toString() => 'FdSource($fd)';
}

/// The size of [source] in bytes. -1 for a descriptor that cannot seek.
Future<int> sourceLength(ByteSource source) async => switch (source) {
  PathSource(:final path) => File(path).length(),
  FdSource(:final fd) => (await FdWorker.instance).length(fd),
};

/// Streams bytes [start, end) of the file at [path] in chunks of at most
/// [chunkSize]. Only one chunk is in memory at a time, and reading pauses
/// while the listener is paused.
Stream<Uint8List> readFileChunks(
  String path, {
  int start = 0,
  int? end,
  int chunkSize = defaultChunkSize,
}) => readSourceChunks(
  PathSource(path),
  start: start,
  end: end,
  chunkSize: chunkSize,
);

/// [readFileChunks] for any [ByteSource]. Descriptor reads run on the
/// [FdWorker] isolate, never blocking this one.
Stream<Uint8List> readSourceChunks(
  ByteSource source, {
  int start = 0,
  int? end,
  int chunkSize = defaultChunkSize,
}) => switch (source) {
  PathSource(:final path) => _readPath(path, start, end, chunkSize),
  FdSource(:final fd) => _readFd(fd, start, end, chunkSize),
};

Stream<Uint8List> _readPath(
  String path,
  int start,
  int? end,
  int chunkSize,
) async* {
  final raf = await File(path).open();
  try {
    final stop = end ?? await raf.length();
    await raf.setPosition(start);
    var pos = start;
    while (pos < stop) {
      final want = stop - pos < chunkSize ? stop - pos : chunkSize;
      final chunk = await raf.read(want);
      if (chunk.isEmpty) {
        throw FileSystemException('file shorter than expected', path);
      }
      pos += chunk.length;
      yield chunk;
    }
  } finally {
    await raf.close();
  }
}

Stream<Uint8List> _readFd(int fd, int start, int? end, int chunkSize) async* {
  final io = await FdWorker.instance;
  final stop = end ?? await io.length(fd);
  if (stop < 0) {
    throw const FileSystemException('descriptor is not seekable');
  }
  var pos = start;
  while (pos < stop) {
    final want = stop - pos < chunkSize ? stop - pos : chunkSize;
    final chunk = await io.readAt(fd, pos, want);
    if (chunk.isEmpty) {
      throw const FileSystemException('file shorter than expected');
    }
    pos += chunk.length;
    yield chunk;
  }
}

/// Streams the given [ranges] of [source], in order, in chunks of at most
/// [chunkSize]: the whole rest of a file, or one stripe of it (D-071).
///
/// With [blocking], descriptor reads block the calling isolate instead of
/// going through the [FdWorker]: for upload workers, which are background
/// isolates already.
Stream<Uint8List> readSourceRanges(
  ByteSource source,
  Iterable<({int start, int end})> ranges, {
  int chunkSize = defaultChunkSize,
  bool blocking = false,
}) async* {
  final RandomAccessFile? raf;
  final Future<Uint8List> Function(int pos, int want) read;
  switch (source) {
    case PathSource(:final path):
      final file = raf = await File(path).open();
      read = (pos, want) async {
        await file.setPosition(pos);
        return file.read(want);
      };
    case FdSource(:final fd):
      raf = null;
      if (blocking) {
        final file = FdFile(fd);
        read = (pos, want) async => file.readAt(pos, want);
      } else {
        final io = await FdWorker.instance;
        read = (pos, want) => io.readAt(fd, pos, want);
      }
  }
  try {
    for (final r in ranges) {
      var pos = r.start;
      while (pos < r.end) {
        final want = r.end - pos < chunkSize ? r.end - pos : chunkSize;
        final chunk = await read(pos, want);
        if (chunk.isEmpty) {
          throw const FileSystemException('file shorter than expected');
        }
        pos += chunk.length;
        yield chunk;
      }
    }
  } finally {
    await raf?.close();
  }
}

/// Blocking chunk reader for background isolates (the hash worker).
/// Yields between chunks so the isolate can see a stop request.
Stream<Uint8List> readSourceChunksInIsolate(
  ByteSource source, {
  int start = 0,
  int? end,
  int chunkSize = defaultChunkSize,
}) async* {
  switch (source) {
    case PathSource(:final path):
      yield* _readPath(path, start, end, chunkSize);
    case FdSource(:final fd):
      final file = FdFile(fd);
      final stop = end ?? file.length();
      // One native buffer for the whole read instead of one per chunk
      // (review, speed item 5). Chunks are copies, so none outlives it.
      final buf = malloc<Uint8>(chunkSize);
      try {
        var pos = start;
        while (pos < stop) {
          final want = stop - pos < chunkSize ? stop - pos : chunkSize;
          final got = file.readInto(buf, pos, want);
          if (got == 0) {
            throw const FileSystemException('file shorter than expected');
          }
          pos += got;
          yield Uint8List.fromList(buf.asTypedList(got));
          await Future<void>.delayed(Duration.zero);
        }
      } finally {
        malloc.free(buf);
      }
  }
}
