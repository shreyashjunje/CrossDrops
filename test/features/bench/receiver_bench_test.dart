import 'package:crossdrop/core/bench/bench.dart';
import 'package:crossdrop/core/bench/bench_stats.dart';
import 'package:crossdrop/core/bench/process_stats.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/features/bench/receiver_bench.dart';
import 'package:crossdrop/features/receive/receive_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _sender = SenderInfo(id: 'a', name: 'iPhone', platform: 'ios');

IncomingSession session(
  String name,
  SessionStatus status, {
  int done = 0,
  String id = 's1',
}) => IncomingSession(
  sessionId: id,
  sender: _sender,
  status: status,
  files: {'f0': IncomingFile(name: name, size: 1000000)},
  doneBytes: done,
);

void main() {
  final bench = benchFileName(1000000, 'abcd1234');

  ReceiverBenchTracker tracker() => ReceiverBenchTracker(
    me: 'android',
    network: 'Router 5 GHz',
    sampler: () => ProcessSampler(cpu: () => Duration.zero, rss: () => 5),
  );

  test('records one row per finished benchmark session', () {
    final t = tracker();
    expect(t.update([session(bench, SessionStatus.accepted)]), isEmpty);
    expect(
      t.update([session(bench, SessionStatus.transferring, done: 10)]),
      isEmpty,
    );
    final rows = t.update([session(bench, SessionStatus.done, done: 1000000)]);
    expect(rows, hasLength(1));
    final r = rows.single;
    expect(r.role, BenchRole.receiver);
    expect(r.ok, isTrue);
    expect(r.runId, 'abcd1234');
    expect(r.direction, 'iPhone → Android');
    expect(r.fileBytes, 1000000);
    expect(r.peakRssBytes, 5);
    // Reported once only.
    expect(t.update([session(bench, SessionStatus.done)]), isEmpty);
  });

  test('ignores sessions with other files', () {
    final t = tracker();
    t.update([session('IMG_0001.HEIC', SessionStatus.transferring, done: 1)]);
    expect(t.update([session('IMG_0001.HEIC', SessionStatus.done)]), isEmpty);
  });

  test('a failed run is a failed row with the reason', () {
    final t = tracker();
    t.update([session(bench, SessionStatus.transferring, done: 1)]);
    final rows = t.update([session(bench, SessionStatus.cancelled)]);
    expect(rows.single.ok, isFalse);
    expect(rows.single.reason, 'cancelled');
  });

  test('a session that ended before it was seen is skipped', () {
    final t = tracker();
    expect(t.update([session(bench, SessionStatus.done)]), isEmpty);
  });
}
