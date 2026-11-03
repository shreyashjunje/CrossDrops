import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// CPU time this process used so far (user + system), or null where
/// `getrusage` is not available (Windows).
///
/// `struct rusage` starts with two `struct timeval`s. Both on 64-bit
/// Android/Linux and on iOS/macOS each is 16 bytes: an 8-byte seconds
/// field, then microseconds (8 bytes on Linux, 4 plus padding on Darwin;
/// reading the low 4 bytes works for both, little-endian).
Duration? processCpuTime() {
  if (Platform.isWindows) return null;
  try {
    final lib = Platform.isAndroid || Platform.isLinux
        ? DynamicLibrary.open('libc.so${Platform.isLinux ? '.6' : ''}')
        : DynamicLibrary.process();
    final getrusage = lib
        .lookupFunction<
          Int32 Function(Int32, Pointer<Uint8>),
          int Function(int, Pointer<Uint8>)
        >('getrusage');
    final buf = calloc<Uint8>(256); // sizeof(struct rusage) is 144.
    try {
      if (getrusage(0 /* RUSAGE_SELF */, buf) != 0) return null;
      final data = buf.cast<Int64>();
      final micros = buf.cast<Int32>();
      final userSec = data[0];
      final userUsec = micros[2];
      final sysSec = data[2];
      final sysUsec = micros[6];
      return Duration(
        microseconds: (userSec + sysSec) * 1000000 + userUsec + sysUsec,
      );
    } finally {
      calloc.free(buf);
    }
  } on Object {
    return null;
  }
}

/// Samples CPU and memory of this process during a run.
///
/// CPU % is CPU time divided by wall time, so 100 % = one core busy; it
/// can exceed 100 % (the hash isolate runs in parallel).
class ProcessSampler {
  ProcessSampler({Duration? Function()? cpu, int Function()? rss})
    : _cpu = cpu ?? processCpuTime,
      _rss = rss ?? (() => ProcessInfo.currentRss);

  final Duration? Function() _cpu;
  final int Function() _rss;
  final Stopwatch _wall = Stopwatch();
  Duration? _cpuStart;
  int _peakRss = 0;

  void start() {
    _cpuStart = _cpu();
    _peakRss = _rss();
    _wall
      ..reset()
      ..start();
  }

  /// Call now and then (every progress update is fine).
  void sample() {
    final rss = _rss();
    if (rss > _peakRss) _peakRss = rss;
  }

  /// Stops and returns `(cpuPercent, peakRssBytes)`; CPU is null if the
  /// platform cannot tell.
  (double?, int) stop() {
    _wall.stop();
    sample();
    final start = _cpuStart;
    final end = _cpu();
    final wallUs = _wall.elapsedMicroseconds;
    final cpu = start == null || end == null || wallUs == 0
        ? null
        : (end - start).inMicroseconds * 100 / wallUs;
    return (cpu, _peakRss);
  }
}
