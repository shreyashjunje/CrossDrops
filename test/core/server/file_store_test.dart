import 'dart:io';
import 'dart:typed_data';

import 'package:crossdrop/core/client/upload_client.dart';
import 'package:crossdrop/core/media/save_target.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/device_credentials.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:crossdrop/core/server/file_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/test_receiver.dart';

void main() {
  group('FolderStore', () {
    late Directory root;
    late String save;
    setUp(() {
      root = Directory.systemTemp.createTempSync('cd_store');
      save = p.join(root.path, 'save');
    });
    tearDown(() => root.deleteSync(recursive: true));

    FileOffer offer(
      String name, {
      String kind = FileKind.file,
      DateTime? created,
    }) => FileOffer(
      fileId: 'f1',
      name: name,
      size: 3,
      kind: kind,
      created: created,
    );

    Future<String> part(FolderStore s, FileOffer o, List<int> bytes) async {
      final dir = p.join(root.path, 'tmp', 's1');
      final loc = s.initialLocation(dir, o);
      final (pf, at) = await s.open(loc, sessionDir: dir, offer: o);
      expect(at, loc, reason: 'folder parts never move');
      await pf.append(Uint8List.fromList(bytes));
      await pf.sync();
      await pf.close();
      return loc;
    }

    test('length is 0 before the part exists; restore cuts back', () async {
      final s = FolderStore(save, platform: DevicePlatform.android);
      final o = offer('a.bin');
      final dir = p.join(root.path, 'tmp', 's1');
      final loc = s.initialLocation(dir, o);
      expect(await s.length(loc), 0);
      await part(s, o, [1, 2, 3, 4, 5]);
      expect(await s.length(loc), 5);
      expect(await s.restore(loc, 3), 3);
      expect(File(loc).readAsBytesSync(), [1, 2, 3]);
      expect(await s.restore(loc, 10), 3, reason: 'never grows');
      await s.delete(loc);
      await s.delete(loc); // twice is fine
      expect(await s.restore(loc, 3), 0, reason: 'a vanished part is 0');
    });

    test('save sanitizes, avoids clashes and sets the date', () async {
      final s = FolderStore(save, platform: DevicePlatform.android);
      final when = DateTime.utc(2021, 3, 4, 5, 6, 7);
      final o = offer('../x/report?.pdf', created: when);
      final first = await s.save(await part(s, o, [1, 2, 3]), o);
      final second = await s.save(await part(s, o, [4, 5, 6]), o);

      expect(p.basename(first.location), 'report_.pdf');
      expect(p.basename(second.location), 'report_ (1).pdf');
      expect(p.isWithin(save, second.location), isTrue);
      expect(first.collection, SaveCollection.files);
      expect(first.fallback, isNull);
      expect(File(first.location).lastModifiedSync().toUtc(), when);
    });

    test('a photo goes to the gallery saver, which takes the file', () async {
      final saver = _FakeSaver(const GallerySave.saved('photos:ABC'));
      final s = FolderStore(
        save,
        mediaSaver: saver,
        platform: DevicePlatform.ios,
      );
      final o = offer('IMG_1.HEIC', kind: FileKind.photo);
      final r = await s.save(await part(s, o, [1, 2, 3]), o);

      expect(r.location, 'photos:ABC');
      expect(r.collection, SaveCollection.photos);
      expect(saver.calls.single.$2, 'IMG_1.HEIC');
      expect(Directory(save).existsSync(), isFalse, reason: 'not in Files');
    });

    test(
      'a format the gallery refuses is saved to Files with a note',
      () async {
        final saver = _FakeSaver(
          const GallerySave.refused(SaveFallback.unsupported),
        );
        final s = FolderStore(
          save,
          mediaSaver: saver,
          platform: DevicePlatform.ios,
        );
        final o = offer('IMG_1.HEIC', kind: FileKind.photo);
        final r = await s.save(await part(s, o, [1, 2, 3]), o);

        expect(r.collection, SaveCollection.files);
        expect(r.fallback, SaveFallback.unsupported);
        expect(File(r.location).readAsBytesSync(), [1, 2, 3]);
      },
    );

    test('formats iOS Photos never takes skip the saver', () async {
      final saver = _FakeSaver(const GallerySave.saved('photos:X'));
      final s = FolderStore(
        save,
        mediaSaver: saver,
        platform: DevicePlatform.ios,
      );
      final o = offer('clip.webm', kind: FileKind.video);
      final r = await s.save(await part(s, o, [1, 2, 3]), o);
      expect(saver.calls, isEmpty);
      expect(r.collection, SaveCollection.files);
      expect(r.fallback, isNull);
    });

    test('documents never go to the saver', () async {
      final saver = _FakeSaver(const GallerySave.saved('photos:X'));
      final s = FolderStore(
        save,
        mediaSaver: saver,
        platform: DevicePlatform.ios,
      );
      final o = offer('a.zip');
      await s.save(await part(s, o, [1, 2, 3]), o);
      expect(saver.calls, isEmpty);
    });

    test('a full library is StoreFull and the part stays', () async {
      final saver = _FakeSaver(const GallerySave.full());
      final s = FolderStore(
        save,
        mediaSaver: saver,
        platform: DevicePlatform.ios,
      );
      final o = offer('IMG_1.JPG', kind: FileKind.photo);
      final loc = await part(s, o, [1, 2, 3]);
      await expectLater(s.save(loc, o), throwsA(isA<StoreFull>()));
      expect(File(loc).existsSync(), isTrue);
    });
  });

  group('a store whose parts live elsewhere (like MediaStore)', () {
    late DeviceCredentials identity;
    late DeviceCredentials me;
    late Directory src;
    late TestReceiver r;
    late _RelocatingStore store;

    setUpAll(() async {
      identity = await DeviceCredentials.generate();
      me = await testSenderCredentials();
      src = Directory.systemTemp.createTempSync('cd_reloc');
    });
    tearDownAll(() => src.deleteSync(recursive: true));
    setUp(() async {
      r = await TestReceiver.start(
        identity: identity,
        store: (r) => store = _RelocatingStore(p.join(r.root.path, 'media')),
      );
    });
    tearDown(() => r.close());

    test('the new location is stored and the file is saved from it', () async {
      final path = p.join(src.path, 'IMG_1.JPG');
      final sha = await writeRandomFile(path, 3 * mb + 5);
      final client = clientFor(r, me);
      addTearDown(client.close);

      final target = await client.offerFile(path, name: 'IMG_1.JPG');
      expect(await client.transfer(target), sha);

      expect(store.created, hasLength(1));
      final saved = r.saved.single;
      expect(saved.collection, SaveCollection.photos);
      expect(saved.savedPath, startsWith('published:'));
      final stored = (await r.repo.unfinished()).isEmpty
          ? null
          : (await r.repo.unfinished()).first;
      expect(stored, isNull, reason: 'session done');
      expect(store.deleted, isEmpty);
    });

    test('cancel deletes parts outside the session folder', () async {
      final path = p.join(src.path, 'b.bin');
      await writeRandomFile(path, 2 * mb);
      final client = clientFor(r, me);
      addTearDown(client.close);
      final target = await client.offerFile(path, name: 'b.bin');
      // Send part of it, then cancel.
      final part = UploadTarget(
        sessionId: target.sessionId,
        fileId: target.fileId,
        path: path,
        size: target.size,
      );
      try {
        await client.put(
          part,
          0,
          onProgress: (pr) {
            if (pr.sentBytes > mb) client.cancel();
          },
        );
      } on UploadException {
        // Cancelled on purpose.
      }
      await client.cancelSession(target.sessionId);
      await waitFor(() => store.deleted.isNotEmpty);
      expect(store.deleted.single, store.created.single);
      expect(File(store.created.single).existsSync(), isFalse);
    });

    test('restart restores from the stored location', () async {
      final path = p.join(src.path, 'c.bin');
      final sha = await writeRandomFile(path, 9 * mb);
      final client = clientFor(r, me);
      addTearDown(client.close);
      final target = await client.offerFile(path, name: 'c.bin');
      try {
        await client.put(
          target,
          0,
          onProgress: (pr) {
            if (pr.sentBytes > 5 * mb) client.cancel();
          },
        );
      } on UploadException {
        // Interrupted on purpose.
      }
      await waitFor(
        () => r.server.sessions.single.status == SessionStatus.paused,
      );
      final stored = (await r.repo.unfinished()).first.files.first;
      expect(stored.tempPath, store.created.single);

      await r.restart();
      final fresh = clientFor(r, me);
      addTearDown(fresh.close);
      final status = await fresh.fileStatus(target);
      expect(status.receivedBytes, stored.transferredBytes);
      expect(status.receivedBytes, greaterThan(0));
      expect(await fresh.transfer(target), sha);
      expect(r.saved.single.savedPath, startsWith('published:'));
    });
  });
}

class _FakeSaver implements MediaSaver {
  _FakeSaver(this.answer);
  final GallerySave answer;
  final List<(String, String)> calls = [];

  @override
  Future<GallerySave> saveToGallery(
    String path, {
    required String safeName,
    required String kind,
    DateTime? created,
  }) async {
    calls.add((path, safeName));
    if (answer.savedAs != null) await File(path).delete();
    return answer;
  }
}

/// Parts are created on first open in [mediaDir], with a new location,
/// as Android's pending MediaStore items are.
class _RelocatingStore implements ReceivedFileStore {
  _RelocatingStore(this.mediaDir);
  final String mediaDir;
  final _folder = FolderStore('unused', platform: DevicePlatform.android);
  final List<String> created = [];
  final List<String> deleted = [];

  static const _placeholder = 'pending:';

  @override
  String initialLocation(String sessionDir, FileOffer offer) =>
      '$_placeholder${offer.fileId}';

  @override
  Future<(PartFile, String)> open(
    String location, {
    required String sessionDir,
    required FileOffer offer,
  }) async {
    var loc = location;
    if (loc.startsWith(_placeholder)) {
      loc = p.join(mediaDir, '${created.length}-${offer.fileId}.bin');
      created.add(loc);
    }
    final (part, _) = await _folder.open(loc, sessionDir: '', offer: offer);
    return (part, loc);
  }

  @override
  Future<int> length(String location) => location.startsWith(_placeholder)
      ? Future.value(0)
      : _folder.length(location);

  @override
  Future<int> restore(String location, int checkpoint) =>
      location.startsWith(_placeholder)
      ? Future.value(0)
      : _folder.restore(location, checkpoint);

  @override
  Future<void> delete(String location) async {
    if (location.startsWith(_placeholder)) return;
    deleted.add(location);
    await _folder.delete(location);
  }

  @override
  Future<SaveResult> save(String location, FileOffer offer) async => SaveResult(
    location: 'published:${p.basename(location)}',
    collection: SaveCollection.photos,
  );
}
