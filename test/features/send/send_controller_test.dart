import 'dart:async';
import 'dart:convert';

import 'package:crossdrop/app/keep_alive.dart';
import 'package:crossdrop/app/media_providers.dart';
import 'package:crossdrop/app/providers.dart';
import 'package:crossdrop/core/client/peer_check.dart';
import 'package:crossdrop/core/media/format_plan.dart';
import 'package:crossdrop/core/media/prepare.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/features/nearby/nearby_controller.dart';
import 'package:crossdrop/features/send/send_controller.dart';
import 'package:crossdrop/platform/document_picker.dart';
import 'package:crossdrop/platform/keep_alive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoKeepAlive implements KeepAlivePlatform {
  @override
  Future<void> setScreenOn(bool on) async {}
  @override
  Future<bool> ensureNotificationPermission() async => true;
  @override
  Future<void> startService({
    required String title,
    required String text,
  }) async {}
  @override
  Future<void> updateService({required String text}) async {}
  @override
  Future<void> stopService() async {}
  @override
  Future<void> beginBackgroundTask({
    required void Function() onExpiring,
  }) async {}
  @override
  Future<void> endBackgroundTask() async {}
}

void main() {
  test('Cancel during the peer check stops the send (review L4)', () async {
    // A typed address is checked before anything is prepared; there was
    // no preparation or session yet, so Cancel did nothing and the send
    // started anyway.
    final check = Completer<ConnectTarget>();
    var prepared = false;
    final c = ProviderContainer(
      overrides: [
        keepAliveProvider.overrideWithValue(
          KeepAliveCoordinator(_NoKeepAlive(), pauseInBackground: false),
        ),
        peerCheckProvider.overrideWithValue((_) => check.future),
        appDirsProvider.overrideWith((ref) async {
          prepared = true;
          throw StateError('must not prepare after a cancel');
        }),
      ],
    );
    addTearDown(c.dispose);
    final ctrl = c.read(sendControllerProvider.notifier);
    ctrl.addShared(const [PickedFile(ref: '/tmp/x.bin', name: 'x.bin')]);

    final sending = ctrl.send(
      const ConnectTarget(host: '192.168.1.5', port: 4000),
    );
    await pumpEventQueue();
    expect(c.read(sendControllerProvider).isRunning, isTrue);
    await ctrl.cancel();
    expect(c.read(sendControllerProvider).isRunning, isFalse);

    check.complete(
      ConnectTarget(
        host: '192.168.1.5',
        port: 4000,
        fingerprint: 'a' * 64,
        pinSource: PinSource.firstContact,
      ),
    );
    await sending;
    expect(prepared, isFalse);
    final s = c.read(sendControllerProvider);
    expect(s.snapshot, isNull);
    expect(s.isRunning, isFalse);
    expect(s.picked, hasLength(1), reason: 'the selection stays');
  });

  test('library picks get their real file names, in one lookup', () async {
    final media = _NamingMedia({'a': 'IMG_0001.HEIC', 'v': 'IMG_0002.MOV'});
    final c = ProviderContainer(
      overrides: [
        keepAliveProvider.overrideWithValue(
          KeepAliveCoordinator(_NoKeepAlive(), pauseInBackground: false),
        ),
        mediaPlatformProvider.overrideWithValue(media),
      ],
    );
    addTearDown(c.dispose);
    final ctrl = c.read(sendControllerProvider.notifier);
    ctrl.addMedia([
      LibraryAsset(
        id: 'a',
        kind: FileKind.photo,
        created: DateTime(2026, 11, 3, 14, 5),
      ),
      const LibraryAsset(id: 'v', kind: FileKind.video),
      const LibraryAsset(id: 'n', kind: FileKind.photo),
      const LibraryAsset(id: 'k', kind: FileKind.photo, originalName: 'K.JPG'),
    ]);
    // Before the names arrive: kind and date, never a blank.
    expect(
      c.read(sendControllerProvider).picked.first.label,
      'Photo 2026-11-03 14:05',
    );
    await pumpEventQueue();

    final labels = c.read(sendControllerProvider).picked.map((p) => p.label);
    expect(labels, ['IMG_0001.HEIC', 'IMG_0002.MOV', 'Photo', 'K.JPG']);
    expect(media.asked, [
      ['a', 'v', 'n'],
    ], reason: 'one call, only for picks without a name');
  });

  test('an album keeps its folder through the name lookup (D-079)', () async {
    final media = _NamingMedia({'a': 'IMG_0001.HEIC'});
    final c = ProviderContainer(
      overrides: [
        keepAliveProvider.overrideWithValue(
          KeepAliveCoordinator(_NoKeepAlive(), pauseInBackground: false),
        ),
        mediaPlatformProvider.overrideWithValue(media),
      ],
    );
    addTearDown(c.dispose);
    final ctrl = c.read(sendControllerProvider.notifier);
    const a = LibraryAsset(id: 'a', kind: FileKind.photo);
    ctrl.addMedia(const [a]);
    ctrl.addMedia(const [a], folder: 'Trip');
    ctrl.addMedia(const [a], folder: 'Trip');
    await pumpEventQueue();

    final picked = c.read(sendControllerProvider).picked.cast<PickedAsset>();
    expect(picked.map((p) => (p.label, p.folder)), [
      ('IMG_0001.HEIC', null),
      ('IMG_0001.HEIC', 'Trip'),
    ], reason: 'loose and in the album both go; the same album once');
  });

  group('a whole folder and big selections (D-075)', () {
    test('a folder joins the selection; left-out files are counted', () async {
      final picker = _FolderPicker((
        files: [
          const PickedFile(ref: '/s/1', name: 'a.jpg', folder: 'Trip'),
          const PickedFile(ref: '/s/2', name: 'b.mp4', folder: 'Trip/Day 1'),
        ],
        skipped: 2,
      ));
      final c = ProviderContainer(
        overrides: [
          keepAliveProvider.overrideWithValue(
            KeepAliveCoordinator(_NoKeepAlive(), pauseInBackground: false),
          ),
          documentPickerProvider.overrideWith((ref) async => picker),
        ],
      );
      addTearDown(c.dispose);
      final ctrl = c.read(sendControllerProvider.notifier);
      expect(await ctrl.pickFolder(), 2);
      final picked = c.read(sendControllerProvider).picked.cast<PickedFile>();
      expect(picked.map((f) => f.folder), ['Trip', 'Trip/Day 1']);
    });

    test('removing one folder file keeps the grant of the folder', () async {
      final picker = _FolderPicker((
        files: [
          const PickedFile(ref: '/s/1', name: 'a.jpg', folder: 'Trip'),
          const PickedFile(ref: '/s/2', name: 'b.jpg', folder: 'Trip'),
        ],
        skipped: 0,
      ));
      final c = ProviderContainer(
        overrides: [
          keepAliveProvider.overrideWithValue(
            KeepAliveCoordinator(_NoKeepAlive(), pauseInBackground: false),
          ),
          documentPickerProvider.overrideWith((ref) async => picker),
        ],
      );
      addTearDown(c.dispose);
      final ctrl = c.read(sendControllerProvider.notifier);
      await ctrl.pickFolder();
      await ctrl.removePicked(c.read(sendControllerProvider).picked.first);
      expect(c.read(sendControllerProvider).picked, hasLength(1));
      expect(picker.released, isEmpty);
    });

    test('a folder with long paths is cut to fit the offer (D-076)', () async {
      // 10,000 files in a ~400-character folder: about 5.5 MB of offer,
      // more than a receiver reads.
      final folder = 'Backup/${'Long folder name ' * 24}';
      final picker = _FolderPicker((
        files: [
          for (var i = 0; i < maxFilesPerOffer; i++)
            PickedFile(ref: '/s/$i', name: 'IMG_$i.jpg', folder: folder),
        ],
        skipped: 0,
      ));
      final c = ProviderContainer(
        overrides: [
          keepAliveProvider.overrideWithValue(
            KeepAliveCoordinator(_NoKeepAlive(), pauseInBackground: false),
          ),
          documentPickerProvider.overrideWith((ref) async => picker),
        ],
      );
      addTearDown(c.dispose);
      final ctrl = c.read(sendControllerProvider.notifier);
      final leftOut = await ctrl.pickFolder();
      final picked = c.read(sendControllerProvider).picked.cast<PickedFile>();
      expect(leftOut, greaterThan(0));
      expect(picked.length + leftOut, maxFilesPerOffer);
      // The real offer of what was kept, every optional field filled.
      final json = jsonEncode({
        'protocol': protocolVersion,
        'sender': {'id': 'x' * 64, 'name': 'n' * 100, 'platform': 'android'},
        'files': [
          for (final (i, f) in picked.indexed)
            FileOffer(
              fileId: 'f$i',
              name: f.name,
              size: maxFileBytes,
              mime:
                  'application/vnd.openxmlformats-officedocument'
                  '.wordprocessingml.document',
              created: DateTime.utc(2026),
              livePhotoGroup: 'g' * 36,
              folder: f.folder,
            ).toJson(),
        ],
      });
      expect(utf8.encode(json).length, lessThanOrEqualTo(maxOfferJsonBytes));
    });

    test('one send holds at most maxFilesPerOffer items', () {
      final c = ProviderContainer(
        overrides: [
          keepAliveProvider.overrideWithValue(
            KeepAliveCoordinator(_NoKeepAlive(), pauseInBackground: false),
          ),
        ],
      );
      addTearDown(c.dispose);
      final ctrl = c.read(sendControllerProvider.notifier);
      final dropped = ctrl.addMedia([
        for (var i = 0; i < maxFilesPerOffer + 5; i++)
          LibraryAsset(id: 'a$i', kind: FileKind.photo),
      ]);
      expect(dropped, 5);
      expect(
        c.read(sendControllerProvider).picked,
        hasLength(maxFilesPerOffer),
      );
    });
  });
}

class _NamingMedia implements MediaPlatform {
  _NamingMedia(this.names);
  final Map<String, String> names;
  final List<List<String>> asked = [];

  @override
  Future<List<ResolvedFile>?> planAsset(
    LibraryAsset asset,
    ExportPlan plan,
    String dir,
  ) async => null;

  @override
  Future<Map<String, String>> originalNames(List<String> ids) async {
    asked.add(ids);
    return {
      for (final id in ids)
        if (names.containsKey(id)) id: names[id]!,
    };
  }

  @override
  Future<int> copyIntoStaging(String ref, String dest, PrepareControl c) =>
      throw UnimplementedError();

  @override
  Future<List<ResolvedFile>> resolveAsset(
    LibraryAsset asset,
    ExportPlan plan,
    String dir,
    PrepareControl control,
    void Function(double fraction) onProgress,
  ) => throw UnimplementedError();
}

class _FolderPicker implements DocumentPicker {
  _FolderPicker(this.result);
  final FolderPick result;

  @override
  Future<List<PickedFile>> pick() async => const [];

  final List<PickedFile> released = [];

  @override
  Future<FolderPick> pickFolder() async => result;

  @override
  Future<void> release(List<PickedFile> files) async => released.addAll(files);
}
