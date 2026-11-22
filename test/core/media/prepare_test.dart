import 'dart:io';

import 'dart:async';

import 'package:crossdrop/core/engine/source_opener.dart';
import 'package:crossdrop/core/media/export_pipeline.dart';
import 'package:crossdrop/core/media/format_plan.dart';
import 'package:crossdrop/core/media/prepare.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late String staging;
  late _FakeMedia media;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cd_prep');
    staging = p.join(root.path, 'crossdrop_outgoing');
    media = _FakeMedia();
  });
  tearDown(() => root.deleteSync(recursive: true));

  Preparer preparer({
    FormatSettings settings = const FormatSettings(),
    SourceOpener opener = const FileSourceOpener(),
    int parallel = Preparer.defaultParallel,
    ExportPipeline? pipeline,
  }) => Preparer(
    platform: media,
    opener: opener,
    stagingRoot: staging,
    settings: settings,
    receiver: DevicePlatform.android,
    parallel: parallel,
    pipeline: pipeline,
    newBatchId: () => 'batch1',
  );

  PickedAsset asset(
    String id, {
    String kind = FileKind.photo,
    String? name,
    bool live = false,
  }) => PickedAsset(
    LibraryAsset(id: id, kind: kind, originalName: name, isLivePhoto: live),
  );

  group('export during the send (D-072)', () {
    test('planned items are offered first and exported in order', () async {
      media.plannable.addAll(['a', 'b', 'c']);
      final pipeline = ExportPipeline(
        media,
        const FileSourceOpener(),
        parallel: 1,
      );
      final r = await preparer(pipeline: pipeline).prepare([
        asset('a', name: 'IMG_1.HEIC'),
        asset('b', name: 'IMG_2.HEIC'),
        asset('c', kind: FileKind.video, name: 'IMG_3.MOV'),
      ]);

      expect(media.exported, isEmpty, reason: 'nothing exported yet');
      expect(r.items.map((i) => i.name), [
        'IMG_1.HEIC',
        'IMG_2.HEIC',
        'IMG_3.MOV',
      ]);
      expect(r.items.map((i) => i.size), [3, 3, 3]);
      expect(r.stagingDir, p.join(staging, 'batch1'), reason: 'kept');
      expect(pipeline.isPending(r.items[2].path), isTrue);

      // Opening the last one first starts its export at once.
      final o = await pipeline.open(r.items[2].path);
      expect(o.length, 3);
      await o.close();
      expect(media.exported, ['c']);
      expect(pipeline.isPending(r.items[2].path), isFalse);

      pipeline.start();
      await (await pipeline.open(r.items[1].path)).close();
      expect(media.exported, ['c', 'a', 'b']);
      await pipeline.cancel();
    });

    test('a failed export is tried once more, then unavailable', () async {
      media.plannable.add('a');
      media.failures['a'] = 'icloud';
      final pipeline = ExportPipeline(media, const FileSourceOpener());
      final r = await preparer(pipeline: pipeline)
          .prepare([asset('a', name: 'IMG_1.HEIC')]);
      pipeline.start();
      await expectLater(
        pipeline.open(r.items.single.path),
        throwsA(isA<SourceUnavailable>()),
      );
      expect(media.exported, ['a', 'a'], reason: 'background, then retry');
      await expectLater(
        pipeline.open(r.items.single.path),
        throwsA(isA<SourceUnavailable>()),
      );
      expect(media.exported, hasLength(2), reason: 'no third try');
    });

    test('a conversion is exported up front, as before', () async {
      media.plannable.add('a');
      final pipeline = ExportPipeline(media, const FileSourceOpener());
      final r = await preparer(
        pipeline: pipeline,
        settings: const FormatSettings(convertHeicToJpeg: true),
      ).prepare([asset('a', name: 'IMG_1.HEIC')]);
      expect(media.exported, ['a']);
      expect(pipeline.isEmpty, isTrue);
      expect(r.items.single.name, 'IMG_1.JPG');
    });

    test('cancel stops the exports still to come', () async {
      media.plannable.addAll(['a', 'b', 'c']);
      final gate = Completer<void>();
      media.onExport = (_) => gate.future;
      final pipeline = ExportPipeline(
        media,
        const FileSourceOpener(),
        parallel: 1,
      );
      await preparer(pipeline: pipeline)
          .prepare([asset('a'), asset('b'), asset('c')]);
      pipeline.start();
      await Future<void>.delayed(Duration.zero);
      final cancelled = pipeline.cancel();
      gate.complete();
      await cancelled;
      expect(media.exported, ['a']);
      expect(media.cancels, 1);
    });
  });

  test('exports photos and videos with their original names', () async {
    final r = await preparer().prepare([
      asset('a', name: 'IMG_0001.HEIC'),
      asset('b', kind: FileKind.video, name: 'IMG_0002.MOV'),
    ]);

    expect(r.skipped, isEmpty);
    expect(r.items.map((i) => i.name), ['IMG_0001.HEIC', 'IMG_0002.MOV']);
    expect(r.items[0].kind, FileKind.photo);
    expect(r.items[0].mime, 'image/heic');
    expect(r.items[1].kind, FileKind.video);
    expect(r.items[0].created, DateTime.utc(2026, 1, 2));
    expect(r.items[0].size, File(r.items[0].path).lengthSync());
    expect(r.stagingDir, p.join(staging, 'batch1'));
    expect(p.isWithin(r.stagingDir!, r.items[1].path), isTrue);
    expect(media.plans['a'], const ExportPlan(assetId: 'a'));
  });

  test('an edited photo is named after the original', () async {
    media.resourceNames['e'] = 'FullSizeRender.jpg';
    final r = await preparer().prepare([asset('e', name: 'IMG_0005.HEIC')]);
    expect(r.items.single.name, 'IMG_0005.JPG');
    expect(r.items.single.mime, 'image/jpeg');
  });

  test('HEIC to JPEG and Live Photo video follow the settings', () async {
    final r = await preparer(
      settings: const FormatSettings(
        convertHeicToJpeg: true,
        sendLivePhotoVideo: true,
      ),
    ).prepare([asset('l', name: 'IMG_0007.HEIC', live: true)]);

    expect(
      media.plans['l'],
      const ExportPlan(
        assetId: 'l',
        convertToJpeg: true,
        includePairedVideo: true,
      ),
    );
    expect(r.items.map((i) => i.name), ['IMG_0007.JPG', 'IMG_0007.MOV']);
    expect(r.items[0].mime, 'image/jpeg');
    expect(r.items[1].kind, FileKind.video);
    expect(r.items[0].livePhotoGroup, isNotNull);
    expect(r.items[1].livePhotoGroup, r.items[0].livePhotoGroup);
  });

  test('iCloud and deleted items are skipped; the rest go', () async {
    media.failures['cloud'] = 'icloud';
    media.failures['gone'] = 'not_found';
    final r = await preparer().prepare([
      asset('cloud', name: 'IMG_1.HEIC'),
      asset('ok', name: 'IMG_2.HEIC'),
      asset('gone', name: 'IMG_3.HEIC'),
    ]);

    expect(r.items.map((i) => i.name), ['IMG_2.HEIC']);
    expect(r.skipped.map((s) => (s.label, s.reason)), [
      ('IMG_1.HEIC', SkipReason.icloud),
      ('IMG_3.HEIC', SkipReason.notFound),
    ]);
    expect(r.ranOutOfSpace, isFalse);
  });

  test('several at once; the result keeps the pick order', () async {
    var running = 0, most = 0;
    media.onExport = (id) async {
      running++;
      most = running > most ? running : most;
      // Later picks finish first.
      await Future<void>.delayed(
        Duration(milliseconds: 5 * (6 - int.parse(id))),
      );
      running--;
    };
    final r = await preparer().prepare([
      for (var i = 1; i <= 5; i++) asset('$i', name: 'IMG_$i.HEIC'),
    ]);
    expect(r.items.map((i) => i.name), [
      for (var i = 1; i <= 5; i++) 'IMG_$i.HEIC',
    ]);
    expect(most, Preparer.defaultParallel);
  });

  test('out of space while others run: those finish, the rest skip', () async {
    media.failures['big'] = 'no_space';
    media.onExport = (id) async {
      if (id == 'slow') {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    };
    final r = await preparer(parallel: 2).prepare([
      asset('big', kind: FileKind.video, name: 'B.MOV'),
      asset('slow', name: 'S.HEIC'),
      asset('later', name: 'L.HEIC'),
    ]);
    expect(r.items.map((i) => i.name), ['S.HEIC']);
    expect(r.skipped.map((s) => (s.label, s.reason)), [
      ('B.MOV', SkipReason.noSpace),
      ('L.HEIC', SkipReason.noSpace),
    ]);
    expect(media.exported, ['big', 'slow'], reason: 'never tried "later"');
  });

  test('running out of space skips that item and everything after', () async {
    media.failures['big'] = 'no_space';
    final r = await preparer(parallel: 1).prepare([
      asset('ok', name: 'A.HEIC'),
      asset('big', kind: FileKind.video, name: 'B.MOV'),
      asset('later', name: 'C.HEIC'),
    ]);

    expect(r.items.map((i) => i.name), ['A.HEIC']);
    expect(r.skipped.map((s) => s.reason), [
      SkipReason.noSpace,
      SkipReason.noSpace,
    ]);
    expect(r.ranOutOfSpace, isTrue);
    expect(media.exported, ['ok', 'big'], reason: 'never tried "later"');
  });

  test('cancel stops at once and deletes what was staged', () async {
    final control = PrepareControl();
    media.onExport = (id) async {
      if (id == 'b') await control.cancel();
    };
    final r = await preparer().prepare([
      asset('a', name: 'A.HEIC'),
      asset('b', name: 'B.HEIC'),
      asset('c', name: 'C.HEIC'),
    ], control: control);

    expect(r.cancelled, isTrue);
    expect(r.items, isEmpty);
    expect(
      media.cancels,
      greaterThanOrEqualTo(1),
      reason: 'the running exports were stopped',
    );
    expect(Directory(p.join(staging, 'batch1')).existsSync(), isFalse);
  });

  test('progress counts done items, with the download fraction', () async {
    final seen = <(int, int, double?)>[];
    await preparer(parallel: 1).prepare([
      asset('a', name: 'A.HEIC'),
      asset('b', name: 'B.HEIC'),
    ], onProgress: (pr) => seen.add((pr.index, pr.count, pr.fraction)));
    expect(seen, containsAllInOrder([(0, 2, null), (0, 2, 0.5), (1, 2, null)]));
  });

  group('files', () {
    test('a readable file is sent in place', () async {
      final path = p.join(root.path, 'report.pdf');
      File(path).writeAsStringSync('pdf!');
      final r = await preparer().prepare([
        PickedFile(ref: path, name: 'report.pdf', created: DateTime.utc(2025)),
      ]);
      final item = r.items.single;
      expect(item.path, path);
      expect(item.size, 4);
      expect(item.mime, 'application/pdf');
      expect(item.kind, FileKind.file);
      expect(item.created, DateTime.utc(2025));
      expect(r.stagingDir, isNull, reason: 'nothing was copied');
    });

    test('a provider that cannot seek is copied into staging', () async {
      final r = await preparer(opener: const _ThrowingOpener('not_seekable'))
          .prepare([
            const PickedFile(
              ref: 'content://cloud/1',
              name: '../../evil:name.zip',
              mime: 'application/zip',
            ),
          ]);
      final item = r.items.single;
      expect(p.isWithin(p.join(staging, 'batch1'), item.path), isTrue);
      expect(p.basename(item.path), isNot(contains(':')));
      expect(item.size, 3);
      expect(
        item.name,
        '../../evil:name.zip',
        reason: 'the receiver sanitizes',
      );
      expect(r.stagingDir, isNotNull);
    });

    test('an unreadable or deleted file is skipped', () async {
      var r = await preparer(opener: const _ThrowingOpener('permission'))
          .prepare([const PickedFile(ref: 'content://x/1', name: 'a.txt')]);
      expect(r.skipped.single.reason, SkipReason.unreadable);

      r = await preparer().prepare([
        PickedFile(ref: p.join(root.path, 'nope.txt'), name: 'nope.txt'),
      ]);
      // FileSourceOpener says "not readable" for a missing path.
      expect(r.skipped.single.reason, SkipReason.unreadable);
      expect(r.items, isEmpty);
    });

    test('a gallery share keeps its kind', () async {
      final path = p.join(root.path, 'x');
      File(path).writeAsBytesSync([1, 2]);
      final r = await preparer().prepare([
        PickedFile(
          ref: path,
          name: 'x',
          mime: 'image/jpeg',
          platformKind: FileKind.photo,
        ),
      ]);
      expect(r.items.single.kind, FileKind.photo);
      expect(r.items.single.mime, 'image/jpeg');
    });
  });

  group('staging cleanup', () {
    test('keeps batches an unfinished send uses, deletes the rest', () async {
      for (final b in ['keep', 'old', 'other']) {
        final f = File(p.join(staging, b, '0', 'still.heic'));
        f.createSync(recursive: true);
      }
      final deleted = await cleanStaging(staging, [
        p.join(staging, 'keep', '0', 'still.heic'),
        '/elsewhere/file.jpg',
        'content://media/1',
      ], now: DateTime.now().add(const Duration(hours: 1)));
      expect(deleted, 2);
      expect(Directory(p.join(staging, 'keep')).existsSync(), isTrue);
      expect(Directory(p.join(staging, 'old')).existsSync(), isFalse);
    });

    test('keeps a batch made moments ago, such as a new share', () async {
      // Review H4: a share taken from the iOS inbox at launch is in no
      // unfinished send yet.
      File(p.join(staging, 'share-1A2B', 'IMG_1.HEIC'))
          .createSync(recursive: true);
      expect(await cleanStaging(staging, const []), 0);
      expect(Directory(p.join(staging, 'share-1A2B')).existsSync(), isTrue);
      final later = DateTime.now().add(const Duration(minutes: 11));
      expect(await cleanStaging(staging, const [], now: later), 1);
      expect(Directory(p.join(staging, 'share-1A2B')).existsSync(), isFalse);
    });

    test('no staging folder is fine', () async {
      expect(await cleanStaging(p.join(root.path, 'none'), const []), 0);
    });

    test('stagingBatchOf', () {
      expect(
        stagingBatchOf(p.join(staging, 'b1', '3', 'x.jpg'), staging),
        p.join(staging, 'b1'),
      );
      expect(stagingBatchOf(p.join(root.path, 'x.jpg'), staging), isNull);
      expect(stagingBatchOf(staging, staging), isNull);
    });
  });
}

class _FakeMedia implements MediaPlatform {
  final Map<String, ExportPlan> plans = {};
  final Map<String, String> failures = {};
  final Map<String, String> resourceNames = {};
  final List<String> exported = [];
  Future<void> Function(String id)? onExport;
  int cancels = 0;

  /// Ids whose files [planAsset] knows ahead (D-072).
  final Set<String> plannable = {};
  final List<String> planned = [];

  @override
  Future<List<ResolvedFile>?> planAsset(
    LibraryAsset asset,
    ExportPlan plan,
    String dir,
  ) async {
    if (!plannable.contains(asset.id) || plan.convertToJpeg) return null;
    planned.add(asset.id);
    return [
      ResolvedFile(
        ref: p.join(dir, 'still.bin'),
        size: 3,
        role: asset.kind == FileKind.video
            ? ResolvedRole.video
            : ResolvedRole.still,
        resourceName: asset.originalName,
        created: DateTime.utc(2026, 1, 2),
      ),
    ];
  }

  @override
  Future<List<ResolvedFile>> resolveAsset(
    LibraryAsset asset,
    ExportPlan plan,
    String dir,
    PrepareControl control,
    void Function(double) onProgress,
  ) async {
    plans[asset.id] = plan;
    exported.add(asset.id);
    final remove = control.onCancel(() async => cancels++);
    try {
      onProgress(0.5);
      await Directory(dir).create(recursive: true);
      final still = File(p.join(dir, 'still.bin'))..writeAsStringSync('img');
      await onExport?.call(asset.id);
      if (control.isCancelled) throw const MediaUnavailable('cancelled');
      final failure = failures[asset.id];
      if (failure != null) throw MediaUnavailable(failure);
      final role = asset.kind == FileKind.video
          ? ResolvedRole.video
          : ResolvedRole.still;
      return [
        ResolvedFile(
          ref: still.path,
          size: 3,
          role: role,
          resourceName: resourceNames[asset.id] ?? asset.originalName,
          created: DateTime.utc(2026, 1, 2),
          converted: plan.convertToJpeg,
        ),
        if (plan.includePairedVideo)
          ResolvedFile(
            ref: p.join(dir, 'paired.mov'),
            size: 0,
            role: ResolvedRole.paired,
            resourceName: 'IMG_X.MOV',
          ),
      ];
    } finally {
      remove();
    }
  }

  @override
  Future<int> copyIntoStaging(
    String ref,
    String dest,
    PrepareControl control,
  ) async {
    File(dest).writeAsStringSync('zip');
    return 3;
  }

  @override
  Future<Map<String, String>> originalNames(List<String> ids) async => {};
}

class _ThrowingOpener implements SourceOpener {
  const _ThrowingOpener(this.reason);
  final String reason;

  @override
  Future<OpenedSource> open(String ref) async =>
      throw SourceUnavailable(reason);
}
