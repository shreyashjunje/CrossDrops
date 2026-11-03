import 'dart:io';

import 'package:flutter/services.dart';

import '../core/engine/chunked_reader.dart';
import '../core/engine/fd_file.dart';
import '../core/log.dart';
import '../core/media/save_target.dart';
import '../core/protocol/file_type.dart';
import '../core/protocol/models.dart';
import '../core/security/device_identity.dart';
import '../core/server/file_store.dart';
import '../core/storage/file_name_sanitizer.dart';

/// The MediaStore calls the store needs (android/.../SaveChannel.kt).
abstract interface class MediaStoreApi {
  /// A new pending item; throws [PlatformException] `unsupported` when the
  /// collection refuses the MIME type, `no_space` when storage is full.
  Future<({String uri, int fd})> create({
    required String name,
    required String mime,
    required SaveCollection collection,
    DateTime? taken,
  });

  /// A read-write descriptor; `not_found` if the item is gone.
  Future<int> open(String uri);

  /// Makes the item visible; returns its final display name.
  Future<String?> publish(String uri);

  Future<void> delete(String uri);

  /// Deletes this app's pending items older than [olderThan] that are not
  /// in [keep]; returns how many.
  Future<int> cleanupPending(DateTime olderThan, Set<String> keep);
}

class ChannelMediaStore implements MediaStoreApi {
  ChannelMediaStore([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('crossdrop/save');

  final MethodChannel _channel;

  @override
  Future<({String uri, int fd})> create({
    required String name,
    required String mime,
    required SaveCollection collection,
    DateTime? taken,
  }) async {
    final m = (await _channel.invokeMapMethod<String, Object?>('create', {
      'name': name,
      'mime': mime,
      'collection': collection.name,
      'takenMs': taken?.millisecondsSinceEpoch,
    }))!;
    return (uri: m['uri']! as String, fd: (m['fd']! as num).toInt());
  }

  @override
  Future<int> open(String uri) async =>
      (await _channel.invokeMethod<num>('open', {'uri': uri}))!.toInt();

  @override
  Future<String?> publish(String uri) =>
      _channel.invokeMethod<String>('publish', {'uri': uri});

  @override
  Future<void> delete(String uri) =>
      _channel.invokeMethod<void>('delete', {'uri': uri});

  @override
  Future<int> cleanupPending(DateTime olderThan, Set<String> keep) async =>
      (await _channel.invokeMethod<num>('cleanupPending', {
        'olderThanMs': olderThan.millisecondsSinceEpoch,
        'keep': keep.toList(),
      }))?.toInt() ??
      0;
}

/// Android: each received file is written straight into a pending
/// MediaStore item, which is published once verified (D-040). No
/// temporary copy, so a 4 GB video needs 4 GB, not 8.
///
/// Photos go to Pictures/CrossDrop, videos to Movies/CrossDrop, the rest
/// to Download/CrossDrop ([saveCollectionFor]). A MIME type the gallery
/// refuses goes to Downloads and the save says so.
///
/// A file's location is the folder path [initialLocation] until its first
/// byte, then the item's content URI.
class MediaStoreFileStore implements ReceivedFileStore {
  MediaStoreFileStore(this._api, {PartFile Function(int fd)? partForFd})
    : _partForFd = partForFd ?? FdPart.new;

  final MediaStoreApi _api;
  final PartFile Function(int fd) _partForFd;

  /// Items created in Downloads because the gallery refused them; for the
  /// note in [SaveResult]. Lost on restart, which only loses the note.
  final Set<String> _refused = {};

  static bool _isItem(String location) => location.startsWith('content://');

  @override
  String initialLocation(String sessionDir, FileOffer offer) =>
      '$sessionDir${Platform.pathSeparator}${offer.fileId}.part';

  @override
  Future<(PartFile, String)> open(
    String location, {
    required String sessionDir,
    required FileOffer offer,
  }) async {
    if (_isItem(location)) {
      try {
        return (_partForFd(await _api.open(location)), location);
      } on PlatformException catch (e) {
        if (e.code != 'not_found') throw _fsError(e.code);
        // Removed by the user or the system: start the file again.
        logEvent('store', 'file ${offer.fileId}: pending item gone');
      }
    }
    final safeName = sanitizeFileName(offer.name);
    final collection = saveCollectionFor(
      safeName: safeName,
      declaredKind: offer.kind,
      platform: DevicePlatform.android,
    );
    final mime = mimeForName(safeName) ?? 'application/octet-stream';
    ({String uri, int fd}) item;
    try {
      item = await _api.create(
        name: safeName,
        mime: mime,
        collection: collection,
        taken: offer.created,
      );
    } on PlatformException catch (e) {
      if (e.code != 'unsupported' || collection == SaveCollection.files) {
        throw _fsError(e.code);
      }
      try {
        item = await _api.create(
          name: safeName,
          mime: mime,
          collection: SaveCollection.files,
        );
      } on PlatformException catch (e) {
        throw _fsError(e.code);
      }
      _refused.add(item.uri);
    }
    return (_partForFd(item.fd), item.uri);
  }

  @override
  Future<int> length(String location) async {
    if (!_isItem(location)) return 0;
    final PartFile part;
    try {
      part = _partForFd(await _api.open(location));
    } on PlatformException {
      return 0;
    }
    try {
      return await part.length();
    } finally {
      await part.close();
    }
  }

  @override
  Future<int> restore(String location, int checkpoint) async {
    if (!_isItem(location)) return 0;
    final PartFile part;
    try {
      part = _partForFd(await _api.open(location));
    } on PlatformException {
      return 0;
    }
    try {
      final length = await part.length();
      final keep = length < checkpoint ? length : checkpoint;
      if (keep != length) {
        await part.truncate(keep);
        await part.sync();
      }
      return keep;
    } finally {
      await part.close();
    }
  }

  @override
  Future<void> delete(String location) async {
    if (!_isItem(location)) return;
    _refused.remove(location);
    try {
      await _api.delete(location);
    } on PlatformException {
      // Gone already.
    }
  }

  @override
  Future<SaveResult> save(String location, FileOffer offer) async {
    if (!_isItem(location)) {
      // Never written: only an empty file gets here, and open() created it.
      throw const FileSystemException('nothing to save');
    }
    final created = offer.created;
    if (created != null) {
      // The scanner reads the file's mtime into DATE_MODIFIED on publish;
      // DATE_TAKEN was set at create. Best effort (D-042).
      try {
        final part = _partForFd(await _api.open(location));
        try {
          await part.setModified(created);
        } finally {
          await part.close();
        }
      } on Object catch (e) {
        logEvent(
          'store',
          'file ${offer.fileId}: date not set (${e.runtimeType})',
        );
      }
    }
    try {
      await _api.publish(location);
    } on PlatformException catch (e) {
      if (e.code == 'no_space') throw const StoreFull();
      throw _fsError(e.code);
    }
    final refused = _refused.remove(location);
    final collection = refused
        ? SaveCollection.files
        : saveCollectionFor(
            safeName: sanitizeFileName(offer.name),
            declaredKind: offer.kind,
            platform: DevicePlatform.android,
          );
    return SaveResult(
      location: location,
      collection: collection,
      fallback: refused ? SaveFallback.unsupported : null,
    );
  }

  /// Deletes pending items older than [maxAge] that no session uses:
  /// left by a crash between creating an item and storing its URI.
  Future<int> cleanupOrphans(
    Set<String> inUse, {
    Duration maxAge = const Duration(hours: 24),
    DateTime? now,
  }) => _api.cleanupPending((now ?? DateTime.now()).subtract(maxAge), inUse);

  static FileSystemException _fsError(String code) => FileSystemException(
    'MediaStore: $code',
    '',
    OSError(code, code == 'no_space' ? 28 : 5),
  );
}

/// A partial file reached through a MediaStore descriptor. Writes go
/// through the [FdWorker] isolate.
class FdPart implements PartFile {
  FdPart(this.fd);

  final int fd;
  int? _end;

  Future<FdWorker> get _io => FdWorker.instance;

  @override
  Future<int> length() async => (await _io).length(fd);

  @override
  Future<void> append(Uint8List bytes) async {
    final io = await _io;
    final at = _end ??= await io.length(fd);
    await io.writeAt(fd, at, bytes);
    _end = at + bytes.length;
  }

  @override
  Future<void> sync() async => (await _io).sync(fd);

  @override
  Future<void> truncate(int length) async {
    await (await _io).truncate(fd, length);
    _end = length;
  }

  @override
  Future<void> setModified(DateTime time) async =>
      (await _io).setModified(fd, time);

  @override
  ByteSource get source => FdSource(fd);

  @override
  Future<void> close() async => (await _io).close(fd);
}
