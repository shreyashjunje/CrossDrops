import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../engine/chunked_reader.dart';
import '../engine/sha256_isolate.dart';
import '../protocol/models.dart';
import '../storage/file_name_sanitizer.dart';

/// Events for the UI. They carry ids and sizes, never file contents.
sealed class ReceiveEvent {
  const ReceiveEvent(this.sessionId);
  final String sessionId;
}

class SessionStarted extends ReceiveEvent {
  const SessionStarted(super.sessionId, this.files);
  final List<FileOffer> files;
}

class FileProgress extends ReceiveEvent {
  const FileProgress(
    super.sessionId,
    this.fileId,
    this.receivedBytes,
    this.size,
  );
  final String fileId;
  final int receivedBytes;
  final int size;
}

class FileSaved extends ReceiveEvent {
  const FileSaved(super.sessionId, this.fileId, this.savedPath, this.size);
  final String fileId;
  final String savedPath;
  final int size;
}

class FileFailed extends ReceiveEvent {
  const FileFailed(super.sessionId, this.fileId, this.code);
  final String fileId;
  final String code;
}

class _ReceivingFile {
  _ReceivingFile(this.offer, this.partPath);

  final FileOffer offer;
  final String partPath;
  bool busy = false;
  String? savedPath;

  /// Digest of the whole file, set when a PUT ends exactly at [FileOffer.size].
  String? digest;
}

class _Session {
  _Session(this.id, this.dir, this.files);
  final String id;
  final String dir;
  final Map<String, _ReceivingFile> files;
}

/// The receiver's HTTPS server (protocol v1, Phase 1 subset).
///
/// Phase 1 limits: offers are accepted automatically (no Accept prompt, no
/// WebSocket events), no client certificate is required, no free-space
/// check, and sessions live only in memory.
class ReceiveServer {
  ReceiveServer._(this._tempDir, this._saveDir, this._bodyIdleTimeout);

  final String _tempDir;
  final String _saveDir;
  final Duration _bodyIdleTimeout;
  final Map<String, _Session> _sessions = {};
  final StreamController<ReceiveEvent> _events = StreamController.broadcast();
  late final HttpServer _server;

  static const int _maxJsonBytes = 1024 * 1024;

  /// Starts listening on [port] (0 = random, as ARCHITECTURE.md asks).
  ///
  /// Partial files go to `<tempDir>/<sessionId>/<fileId>.part`; verified
  /// files are moved into [saveDir].
  static Future<ReceiveServer> start({
    required SecurityContext securityContext,
    required String tempDir,
    required String saveDir,
    Object? address,
    int port = 0,
    Duration bodyIdleTimeout = const Duration(seconds: 15),
  }) async {
    final server = ReceiveServer._(tempDir, saveDir, bodyIdleTimeout);
    await Directory(tempDir).create(recursive: true);
    await Directory(saveDir).create(recursive: true);
    server._server = await shelf_io.serve(
      server._router().call,
      address ?? InternetAddress.anyIPv4,
      port,
      securityContext: securityContext,
    );
    _log('listening on port ${server.port}');
    return server;
  }

  int get port => _server.port;

  Stream<ReceiveEvent> get events => _events.stream;

  Future<void> close() async {
    await _server.close(force: true);
    await _events.close();
  }

  Router _router() => Router(notFoundHandler: (_) => _notFound())
    ..post('/v1/sessions', _createSession)
    ..get('/v1/sessions/<sid>/files/<fid>', _getFile)
    ..put('/v1/sessions/<sid>/files/<fid>', _putFile)
    ..post('/v1/sessions/<sid>/files/<fid>/complete', _complete);

  Future<Response> _createSession(Request req) async {
    final SessionOffer offer;
    try {
      offer = SessionOffer.fromJson(await _readJson(req));
    } on FormatError catch (e) {
      return _error(400, ErrorCodes.badRequest, e.message);
    }
    if (offer.protocol != protocolVersion) {
      return _error(400, ErrorCodes.badRequest, 'unsupported protocol');
    }
    // TODO(phase2): free-space check and Accept prompt before accepting.
    final id = _randomId();
    final dir = p.join(_tempDir, id);
    await Directory(dir).create(recursive: true);
    final files = <String, _ReceivingFile>{};
    for (final f in offer.files) {
      final part = p.join(dir, '${f.fileId}.part');
      await File(part).create();
      files[f.fileId] = _ReceivingFile(f, part);
    }
    _sessions[id] = _Session(id, dir, files);
    _log('session $id: ${offer.files.length} file(s)');
    _events.add(SessionStarted(id, offer.files));
    return _json(200, SessionCreated(sessionId: id, status: 'accepted'));
  }

  Future<Response> _getFile(Request req, String sid, String fid) async {
    final f = _lookup(sid, fid);
    if (f == null) return _notFound();
    return _json(200, await _status(f));
  }

  Future<Response> _putFile(Request req, String sid, String fid) async {
    final f = _lookup(sid, fid);
    if (f == null) return _notFound();
    if (f.savedPath != null) {
      return _error(409, ErrorCodes.alreadySaved, 'file already saved');
    }
    final offset = int.tryParse(req.url.queryParameters['offset'] ?? '');
    if (offset == null || offset < 0) {
      return _error(400, ErrorCodes.badRequest, 'missing or bad offset');
    }
    if (f.busy) {
      return _error(409, ErrorCodes.busy, 'another upload is in progress');
    }
    f.busy = true;
    try {
      return await _receive(req, sid, f, offset);
    } finally {
      f.busy = false;
    }
  }

  Future<Response> _receive(
    Request req,
    String sid,
    _ReceivingFile f,
    int offset,
  ) async {
    final size = f.offer.size;
    final part = File(f.partPath);
    final received = await part.length();
    if (offset != received) {
      return _error(
        409,
        ErrorCodes.offsetMismatch,
        'offset must equal receivedBytes',
        {'receivedBytes': received},
      );
    }
    final declared = req.contentLength;
    if (declared != null && offset + declared > size) {
      return _error(413, ErrorCodes.tooManyBytes, 'body exceeds declared size');
    }

    f.digest = null;
    final hasher = await Sha256Isolate.spawn();
    final raf = await part.open(mode: FileMode.append);
    var written = offset;
    var overflow = false;
    Object? interruption;
    final buffer = BytesBuilder(copy: false);

    Future<void> flush() async {
      if (buffer.isEmpty) return;
      final bytes = buffer.takeBytes();
      await raf.writeFrom(bytes);
      await hasher.add(bytes);
      written += bytes.length;
      _events.add(FileProgress(sid, f.offer.fileId, written, size));
    }

    try {
      try {
        await hasher.addFilePrefix(f.partPath, offset);
        await for (final chunk in req.read().timeout(_bodyIdleTimeout)) {
          // Never trust the declared size (CLAUDE.md hard rule 6).
          if (written + buffer.length + chunk.length > size) {
            overflow = true;
            break;
          }
          buffer.add(chunk);
          if (buffer.length >= defaultChunkSize) await flush();
        }
      } on Exception catch (e) {
        // Client went away or stalled. Keep every byte that arrived.
        interruption = e;
      }
      if (overflow) {
        await raf.truncate(offset);
        hasher.abort();
        _log('file ${f.offer.fileId}: too many bytes, discarded this upload');
        return _error(
          413,
          ErrorCodes.tooManyBytes,
          'body exceeds declared size',
        );
      }
      await flush();
      await raf.flush();
    } finally {
      await raf.close();
    }

    if (interruption != null) {
      hasher.abort();
      _log('file ${f.offer.fileId}: interrupted at $written bytes');
      // The client usually never sees this response.
      return _error(400, ErrorCodes.incomplete, 'upload interrupted', {
        'receivedBytes': written,
      });
    }
    if (written == size) {
      f.digest = await hasher.close();
    } else {
      hasher.abort();
    }
    return _json(200, await _status(f));
  }

  Future<Response> _complete(Request req, String sid, String fid) async {
    final f = _lookup(sid, fid);
    if (f == null) return _notFound();
    if (f.savedPath != null) {
      return _error(409, ErrorCodes.alreadySaved, 'file already saved');
    }
    if (f.busy) {
      return _error(409, ErrorCodes.busy, 'upload still in progress');
    }
    final CompleteRequest body;
    try {
      body = CompleteRequest.fromJson(await _readJson(req));
    } on FormatError catch (e) {
      return _error(400, ErrorCodes.badRequest, e.message);
    }
    f.busy = true;
    try {
      final size = f.offer.size;
      final received = await File(f.partPath).length();
      if (received != size) {
        return _error(409, ErrorCodes.incomplete, 'file not fully received', {
          'receivedBytes': received,
        });
      }
      final digest = f.digest ?? await _hashFile(f.partPath, size);
      if (digest != body.sha256) {
        // Restart from zero (ARCHITECTURE.md transfer rule 6).
        await File(f.partPath).writeAsBytes(const []);
        f.digest = null;
        _log('file ${f.offer.fileId}: hash mismatch, partial file reset');
        _events.add(FileFailed(sid, fid, ErrorCodes.hashMismatch));
        return _error(422, ErrorCodes.hashMismatch, 'SHA-256 does not match');
      }
      final dest = availablePath(_saveDir, sanitizeFileName(f.offer.name));
      try {
        await _move(f.partPath, dest);
      } on FileSystemException {
        _events.add(FileFailed(sid, fid, ErrorCodes.ioError));
        return _error(500, ErrorCodes.ioError, 'could not save file');
      }
      f.savedPath = dest;
      _log('file ${f.offer.fileId}: verified and saved ($size bytes)');
      _events.add(FileSaved(sid, fid, dest, size));
      return _json(200, await _status(f));
    } finally {
      f.busy = false;
    }
  }

  _ReceivingFile? _lookup(String sid, String fid) => _sessions[sid]?.files[fid];

  Future<FileStatus> _status(_ReceivingFile f) async {
    final saved = f.savedPath != null;
    return FileStatus(
      fileId: f.offer.fileId,
      size: f.offer.size,
      receivedBytes: saved ? f.offer.size : await File(f.partPath).length(),
      status: saved ? 'saved' : 'receiving',
    );
  }

  static Future<String> _hashFile(String path, int length) async {
    final hasher = await Sha256Isolate.spawn();
    await hasher.addFilePrefix(path, length);
    return hasher.close();
  }

  static Future<void> _move(String from, String to) async {
    try {
      await File(from).rename(to);
    } on FileSystemException {
      // Different volume: copy (streamed by the OS), then delete.
      await File(from).copy(to);
      await File(from).delete();
    }
  }

  static Future<Object?> _readJson(Request req) async {
    final declared = req.contentLength;
    if (declared != null && declared > _maxJsonBytes) {
      throw FormatError('body too large');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in req.read()) {
      bytes.add(chunk);
      if (bytes.length > _maxJsonBytes) throw FormatError('body too large');
    }
    try {
      return jsonDecode(utf8.decode(bytes.takeBytes()));
    } on FormatException {
      throw FormatError('invalid JSON');
    }
  }

  static String _randomId() {
    final rnd = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  static Response _json(int status, Object body) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );

  static Response _error(
    int status,
    String code,
    String message, [
    Map<String, Object?> extra = const {},
  ]) => _json(status, {'error': code, 'message': message, ...extra});

  static Response _notFound() =>
      _error(404, ErrorCodes.notFound, 'unknown session, file or route');

  static void _log(String message) =>
      developer.log(message, name: 'crossdrop.server');
}
