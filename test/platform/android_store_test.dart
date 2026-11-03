import 'dart:io';

import 'package:crossdrop/core/client/upload_client.dart';
import 'package:crossdrop/core/engine/chunked_reader.dart';
import 'package:crossdrop/core/media/save_target.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/device_credentials.dart';
import 'package:crossdrop/core/server/file_store.dart';
import 'package:crossdrop/platform/android_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/test_receiver.dart';

void main() {
  late DeviceCredentials identity;
  late DeviceCredentials me;
  late Directory src;
  late TestReceiver r;
  late _FakeMediaStore api;

  setUpAll(() async {
    identity = await DeviceCredentials.generate();
    me = await testSenderCredentials();
    src = Directory.systemTemp.createTempSync('cd_ms_src');
  });
  tearDownAll(() => src.deleteSync(recursive: true));

  setUp(() async {
    r = await TestReceiver.start(
      identity: identity,
      store: (r) {
        api = _FakeMediaStore(p.join(r.root.path, 'media'));
        return MediaStoreFileStore(api, partForFd: api.part);
      },
    );
  });
  tearDown(() => r.close());

  Future<(UploadTarget, String, UploadClient)> offer(
    String name,
    int size, {
    String kind = FileKind.photo,
    DateTime? created,
  }) async {
    final path = p.join(src.path, name);
    final sha = await writeRandomFile(path, size);
    final client = clientFor(r, me);
    addTearDown(client.close);
    final created0 = await client.offer(
      SessionOffer(
        sender: testSender,
        files: [
          FileOffer(
            fileId: 'f1',
            name: name,
            size: size,
            kind: kind,
            created: created,
          ),
        ],
      ),
    );
    await waitFor(
      () => r.server.sessions.single.status != SessionStatus.offered,
    );
    return (
      UploadTarget(
        sessionId: created0.sessionId,
        fileId: 'f1',
        path: path,
        size: size,
      ),
      sha,
      client,
    );
  }

  test('a photo is written into a pending item, then published', () async {
    final when = DateTime.utc(2024, 6, 1, 12);
    final (t, sha, client) = await offer(
      'IMG_1.HEIC',
      2 * mb + 3,
      created: when,
    );
    expect(await client.transfer(t), sha);

    final item = api.items.single;
    expect(item.collection, SaveCollection.photos);
    expect(item.mime, 'image/heic');
    expect(item.taken, when);
    expect(item.published, isTrue);
    expect(await hashFile(item.path), sha);
    expect(File(item.path).lastModifiedSync().toUtc(), when);
    final saved = r.saved.single;
    expect(saved.savedPath, item.uri);
    expect(saved.collection, SaveCollection.photos);
    expect(saved.fallback, isNull);
    // No copy was made anywhere else.
    expect(Directory(r.saveDir).existsSync(), isFalse);
  });

  test('documents go to Downloads, videos to Movies', () async {
    var (t, sha, client) = await offer('a.pdf', 10, kind: FileKind.file);
    await client.transfer(t);
    expect(api.items.last.collection, SaveCollection.files);
    expect(api.items.last.mime, 'application/pdf');

    await r.restart();
    (t, sha, client) = await offer('clip.mp4', 10, kind: FileKind.video);
    await client.transfer(t);
    expect(api.items.last.collection, SaveCollection.videos);
    expect(sha, isNotEmpty);
  });

  test(
    'a MIME type the gallery refuses goes to Downloads, with a note',
    () async {
      api.refuse.add(SaveCollection.photos);
      final (t, sha, client) = await offer('IMG_2.HEIC', 100);
      expect(await client.transfer(t), sha);

      expect(api.items.single.collection, SaveCollection.files);
      expect(r.saved.single.collection, SaveCollection.files);
      expect(r.saved.single.fallback, SaveFallback.unsupported);
    },
  );

  test(
    'storage full at create is a 507 no_space and the session pauses',
    () async {
      api.full = true;
      final (t, _, client) = await offer('IMG_3.JPG', 100);
      await expectLater(
        client.transfer(t),
        throwsA(
          isA<UploadException>().having(
            (e) => e.code,
            'code',
            ErrorCodes.noSpace,
          ),
        ),
      );
      expect(r.server.sessions.single.status, SessionStatus.paused);
      expect(api.items, isEmpty);
    },
  );

  test('cancel deletes the pending item', () async {
    final (t, _, client) = await offer('big.mov', 6 * mb, kind: FileKind.video);
    try {
      await client.put(
        t,
        0,
        onProgress: (pr) {
          if (pr.sentBytes > 2 * mb) client.cancel();
        },
      );
    } on UploadException {
      // Cancelled on purpose.
    }
    await waitFor(() => api.items.isNotEmpty);
    await client.cancelSession(t.sessionId);
    await waitFor(() => api.items.single.deleted);
    expect(File(api.items.single.path).existsSync(), isFalse);
  });

  test('a pending item removed while the app was closed starts over', () async {
    final (t, sha, client) = await offer('IMG_4.JPG', 9 * mb);
    try {
      await client.put(
        t,
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
    // The system or the user deleted it.
    api.items.single.deleted = true;
    File(api.items.single.path).deleteSync();

    await r.restart();
    final fresh = clientFor(r, me);
    addTearDown(fresh.close);
    expect((await fresh.fileStatus(t)).receivedBytes, 0);
    expect(await fresh.transfer(t), sha);
    expect(api.items, hasLength(2));
    expect(api.items.last.published, isTrue);
  });

  test('cleanupOrphans keeps items in use', () async {
    final store = MediaStoreFileStore(api, partForFd: api.part);
    final now = DateTime.utc(2026, 11, 3);
    await store.cleanupOrphans({'content://a'}, now: now);
    expect(api.cleanupCalls.single.$1, now.subtract(const Duration(hours: 24)));
    expect(api.cleanupCalls.single.$2, {'content://a'});
  });
}

class _Item {
  _Item(this.uri, this.path, this.collection, this.mime, this.taken);
  final String uri;
  final String path;
  final SaveCollection collection;
  final String mime;
  final DateTime? taken;
  bool published = false;
  bool deleted = false;
}

class _FakeMediaStore implements MediaStoreApi {
  _FakeMediaStore(this.dir) {
    Directory(dir).createSync(recursive: true);
  }

  final String dir;
  final List<_Item> items = [];
  final Set<SaveCollection> refuse = {};
  final List<(DateTime, Set<String>)> cleanupCalls = [];
  bool full = false;
  final Map<int, String> _fds = {};
  int _nextFd = 100;

  _Item _find(String uri) => items.firstWhere((i) => i.uri == uri);

  int _fdFor(String path) {
    final fd = _nextFd++;
    _fds[fd] = path;
    return fd;
  }

  PartFile part(int fd) => _FilePart(_fds[fd]!);

  @override
  Future<({String uri, int fd})> create({
    required String name,
    required String mime,
    required SaveCollection collection,
    DateTime? taken,
  }) async {
    if (full) throw PlatformException(code: 'no_space');
    if (refuse.contains(collection)) {
      throw PlatformException(code: 'unsupported');
    }
    final uri =
        'content://media/external_primary/${collection.name}/${items.length}';
    final path = p.join(dir, '${items.length}-$name');
    File(path).createSync();
    items.add(_Item(uri, path, collection, mime, taken));
    return (uri: uri, fd: _fdFor(path));
  }

  @override
  Future<int> open(String uri) async {
    final item = items.where((i) => i.uri == uri && !i.deleted).firstOrNull;
    if (item == null) throw PlatformException(code: 'not_found');
    return _fdFor(item.path);
  }

  @override
  Future<String?> publish(String uri) async {
    _find(uri).published = true;
    return p.basename(_find(uri).path);
  }

  @override
  Future<void> delete(String uri) async {
    final item = _find(uri);
    item.deleted = true;
    if (File(item.path).existsSync()) File(item.path).deleteSync();
  }

  @override
  Future<int> cleanupPending(DateTime olderThan, Set<String> keep) async {
    cleanupCalls.add((olderThan, keep));
    return 0;
  }
}

class _FilePart implements PartFile {
  _FilePart(this.path) : _raf = File(path).openSync(mode: FileMode.append);
  final String path;
  final RandomAccessFile _raf;

  @override
  Future<int> length() => _raf.length();
  @override
  Future<void> append(Uint8List bytes) => _raf.writeFrom(bytes);
  @override
  Future<void> sync() => _raf.flush();
  @override
  Future<void> truncate(int length) => _raf.truncate(length);
  @override
  Future<void> setModified(DateTime time) => File(path).setLastModified(time);
  @override
  ByteSource get source => PathSource(path);
  @override
  Future<void> close() => _raf.close();
}
