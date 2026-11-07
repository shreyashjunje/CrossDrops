import 'package:crossdrop/core/media/save_target.dart';
import 'package:crossdrop/core/usb_import/camera_roll.dart';
import 'package:crossdrop/core/usb_import/import_runner.dart';
import 'package:flutter_test/flutter_test.dart';

ImportFile file(int handle, {String item = '', int? size = 100}) => ImportFile(
  object: CameraObject(
    handle: handle,
    name: 'IMG_$handle.HEIC',
    folder: 1,
    size: size,
  ),
  itemKey: item.isEmpty ? 'i$handle' : item,
  safeName: 'IMG_$handle.HEIC',
  mime: 'image/heic',
  collection: SaveCollection.photos,
);

void main() {
  test('copies every file in order and reports progress', () async {
    final copied = <int>[];
    final progress = <ImportProgress>[];
    final runner = ImportRunner(
      copy: (f) async {
        copied.add(f.object.handle);
        return f.object.size!;
      },
      freeBytes: () async => null,
    );
    final s = await runner.run([
      file(1),
      file(2),
      file(3),
    ], onProgress: progress.add);
    expect(copied, [1, 2, 3]);
    expect(s.copiedFiles, 3);
    expect(s.copiedItems, {'i1', 'i2', 'i3'});
    expect(s.failedFiles, 0);
    expect(s.notTried, 0);
    expect(s.bytes, 300);
    expect(s.stop, isNull);
    expect(progress.last.filesDone, 3);
    expect(progress.last.fraction, 1);
  });

  test('refuses before copying when space is short', () async {
    var calls = 0;
    final runner = ImportRunner(
      copy: (f) async {
        calls++;
        return 0;
      },
      freeBytes: () async => 1000,
      reserve: 800,
    );
    await expectLater(
      runner.run([file(1), file(2), file(3)]),
      throwsA(isA<NotEnoughSpace>().having((e) => e.needed, 'needed', 1100)),
    );
    expect(calls, 0);
  });

  test('a size mismatch is retried once, then counted as failed', () async {
    final tries = <int, int>{};
    final runner = ImportRunner(
      copy: (f) async {
        final n = tries.update(
          f.object.handle,
          (n) => n + 1,
          ifAbsent: () => 1,
        );
        if (f.object.handle == 2) throw const CopyFailure('size_mismatch');
        if (f.object.handle == 3 && n == 1) throw const CopyFailure('io');
        return 100;
      },
      freeBytes: () async => null,
    );
    final s = await runner.run([file(1), file(2), file(3)]);
    expect(tries, {1: 1, 2: 2, 3: 2});
    expect(s.copiedFiles, 2);
    expect(s.failedFiles, 1);
    expect(s.copiedItems, {'i1', 'i3'});
    expect(s.stop, isNull);
  });

  test('unplugging stops at once; copied files are kept', () async {
    final runner = ImportRunner(
      copy: (f) async {
        if (f.object.handle == 2) throw const CopyFailure('disconnected');
        return 100;
      },
      freeBytes: () async => null,
    );
    final s = await runner.run([file(1), file(2), file(3)]);
    expect(s.stop, ImportStop.disconnected);
    expect(s.copiedItems, {'i1'});
    expect(s.notTried, 2);
  });

  test('a full disk stops the import', () async {
    final runner = ImportRunner(
      copy: (f) async => throw const CopyFailure('no_space'),
      freeBytes: () async => null,
    );
    final s = await runner.run([file(1), file(2)]);
    expect(s.stop, ImportStop.noSpace);
    expect(s.copiedFiles, 0);
  });

  test('cancel stops after the current file', () async {
    late ImportRunner runner;
    runner = ImportRunner(
      copy: (f) async {
        if (f.object.handle == 2) runner.cancel();
        return 100;
      },
      freeBytes: () async => null,
    );
    final s = await runner.run([file(1), file(2), file(3), file(4)]);
    expect(s.stop, ImportStop.cancelled);
    expect(s.copiedItems, {'i1', 'i2'});
    expect(s.notTried, 2);
  });

  test('an item counts as copied only when all its files are', () async {
    final runner = ImportRunner(
      copy: (f) async {
        if (f.object.handle == 2) throw const CopyFailure('size_mismatch');
        return 100;
      },
      freeBytes: () async => null,
    );
    final s = await runner.run([
      file(1, item: 'live'),
      file(2, item: 'live'),
      file(3, item: 'plain'),
    ]);
    expect(s.copiedItems, {'plain'});
    expect(s.copiedFiles, 2);
  });

  test('device progress for the current file moves the bar', () async {
    final seen = <int>[];
    late ImportRunner runner;
    runner = ImportRunner(
      copy: (f) async {
        runner.reportBytes(f.object.handle, 40);
        runner.reportBytes(999, 70); // another file: ignored
        return 100;
      },
      freeBytes: () async => null,
    );
    await runner.run([file(1)], onProgress: (p) => seen.add(p.bytesDone));
    expect(seen, [0, 40, 100]);
  });
}
