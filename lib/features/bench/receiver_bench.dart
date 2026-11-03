import '../../core/bench/bench.dart';
import '../../core/bench/bench_stats.dart';
import '../../core/bench/process_stats.dart';
import '../../core/engine/chunked_reader.dart';
import '../../core/protocol/models.dart';
import '../receive/receive_controller.dart';

/// `iPhone`, `Android` from a protocol platform name.
String platformShort(String? platform) => switch (platform) {
  'ios' => 'iPhone',
  'android' => 'Android',
  _ => 'Other',
};

class _Track {
  _Track(this.sampler) {
    clock.start();
    sampler.start();
  }

  final ProcessSampler sampler;
  final Stopwatch clock = Stopwatch();
  final DateTime started = DateTime.now();
}

/// Records this phone's side of benchmark runs it receives: time, CPU and
/// memory (D-058). A session counts when every file in it has a benchmark
/// name. Time runs from the first received byte to the end of the session,
/// so it is close to, not the same as, the sender's figure.
class ReceiverBenchTracker {
  ReceiverBenchTracker({
    required this.me,
    required this.network,
    this.wifiBand,
    this.linkMbps,
    this.appVersion = '',
    ProcessSampler Function()? sampler,
  }) : _sampler = sampler ?? ProcessSampler.new;

  /// This phone's protocol platform name.
  final String me;
  String network;
  String? wifiBand;
  int? linkMbps;
  final String appVersion;
  final ProcessSampler Function() _sampler;
  final Map<String, _Track> _tracks = {};
  final Set<String> _finished = {};

  static bool isBenchSession(IncomingSession s) =>
      s.files.isNotEmpty &&
      s.files.values.every((f) => isBenchFileName(f.name));

  /// Feed every receive state; returns the runs that just ended.
  List<BenchResult> update(Iterable<IncomingSession> sessions) {
    final out = <BenchResult>[];
    for (final s in sessions) {
      if (_finished.contains(s.sessionId) || !isBenchSession(s)) continue;
      final track = _tracks[s.sessionId];
      if (track == null) {
        if (s.isActive && s.doneBytes > 0) {
          _tracks[s.sessionId] = _Track(_sampler());
        } else if (s.status.isTerminal) {
          _finished.add(s.sessionId);
        }
        continue;
      }
      track.sampler.sample();
      if (!s.status.isTerminal) continue;
      track.clock.stop();
      final (cpu, rss) = track.sampler.stop();
      _tracks.remove(s.sessionId);
      _finished.add(s.sessionId);
      final ok = s.status == SessionStatus.done;
      final elapsed = track.clock.elapsed;
      out.add(
        BenchResult(
          runId: _runIdOf(s),
          time: track.started,
          role: BenchRole.receiver,
          direction:
              '${platformShort(s.sender.platform)} → ${platformShort(me)}',
          network: network,
          fileBytes: s.totalBytes,
          bufferBytes: defaultChunkSize,
          run: 0,
          ok: ok,
          seconds: ok ? elapsed.inMicroseconds / 1e6 : null,
          avgMBps: ok ? mbPerSecond(s.totalBytes, elapsed) : null,
          cpuPercent: cpu,
          peakRssBytes: rss,
          reason: ok ? null : (s.reason ?? s.status.name),
          wifiBand: wifiBand,
          linkMbps: linkMbps,
          appVersion: appVersion,
        ),
      );
    }
    return out;
  }

  /// The sender's run id, from the file name, so both CSVs join on it.
  static String _runIdOf(IncomingSession s) {
    final name = s.files.values.first.name;
    final dash = name.lastIndexOf('-');
    final dot = name.lastIndexOf('.');
    return dash < 0 || dot <= dash ? '' : name.substring(dash + 1, dot);
  }
}
