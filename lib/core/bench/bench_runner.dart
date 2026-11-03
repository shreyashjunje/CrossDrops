import 'dart:async';

import '../engine/send_session.dart';
import '../log.dart';
import 'bench.dart';
import 'bench_stats.dart';
import 'process_stats.dart';

/// One file size and buffer size, run number [run].
class BenchCase {
  const BenchCase(this.fileBytes, this.bufferBytes, this.run);
  final int fileBytes;
  final int bufferBytes;
  final int run;

  @override
  bool operator ==(Object other) =>
      other is BenchCase &&
      other.fileBytes == fileBytes &&
      other.bufferBytes == bufferBytes &&
      other.run == run;

  @override
  int get hashCode => Object.hash(fileBytes, bufferBytes, run);

  @override
  String toString() =>
      '${sizeLabel(fileBytes)} / ${sizeLabel(bufferBytes)} #$run';
}

/// The runs of a series. Buffers alternate within each repeat, so a phone
/// warming up or a neighbour's traffic does not favour one buffer.
List<BenchCase> planCases({
  required List<int> sizes,
  required List<int> buffers,
  required int repeats,
}) => [
  for (final size in sizes)
    for (var run = 1; run <= repeats; run++)
      for (final buffer in buffers) BenchCase(size, buffer, run),
];

/// Builds the session that sends [path] (named [name]) to the chosen
/// receiver with [chunkSize].
typedef BenchSessionFactory = SendSession Function({
  required String path,
  required String name,
  required int size,
  required int chunkSize,
});

/// Runs benchmark cases through the real send engine (D-058).
///
/// Time counts from the first upload byte (after the Accept prompt) until
/// the receiver confirmed the verified save; that matches the app's own
/// "average" line. CPU and memory are this phone's only; the receiver
/// records its own.
class BenchRunner {
  BenchRunner({
    required this.newSession,
    required this.fileFor,
    required this.direction,
    required this.network,
    this.wifiBand,
    this.linkMbps,
    this.appVersion = '',
    this.pause = const Duration(seconds: 2),
    ProcessSampler Function()? sampler,
  }) : _sampler = sampler ?? ProcessSampler.new;

  final BenchSessionFactory newSession;

  /// The local file of a size (created on first use).
  final Future<String> Function(int size) fileFor;
  final String direction;
  final String network;
  final String? wifiBand;
  final int? linkMbps;
  final String appVersion;

  /// Rest between runs, so the previous run's teardown is over.
  final Duration pause;
  final ProcessSampler Function() _sampler;

  SendSession? _current;
  bool _cancelled = false;

  /// Runs [cases] in order and emits one result per case. Failures are
  /// results too; the series goes on.
  Stream<BenchResult> run(List<BenchCase> cases) async* {
    _cancelled = false;
    for (final (i, c) in cases.indexed) {
      if (_cancelled) return;
      if (i > 0) await Future<void>.delayed(pause);
      if (_cancelled) return;
      yield await runOne(c);
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    await _current?.cancel();
  }

  Future<BenchResult> runOne(BenchCase c) async {
    final runId = newRunId();
    final started = DateTime.now();
    BenchResult failed(String reason) => BenchResult(
      runId: runId,
      time: started,
      role: BenchRole.sender,
      direction: direction,
      network: network,
      fileBytes: c.fileBytes,
      bufferBytes: c.bufferBytes,
      run: c.run,
      ok: false,
      reason: reason,
      wifiBand: wifiBand,
      linkMbps: linkMbps,
      appVersion: appVersion,
    );

    final String path;
    try {
      path = await fileFor(c.fileBytes);
    } on Exception catch (e) {
      logEvent('bench', 'test file failed: ${e.runtimeType}');
      return failed('test_file');
    }
    final session = _current = newSession(
      path: path,
      name: benchFileName(c.fileBytes, runId),
      size: c.fileBytes,
      chunkSize: c.bufferBytes,
    );
    final recorder = ThroughputRecorder();
    final sampler = _sampler();
    final clock = Stopwatch();
    var retries = 0;
    var lastPhase = SendPhase.connecting;
    final sub = session.updates.listen((s) {
      if (s.phase == SendPhase.sending && !clock.isRunning) {
        clock.start();
        sampler.start();
      }
      if (clock.isRunning) {
        recorder.add(clock.elapsed, s.sentBytes);
        sampler.sample();
      }
      if (s.phase == SendPhase.retrying && lastPhase != SendPhase.retrying) {
        retries++;
      }
      lastPhase = s.phase;
    });
    final SendSnapshot end;
    try {
      end = await session.run();
    } finally {
      clock.stop();
      await sub.cancel();
      _current = null;
    }
    final (cpu, rss) = clock.elapsed > Duration.zero
        ? sampler.stop()
        : (null, 0);
    final ok =
        end.phase == SendPhase.done && end.files.every((f) => f.error == null);
    if (!ok) {
      return failed(end.reason ?? end.phase.name);
    }
    final elapsed = clock.elapsed;
    final result = BenchResult(
      runId: runId,
      time: started,
      role: BenchRole.sender,
      direction: direction,
      network: network,
      fileBytes: c.fileBytes,
      bufferBytes: c.bufferBytes,
      run: c.run,
      ok: true,
      seconds: elapsed.inMicroseconds / 1e6,
      avgMBps: mbPerSecond(c.fileBytes, elapsed),
      peakMBps: recorder.peakMBps(),
      cpuPercent: cpu,
      peakRssBytes: rss == 0 ? null : rss,
      retries: retries,
      wifiBand: wifiBand,
      linkMbps: linkMbps,
      appVersion: appVersion,
    );
    logEvent(
      'bench',
      '$c: ${result.avgMBps!.toStringAsFixed(1)} MB/s, '
          'retries $retries',
    );
    return result;
  }
}
