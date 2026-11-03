import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Benchmark builds only: `--dart-define=CROSSDROP_BENCH=true` on a release
/// build (D-058). Normal builds compile the benchmark code out.
const bool benchBuild = bool.fromEnvironment('CROSSDROP_BENCH');

/// Sizes in docs/BENCHMARKS.md, in bytes (MB = 2^20 here, as the test
/// files in DEVICE_TESTS.md).
const benchSizes = <int>[
  10 * 1024 * 1024,
  100 * 1024 * 1024,
  1024 * 1024 * 1024,
  2048 * 1024 * 1024,
];

const benchBuffers = <int>[256 * 1024, 1024 * 1024, 4 * 1024 * 1024];

/// `10 MB`, `1 GB`, `256 KB`.
String sizeLabel(int bytes) {
  const mib = 1024 * 1024;
  if (bytes >= 1024 * mib && bytes % (1024 * mib) == 0) {
    return '${bytes ~/ (1024 * mib)} GB';
  }
  if (bytes >= mib && bytes % mib == 0) return '${bytes ~/ mib} MB';
  if (bytes % 1024 == 0) return '${bytes ~/ 1024} KB';
  return '$bytes B';
}

final RegExp _benchName = RegExp(r'^crossdrop-bench-[0-9]+-[0-9a-f]{8}\.bin$');

/// The name a benchmark file is sent under. The run id makes each run a
/// new file on the receiver.
String benchFileName(int size, String runId) =>
    'crossdrop-bench-$size-$runId.bin';

/// True for names made by [benchFileName]. Benchmark builds discard such
/// files after verifying them, so 2 GB runs do not fill the phone.
bool isBenchFileName(String name) => _benchName.hasMatch(name);

/// A random run id: 8 lowercase hex characters.
String newRunId([Random? random]) {
  final r = random ?? Random.secure();
  return [
    for (var i = 0; i < 4; i++)
      r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// Writes (or reuses) a file of [size] random bytes in [dir], 1 MB at a
/// time; never the whole file in memory (CLAUDE.md hard rule 1). Random so
/// nothing on the way can compress it. Reused while its size matches.
Future<String> ensureBenchFile(String dir, int size) async {
  final path = p.join(dir, 'bench-$size.bin');
  final file = File(path);
  if (await file.exists() && await file.length() == size) return path;
  await Directory(dir).create(recursive: true);
  final tmp = File('$path.tmp');
  final raf = await tmp.open(mode: FileMode.write);
  try {
    // xorshift32: fast, and random enough that nothing compresses it.
    var x = 0x9e3779b9 ^ (size & 0xffffffff);
    if (x == 0) x = 1;
    const block = 1024 * 1024;
    final buf = Uint8List(block);
    final words = buf.buffer.asUint32List();
    var left = size;
    while (left > 0) {
      for (var i = 0; i < words.length; i++) {
        x ^= (x << 13) & 0xffffffff;
        x ^= x >> 17;
        x ^= (x << 5) & 0xffffffff;
        words[i] = x;
      }
      final n = left < block ? left : block;
      await raf.writeFrom(buf, 0, n);
      left -= n;
    }
  } finally {
    await raf.close();
  }
  await tmp.rename(path);
  return path;
}
