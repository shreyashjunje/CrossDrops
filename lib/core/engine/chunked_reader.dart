import 'dart:io';
import 'dart:typed_data';

/// Default read/write buffer size. See ARCHITECTURE.md, "Performance design".
const int defaultChunkSize = 1024 * 1024;

/// Streams bytes [start, end) of the file at [path] in chunks of at most
/// [chunkSize]. Only one chunk is in memory at a time, and reading pauses
/// while the listener is paused.
Stream<Uint8List> readFileChunks(
  String path, {
  int start = 0,
  int? end,
  int chunkSize = defaultChunkSize,
}) async* {
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
