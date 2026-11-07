import 'dart:async';

import 'package:crossdrop/core/usb_import/thumbnail_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('newest request first, at most [parallel] at once', () async {
    final started = <int>[];
    final gates = <int, Completer<String?>>{};
    final q = ThumbnailQueue((h) {
      started.add(h);
      return (gates[h] = Completer<String?>()).future;
    }, parallel: 1);
    final f1 = q.load(1);
    final f2 = q.load(2);
    final f3 = q.load(3);
    await Future<void>.delayed(Duration.zero);
    expect(started, [3]); // the latest goes first
    gates[3]!.complete('/t/3.jpg');
    expect(await f3, '/t/3.jpg');
    await Future<void>.delayed(Duration.zero);
    expect(started, [3, 2]);
    gates[2]!.complete(null);
    await f2;
    await Future<void>.delayed(Duration.zero);
    expect(started, [3, 2, 1]);
    gates[1]!.complete('/t/1.jpg');
    expect(await f1, '/t/1.jpg');
  });

  test('a cancelled request never reaches the device', () async {
    final started = <int>[];
    final gates = <int, Completer<String?>>{};
    final q = ThumbnailQueue((h) {
      started.add(h);
      return (gates[h] = Completer<String?>()).future;
    }, parallel: 1);
    final f1 = q.load(1);
    final f2 = q.load(2);
    unawaited(q.load(3));
    await Future<void>.delayed(Duration.zero);
    expect(started, [3]);
    q.cancel(2);
    expect(await f2, isNull);
    gates[3]!.complete('/t/3.jpg');
    await Future<void>.delayed(Duration.zero);
    expect(started, [3, 1]);
    gates[1]!.complete('/t/1.jpg');
    expect(await f1, '/t/1.jpg');
  });

  test('results are cached, including "no preview"', () async {
    var calls = 0;
    final q = ThumbnailQueue((h) async {
      calls++;
      return h == 1 ? '/t/1.jpg' : null;
    });
    expect(await q.load(1), '/t/1.jpg');
    expect(await q.load(2), isNull);
    expect(await q.load(1), '/t/1.jpg');
    expect(q.has(2), isTrue);
    expect(q.cached(1), '/t/1.jpg');
    expect(calls, 2);
  });

  test('a failing device call counts as no preview', () async {
    final q = ThumbnailQueue((h) async => throw StateError('gone'));
    expect(await q.load(1), isNull);
  });

  test('the cache keeps the newest [capacity] results', () async {
    final q = ThumbnailQueue((h) async => '/t/$h.jpg', capacity: 2);
    for (final h in [1, 2, 3]) {
      await q.load(h);
    }
    await Future<void>.delayed(Duration.zero);
    expect(q.has(1), isFalse);
    expect(q.has(3), isTrue);
  });

  test('close completes waiting requests with null', () async {
    final q = ThumbnailQueue((h) => Completer<String?>().future, parallel: 1);
    unawaited(q.load(1));
    final f2 = q.load(2);
    q.close();
    expect(await f2, isNull);
  });
}
