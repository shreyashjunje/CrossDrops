import 'dart:async';

import 'package:crossdrop/app/keep_alive.dart';
import 'package:crossdrop/app/media_providers.dart';
import 'package:crossdrop/app/providers.dart';
import 'package:crossdrop/core/client/peer_check.dart';
import 'package:crossdrop/core/media/format_plan.dart';
import 'package:crossdrop/core/media/prepare.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/features/nearby/nearby_controller.dart';
import 'package:crossdrop/features/send/send_controller.dart';
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
}

class _NamingMedia implements MediaPlatform {
  _NamingMedia(this.names);
  final Map<String, String> names;
  final List<List<String>> asked = [];

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
