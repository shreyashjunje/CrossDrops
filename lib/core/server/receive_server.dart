import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';

import '../engine/chunked_reader.dart';
import '../engine/session_state_machine.dart';
import '../engine/sha256_isolate.dart';
import '../log.dart';
import '../protocol/events.dart';
import '../protocol/models.dart';
import '../storage/file_name_sanitizer.dart';
import '../storage/transfer_repository.dart';

/// Events for the UI. They carry ids and sizes, never file contents.
sealed class ReceiveEvent {
  const ReceiveEvent(this.sessionId);
  final String sessionId;
}

/// A new offer is waiting for the Accept prompt.
class SessionOffered extends ReceiveEvent {
  const SessionOffered(super.sessionId, this.sender, this.files);
  final SenderInfo sender;
  final List<FileOffer> files;
}

/// An offer was refused before it reached the prompt (no space, sender
/// busy), so the user knows something was attempted.
class OfferRefused extends ReceiveEvent {
  const OfferRefused(this.sender, this.reason, {this.neededBytes}) : super('');
  final SenderInfo sender;
  final String reason;
  final int? neededBytes;
}

class SessionStateChanged extends ReceiveEvent {
  const SessionStateChanged(super.sessionId, this.status, [this.reason]);
  final SessionStatus status;
  final String? reason;
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

/// An offer the user is asked to accept.
class IncomingOffer {
  const IncomingOffer({
    required this.sessionId,
    required this.sender,
    required this.files,
  });

  final String sessionId;
  final SenderInfo sender;
  final List<FileOffer> files;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);
}

/// Shows the Accept prompt; completes with true to accept. The server
/// rejects with `timeout` if it takes longer than its accept timeout.
typedef OfferDecider = Future<bool> Function(IncomingOffer offer);

/// Free bytes on the volume holding [path], or null if unknown.
typedef FreeSpaceProbe = Future<int?> Function(String path);

/// Read-only view of a session for the UI.
class ReceiveSessionSnapshot {
  const ReceiveSessionSnapshot({
    required this.sessionId,
    required this.sender,
    required this.status,
    required this.files,
    this.reason,
  });

  final String sessionId;
  final SenderInfo sender;
  final SessionStatus status;
  final String? reason;
  final List<ReceiveFileSnapshot> files;
}

class ReceiveFileSnapshot {
  const ReceiveFileSnapshot({
    required this.offer,
    required this.status,
    required this.receivedBytes,
    this.savedPath,
    this.errorCode,
  });

  final FileOffer offer;
  final FileTransferStatus status;
  final int receivedBytes;
  final String? savedPath;
  final String? errorCode;
}

class _ReceivingFile {
  _ReceivingFile(
    this.offer,
    this.partPath, {
    this.status = FileTransferStatus.pending,
    this.received = 0,
    this.hashAttempts = 0,
    this.savedPath,
    this.errorCode,
  });

  final FileOffer offer;
  final String partPath;
  FileTransferStatus status;

  /// Bytes on disk in the `.part` file.
  int received;
  int hashAttempts;
  String? savedPath;
  String? errorCode;

  /// Digest of the whole file, set when a PUT ends exactly at the size.
  String? digest;

  /// Incremental hash of bytes [0, hashedBytes) of the part file, kept
  /// across uploads so a resume after a drop costs nothing.
  Sha256Isolate? hasher;
  int hashedBytes = 0;

  void dropHasher() {
    hasher?.abort();
    hasher = null;
    hashedBytes = 0;
  }

  Completer<void>? _busy;

  /// Set by [ReceiveServer.checkpointAll]; the running upload completes it
  /// after saving progress.
  Completer<void>? checkpointRequest;

  bool get busy => _busy != null;

  void lock() => _busy = Completer<void>();

  void unlock() {
    _busy?.complete();
    _busy = null;
  }

  Future<void> get idle => _busy?.future ?? Future<void>.value();
}

class _EventSocket {
  _EventSocket(this.send, this.close);
  final void Function(String text) send;
  final Future<void> Function() close;
}

class _Session {
  _Session({
    required this.id,
    required this.rowId,
    required this.dir,
    required this.sender,
    required this.files,
    required this.machine,
  });

  final String id;
  final int rowId;
  final String dir;
  final SenderInfo sender;

  /// In manifest order.
  final Map<String, _ReceivingFile> files;
  final SessionStateMachine machine;
  String? reason;
  final Set<_EventSocket> sockets = {};
  Timer? acceptTimer;

  SessionStatus get status => machine.state;

  int get remainingBytes => files.values
      .where((f) => !f.status.isTerminal)
      .fold(0, (sum, f) => sum + f.offer.size - f.received);
}

/// The receiver's HTTPS server, protocol v1 (ARCHITECTURE.md, "Protocol
/// spec").
///
/// Every offer waits for [OfferDecider] (the Accept prompt). Sessions and
/// received byte counts are stored in the database, so a session survives
/// an app restart and the sender can resume it.
///
/// Phase 3 limits: no client certificate is required yet (Phase 4), so the
/// sender id in an offer is not proven.
class ReceiveServer {
  ReceiveServer._(
    this._info,
    this._tempDir,
    this._saveDir,
    this._repo,
    this._decider,
    this._freeSpace,
    this._bodyIdleTimeout,
    this._acceptTimeout,
    this._checkpointBytes,
    this._freeSpaceReserve,
  );

  final DeviceInfo _info;
  final String _tempDir;
  final String _saveDir;
  final TransferRepository _repo;
  final OfferDecider _decider;
  final FreeSpaceProbe? _freeSpace;
  final Duration _bodyIdleTimeout;
  final Duration _acceptTimeout;
  final int _checkpointBytes;
  final int _freeSpaceReserve;
  final Map<String, _Session> _sessions = {};
  final StreamController<ReceiveEvent> _events = StreamController.broadcast();
  late final HttpServer _server;

  static const int _maxJsonBytes = 4 * 1024 * 1024;

  /// Unfinished sessions at once, from all senders. More offers get 503.
  static const int maxOpenSessions = 8;

  /// Starts listening on [port] (0 = random, as ARCHITECTURE.md asks) and
  /// restores unfinished sessions from [repository].
  ///
  /// Partial files go to `<tempDir>/<sessionId>/<fileId>.part`; verified
  /// files are moved into [saveDir].
  static Future<ReceiveServer> start({
    required DeviceInfo info,
    required SecurityContext securityContext,
    required String tempDir,
    required String saveDir,
    required TransferRepository repository,
    required OfferDecider decider,
    FreeSpaceProbe? freeSpace,
    Object? address,
    int port = 0,
    Duration bodyIdleTimeout = const Duration(seconds: 15),
    Duration acceptTimeout = const Duration(seconds: 60),
    int checkpointBytes = 4 * 1024 * 1024,
    int freeSpaceReserve = 64 * 1024 * 1024,
  }) async {
    final server = ReceiveServer._(
      info,
      tempDir,
      saveDir,
      repository,
      decider,
      freeSpace,
      bodyIdleTimeout,
      acceptTimeout,
      checkpointBytes,
      freeSpaceReserve,
    );
    await Directory(tempDir).create(recursive: true);
    await Directory(saveDir).create(recursive: true);
    await server._restore();
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

  /// Current sessions, including ones restored after a restart.
  List<ReceiveSessionSnapshot> get sessions => [
    for (final s in _sessions.values)
      ReceiveSessionSnapshot(
        sessionId: s.id,
        sender: s.sender,
        status: s.status,
        reason: s.reason,
        files: [
          for (final f in s.files.values)
            ReceiveFileSnapshot(
              offer: f.offer,
              status: f.status,
              receivedBytes: f.status == FileTransferStatus.saved
                  ? f.offer.size
                  : f.received,
              savedPath: f.savedPath,
              errorCode: f.errorCode,
            ),
        ],
      ),
  ];

  /// True while bytes are being written.
  bool get isReceiving =>
      _sessions.values.any((s) => s.files.values.any((f) => f.busy));

  Future<void> close() async {
    await checkpointAll();
    for (final s in _sessions.values) {
      s.acceptTimer?.cancel();
      for (final ws in s.sockets.toList()) {
        await ws.close();
      }
    }
    await _server.close(force: true);
    // Uploads see their sockets close and release their files.
    await Future.wait([
      for (final s in _sessions.values)
        for (final f in s.files.values) f.idle,
    ]).timeout(const Duration(seconds: 5), onTimeout: () => const []);
    for (final s in _sessions.values) {
      for (final f in s.files.values) {
        f.dropHasher();
      }
    }
    await _events.close();
  }

  /// Saves the progress of every running upload now (app going to the
  /// background). Uploads keep running.
  Future<void> checkpointAll({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final waits = <Future<void>>[];
    for (final s in _sessions.values) {
      for (final f in s.files.values) {
        if (!f.busy) continue;
        waits.add((f.checkpointRequest ??= Completer<void>()).future);
      }
    }
    if (waits.isEmpty) return;
    await Future.wait(waits).timeout(timeout, onTimeout: () => const []);
  }

  /// Cancel from the receiver's side. An offer still waiting is declined.
  Future<void> cancel(String sessionId) async {
    final s = _sessions[sessionId];
    if (s == null || s.status.isTerminal) return;
    if (s.status == SessionStatus.offered) {
      await _reject(s, RejectReasons.declined);
    } else {
      await _cancel(s, 'receiver');
    }
  }

  Router _router() => Router(notFoundHandler: (_) => _notFound())
    ..get('/v1/info', (Request _) => _json(200, _info))
    ..post('/v1/sessions', _createSession)
    ..get('/v1/sessions/<sid>', _getSession)
    ..delete('/v1/sessions/<sid>', _deleteSession)
    ..get('/v1/sessions/<sid>/events', _eventSocket)
    ..get('/v1/sessions/<sid>/files/<fid>', _getFile)
    ..put('/v1/sessions/<sid>/files/<fid>', _putFile)
    ..post('/v1/sessions/<sid>/files/<fid>/complete', _complete);

  // ---------------------------------------------------------------- restore

  Future<void> _restore() async {
    for (final stored in await _repo.unfinished(TransferDirection.receive)) {
      final dir = p.join(_tempDir, stored.sessionId);
      if (stored.status == SessionStatus.offered) {
        // The prompt died with the app; the sender will see `rejected`.
        await _repo.updateSession(
          stored.rowId,
          status: SessionStatus.rejected,
          reason: RejectReasons.timeout,
        );
        await _deleteDir(dir);
        continue;
      }
      final files = <String, _ReceivingFile>{};
      for (final f in stored.files) {
        final part = p.join(dir, '${f.fileId}.part');
        var received = 0;
        if (!f.status.isTerminal) {
          received = await _restorePart(part, f.transferredBytes);
          if (received != f.transferredBytes) {
            await _repo.updateFile(
              stored.rowId,
              f.fileId,
              transferredBytes: received,
            );
          }
        }
        files[f.fileId] = _ReceivingFile(
          f.toOffer(),
          part,
          status: switch (f.status) {
            FileTransferStatus.verifying => FileTransferStatus.receiving,
            final other => other,
          },
          received: received,
          hashAttempts: f.hashAttempts,
          savedPath: f.finalLocation,
          errorCode: f.errorCode,
        );
      }
      final session = _Session(
        id: stored.sessionId,
        rowId: stored.rowId,
        dir: dir,
        sender: stored.peer,
        files: files,
        machine: SessionStateMachine(stored.status),
      );
      session.machine.tryMoveTo(SessionStatus.paused);
      if (stored.status != SessionStatus.paused) {
        await _repo.updateSession(stored.rowId, status: SessionStatus.paused);
      }
      _sessions[session.id] = session;
      _log('session ${session.id}: restored, paused');
    }
  }

  /// Cuts the partial file back to the last checkpoint: bytes after it may
  /// not have reached the disk before a crash.
  static Future<int> _restorePart(String path, int checkpoint) async {
    final file = File(path);
    if (!await file.exists()) {
      await file.create(recursive: true);
      return 0;
    }
    final length = await file.length();
    final keep = min(length, checkpoint);
    if (keep != length) {
      final raf = await file.open(mode: FileMode.append);
      try {
        await raf.truncate(keep);
      } finally {
        await raf.close();
      }
    }
    return keep;
  }

  // ----------------------------------------------------------------- offers

  Future<Response> _createSession(Request req) async {
    final SessionOffer offer;
    try {
      offer = SessionOffer.fromJson(await _readJson(req));
    } on FormatError catch (e) {
      return _error(400, ErrorCodes.badRequest, e.message);
    }
    if (!supportedVersions.contains(offer.protocol)) {
      return _error(
        400,
        ErrorCodes.unsupportedVersion,
        'unsupported protocol',
        {'versions': supportedVersions},
      );
    }
    final open = _sessions.values.where((s) => !s.status.isTerminal);
    // One unfinished session per sender (Phase 4 ties the id to the
    // certificate; until then it is only what the sender claims).
    if (open.any((s) => s.sender.id == offer.sender.id)) {
      _events.add(OfferRefused(offer.sender, RejectReasons.senderBusy));
      return _error(
        409,
        ErrorCodes.senderBusy,
        'finish or cancel the unfinished transfer first',
      );
    }
    if (open.length >= maxOpenSessions) {
      return _error(503, ErrorCodes.busy, 'too many open sessions');
    }
    final needed = await _neededBytes(offer.totalBytes);
    if (needed != null) {
      _events.add(
        OfferRefused(
          offer.sender,
          RejectReasons.noSpace,
          neededBytes: offer.totalBytes,
        ),
      );
      return _error(507, ErrorCodes.noSpace, 'not enough free space', {
        'neededBytes': offer.totalBytes,
      });
    }

    final id = _randomId();
    final dir = p.join(_tempDir, id);
    final rowId = await _repo.createSession(
      sessionId: id,
      direction: TransferDirection.receive,
      peer: offer.sender,
      status: SessionStatus.offered,
      files: [
        for (final f in offer.files)
          StoredFile.fromOffer(f, tempPath: p.join(dir, '${f.fileId}.part')),
      ],
    );
    final session = _Session(
      id: id,
      rowId: rowId,
      dir: dir,
      sender: offer.sender,
      files: Map.fromEntries([
        for (final f in offer.files)
          MapEntry(
            f.fileId,
            _ReceivingFile(f, p.join(dir, '${f.fileId}.part')),
          ),
      ]),
      machine: SessionStateMachine(),
    );
    _sessions[id] = session;
    _log('session $id: offered, ${offer.files.length} file(s)');
    _events.add(SessionOffered(id, offer.sender, offer.files));
    unawaited(_decide(session));
    return _json(
      200,
      SessionCreated(sessionId: id, status: SessionStatus.offered.name),
    );
  }

  /// Null if the space is there (or unknown); otherwise the bytes needed.
  Future<int?> _neededBytes(int offered, {_Session? excluding}) async {
    final probe = _freeSpace;
    if (probe == null) return null;
    final committed = _sessions.values
        .where((s) => s != excluding && !s.status.isTerminal)
        .fold(0, (sum, s) => sum + s.remainingBytes);
    final needed = offered + committed + _freeSpaceReserve;
    int? free;
    try {
      // Temp and save folders can be on different volumes (Android).
      final a = await probe(_tempDir);
      final b = await probe(_saveDir);
      free = a == null ? b : (b == null ? a : min(a, b));
    } catch (e) {
      _log('free space check failed: ${e.runtimeType}');
    }
    if (free == null || free >= needed) return null;
    return needed;
  }

  Future<void> _decide(_Session s) async {
    final decision = Completer<bool?>();
    s.acceptTimer = Timer(_acceptTimeout, () {
      if (!decision.isCompleted) decision.complete(null);
    });
    _decider(
      IncomingOffer(
        sessionId: s.id,
        sender: s.sender,
        files: [for (final f in s.files.values) f.offer],
      ),
    ).then(
      (v) {
        if (!decision.isCompleted) decision.complete(v);
      },
      onError: (Object e) {
        if (!decision.isCompleted) decision.complete(false);
      },
    );
    final accepted = await decision.future;
    s.acceptTimer?.cancel();
    if (s.status != SessionStatus.offered) return; // cancelled meanwhile
    if (accepted == null) return _reject(s, RejectReasons.timeout);
    if (!accepted) return _reject(s, RejectReasons.declined);
    // The user may have taken a while; check the space again.
    final total = s.files.values.fold(0, (sum, f) => sum + f.offer.size);
    if (await _neededBytes(total, excluding: s) != null) {
      return _reject(s, RejectReasons.noSpace, neededBytes: total);
    }
    if (s.status != SessionStatus.offered) return;
    await Directory(s.dir).create(recursive: true);
    await _setStatus(s, SessionStatus.accepted);
    _broadcast(s, const AcceptedEvent());
  }

  Future<void> _reject(_Session s, String reason, {int? neededBytes}) async {
    s.acceptTimer?.cancel();
    s.reason = reason;
    await _setStatus(s, SessionStatus.rejected, reason);
    _broadcast(s, RejectedEvent(reason, neededBytes: neededBytes));
    await _closeSockets(s);
    await _deleteDir(s.dir);
  }

  // ------------------------------------------------------- session routes

  Response _getSession(Request req, String sid) {
    final s = _sessions[sid];
    if (s == null) return _notFound();
    return _json(200, _sessionStatus(s));
  }

  Future<Response> _deleteSession(Request req, String sid) async {
    final s = _sessions[sid];
    if (s == null) return _notFound();
    if (!s.status.isTerminal) {
      if (s.status == SessionStatus.offered) {
        // The sender withdrew the offer before an answer.
        s.acceptTimer?.cancel();
      }
      await _cancel(s, 'sender');
    }
    return _json(200, _sessionStatus(s));
  }

  SessionStatusReply _sessionStatus(_Session s) => SessionStatusReply(
    sessionId: s.id,
    status: s.status,
    reason: s.reason,
    files: [for (final f in s.files.values) _fileStatus(f)],
  );

  Future<void> _cancel(_Session s, String by) async {
    s.reason = by;
    await _setStatus(s, SessionStatus.cancelled, by);
    _log('session ${s.id}: cancelled by $by');
    _broadcast(s, CancelledEvent(by));
    await _closeSockets(s);
    // Running uploads see the state and stop after their current chunk.
    await Future.wait([for (final f in s.files.values) f.idle]);
    for (final f in s.files.values) {
      f.dropHasher();
    }
    await _deleteDir(s.dir);
  }

  FutureOr<Response> _eventSocket(Request req, String sid) {
    final s = _sessions[sid];
    if (s == null) return _notFound();
    final handler = webSocketHandler((ws, _) {
      final socket = _EventSocket(
        (text) => ws.sink.add(text),
        () => ws.sink.close(),
      );
      // A sender reconnecting many times must not pile up sockets.
      if (s.sockets.length >= 4) {
        final oldest = s.sockets.first;
        s.sockets.remove(oldest);
        unawaited(oldest.close());
      }
      s.sockets.add(socket);
      // Writes to a sender that vanished fail here, not at add(); without a
      // handler they would surface as uncaught errors.
      ws.sink.done.then(
        (_) => s.sockets.remove(socket),
        onError: (Object _) => s.sockets.remove(socket),
      );
      ws.stream.listen(
        (_) {}, // The sender has nothing to say on this socket.
        onDone: () => s.sockets.remove(socket),
        onError: (Object _) => s.sockets.remove(socket),
        cancelOnError: true,
      );
      for (final e in _replay(s)) {
        socket.send(jsonEncode(e.toJson()));
      }
      if (s.status.isTerminal) unawaited(socket.close());
    }, pingInterval: const Duration(seconds: 10));
    return handler(req);
  }

  /// What a newly connected sender missed.
  List<SessionEvent> _replay(_Session s) => switch (s.status) {
    SessionStatus.offered => const [],
    SessionStatus.rejected => [RejectedEvent(s.reason ?? 'declined')],
    SessionStatus.cancelled => [CancelledEvent(s.reason ?? 'receiver')],
    SessionStatus.failed => [ErrorEvent(s.reason ?? ErrorCodes.ioError)],
    _ => [
      const AcceptedEvent(),
      for (final f in s.files.values)
        if (f.status == FileTransferStatus.saved)
          FileDoneEvent(f.offer.fileId)
        else if (f.status == FileTransferStatus.failed)
          ErrorEvent(
            f.errorCode ?? ErrorCodes.fileFailed,
            fileId: f.offer.fileId,
          )
        else if (f.received > 0)
          ProgressEvent(f.offer.fileId, f.received),
    ],
  };

  // ---------------------------------------------------------- file routes

  /// Common checks for routes that touch a file's bytes.
  (_Session, _ReceivingFile)? _lookup(String sid, String fid) {
    final s = _sessions[sid];
    final f = s?.files[fid];
    return f == null ? null : (s!, f);
  }

  Response? _sessionGate(_Session s) {
    if (s.status.isTerminal) {
      return _error(410, ErrorCodes.sessionClosed, 'session is closed', {
        'status': s.status.name,
        if (s.reason != null) 'reason': s.reason,
      });
    }
    if (s.status == SessionStatus.offered) {
      return _error(403, ErrorCodes.notAccepted, 'offer not accepted yet');
    }
    return null;
  }

  Response? _fileGate(_ReceivingFile f) {
    if (f.status == FileTransferStatus.saved) {
      return _error(409, ErrorCodes.alreadySaved, 'file already saved');
    }
    if (f.status == FileTransferStatus.failed) {
      return _error(410, ErrorCodes.fileFailed, 'file failed', {
        'reason': f.errorCode,
      });
    }
    return null;
  }

  Future<Response> _getFile(Request req, String sid, String fid) async {
    final found = _lookup(sid, fid);
    if (found == null) return _notFound();
    final (s, f) = found;
    final gate = _sessionGate(s);
    if (gate != null) return gate;
    return _json(200, _fileStatus(f));
  }

  Future<Response> _putFile(Request req, String sid, String fid) async {
    final found = _lookup(sid, fid);
    if (found == null) return _notFound();
    final (s, f) = found;
    final gate = _sessionGate(s) ?? _fileGate(f);
    if (gate != null) return gate;
    final offset = int.tryParse(req.url.queryParameters['offset'] ?? '');
    if (offset == null || offset < 0) {
      return _error(400, ErrorCodes.badRequest, 'missing or bad offset');
    }
    if (f.busy) {
      return _error(409, ErrorCodes.busy, 'another upload is in progress');
    }
    f.lock();
    try {
      return await _receive(req, s, f, offset);
    } finally {
      f.unlock();
      final pending = f.checkpointRequest;
      f.checkpointRequest = null;
      if (pending != null && !pending.isCompleted) pending.complete();
    }
  }

  Future<Response> _receive(
    Request req,
    _Session s,
    _ReceivingFile f,
    int offset,
  ) async {
    final size = f.offer.size;
    final part = File(f.partPath);
    if (!await part.exists()) await part.create(recursive: true);
    final received = await part.length();
    f.received = received;
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
      await _failFile(s, f, ErrorCodes.tooManyBytes);
      return _error(413, ErrorCodes.tooManyBytes, 'body exceeds declared size');
    }

    await _setStatus(s, SessionStatus.transferring);
    if (f.status != FileTransferStatus.receiving) {
      f.status = FileTransferStatus.receiving;
      await _repo.updateFile(
        s.rowId,
        f.offer.fileId,
        status: FileTransferStatus.receiving,
      );
    }

    f.digest = null;
    // Keep hashing where the last upload stopped. Without a hash that
    // matches the bytes on disk (after a restart) don't hash here: hashing
    // a large prefix would stall the upload. /complete hashes from disk.
    var hasher = f.hasher;
    if (hasher == null || f.hashedBytes != offset) {
      f.dropHasher();
      hasher = offset == 0 ? await Sha256Isolate.spawn() : null;
      f.hasher = hasher;
      f.hashedBytes = offset;
    }
    final raf = await part.open(mode: FileMode.append);
    var written = offset;
    var checkpointed = offset;
    var overflow = false;
    var stopped = false;
    Object? interruption;
    final buffer = BytesBuilder(copy: false);

    Future<void> checkpoint() async {
      await raf.flush(); // fsync: the count we store must be on disk
      checkpointed = written;
      await _repo.updateFile(
        s.rowId,
        f.offer.fileId,
        transferredBytes: written,
      );
      _broadcast(s, ProgressEvent(f.offer.fileId, written));
    }

    Future<void> flush() async {
      if (buffer.isEmpty) return;
      final bytes = buffer.takeBytes();
      try {
        await raf.writeFrom(bytes);
      } on FileSystemException {
        // Part of the buffer may be on disk: the hash no longer matches.
        f.dropHasher();
        rethrow;
      }
      written += bytes.length;
      if (f.hasher != null) {
        await f.hasher!.add(bytes);
        f.hashedBytes = written;
      }
      f.received = written;
      _events.add(FileProgress(s.id, f.offer.fileId, written, size));
      final request = f.checkpointRequest;
      if (written - checkpointed >= _checkpointBytes || request != null) {
        await checkpoint();
        f.checkpointRequest = null;
        request?.complete();
      }
    }

    try {
      try {
        await for (final chunk in req.read().timeout(_bodyIdleTimeout)) {
          // Never trust the declared size (CLAUDE.md hard rule 6).
          if (written + buffer.length + chunk.length > size) {
            overflow = true;
            break;
          }
          buffer.add(chunk);
          if (buffer.length >= defaultChunkSize) await flush();
          if (s.status.isTerminal) {
            stopped = true;
            break;
          }
        }
        if (!overflow && !stopped) await flush();
      } on FileSystemException catch (e) {
        interruption = e;
      } on Exception catch (e) {
        // Client went away or stalled. Keep every byte that arrived.
        interruption = e;
        await flush();
      }
      if (!overflow && !stopped) await checkpoint();
    } on FileSystemException catch (e) {
      interruption = e;
    } finally {
      await raf.close();
    }

    if (overflow) {
      _log('file ${f.offer.fileId}: too many bytes, file failed');
      await _failFile(s, f, ErrorCodes.tooManyBytes);
      return _error(413, ErrorCodes.tooManyBytes, 'body exceeds declared size');
    }
    if (stopped) {
      f.dropHasher();
      return _sessionGate(s)!;
    }
    if (interruption is FileSystemException) {
      return _diskError(s, f, interruption);
    }
    if (interruption != null) {
      // The hasher stays alive: it matches the bytes on disk.
      _log('file ${f.offer.fileId}: interrupted at $written bytes');
      await _pauseIfIdle(s, except: f);
      // The client usually never sees this response.
      return _error(400, ErrorCodes.incomplete, 'upload interrupted', {
        'receivedBytes': written,
      });
    }
    final live = f.hasher;
    if (written == size && live != null) {
      f.hasher = null;
      f.digest = await live.close();
    }
    return _json(200, _fileStatus(f));
  }

  /// A write failed: most likely the disk is full. Keep the partial file
  /// and pause, as ARCHITECTURE.md asks.
  Future<Response> _diskError(
    _Session s,
    _ReceivingFile f,
    FileSystemException e,
  ) async {
    final noSpace = _isNoSpace(e);
    final code = noSpace ? ErrorCodes.noSpace : ErrorCodes.ioError;
    _log('file ${f.offer.fileId}: write failed ($code)');
    final onDisk = await File(f.partPath).length();
    f.received = onDisk;
    await _repo.updateFile(s.rowId, f.offer.fileId, transferredBytes: onDisk);
    _broadcast(s, ErrorEvent(code, fileId: f.offer.fileId));
    await _pauseIfIdle(s, except: f);
    return _error(507, code, 'could not write the file', {
      'receivedBytes': onDisk,
    });
  }

  static bool _isNoSpace(FileSystemException e) {
    final code = e.osError?.errorCode;
    // ENOSPC on Linux, Android and iOS; ERROR_DISK_FULL / HANDLE_DISK_FULL
    // on Windows test hosts.
    return code == 28 || code == 112 || code == 39;
  }

  Future<Response> _complete(Request req, String sid, String fid) async {
    final found = _lookup(sid, fid);
    if (found == null) return _notFound();
    final (s, f) = found;
    final gate = _sessionGate(s) ?? _fileGate(f);
    if (gate != null) return gate;
    if (f.busy) {
      return _error(409, ErrorCodes.busy, 'upload still in progress');
    }
    final CompleteRequest body;
    try {
      body = CompleteRequest.fromJson(await _readJson(req));
    } on FormatError catch (e) {
      return _error(400, ErrorCodes.badRequest, e.message);
    }
    if (f.busy) {
      return _error(409, ErrorCodes.busy, 'upload still in progress');
    }
    f.lock();
    try {
      final size = f.offer.size;
      final part = File(f.partPath);
      if (size == 0 && !await part.exists()) {
        await part.create(recursive: true);
      }
      final received = await part.length();
      if (received != size) {
        return _error(409, ErrorCodes.incomplete, 'file not fully received', {
          'receivedBytes': received,
        });
      }
      await _setStatus(s, SessionStatus.verifying);
      f.status = FileTransferStatus.verifying;
      await _repo.updateFile(
        s.rowId,
        fid,
        status: FileTransferStatus.verifying,
      );
      final digest = f.digest ?? await _hashFile(f.partPath, size);
      if (s.status.isTerminal) return _sessionGate(s)!;
      if (digest != body.sha256) return await _hashMismatch(s, f);

      final String dest;
      try {
        dest = availablePath(_saveDir, sanitizeFileName(f.offer.name));
        await _move(f.partPath, dest);
      } on FileSystemException catch (e) {
        f.status = FileTransferStatus.receiving;
        await _repo.updateFile(
          s.rowId,
          fid,
          status: FileTransferStatus.receiving,
        );
        await _pauseIfIdle(s, except: f);
        final code = _isNoSpace(e) ? ErrorCodes.noSpace : ErrorCodes.ioError;
        _broadcast(s, ErrorEvent(code, fileId: fid));
        return _error(507, code, 'could not save file');
      }
      f.savedPath = dest;
      f.status = FileTransferStatus.saved;
      await _repo.updateFile(
        s.rowId,
        fid,
        status: FileTransferStatus.saved,
        transferredBytes: size,
        sha256: digest,
        finalLocation: dest,
      );
      _log('file $fid: verified and saved ($size bytes)');
      _events.add(FileSaved(s.id, fid, dest, size));
      _broadcast(s, FileDoneEvent(fid));
      await _afterFile(s);
      return _json(200, _fileStatus(f));
    } finally {
      f.unlock();
    }
  }

  /// First mismatch: start the file again from zero. Second: fail it
  /// (ARCHITECTURE.md transfer rule 6).
  Future<Response> _hashMismatch(_Session s, _ReceivingFile f) async {
    final fid = f.offer.fileId;
    f.hashAttempts++;
    f.digest = null;
    f.dropHasher();
    if (f.hashAttempts >= 2) {
      _log('file $fid: hash mismatch again, file failed');
      await _failFile(s, f, ErrorCodes.hashMismatch, attempts: f.hashAttempts);
      return _error(422, ErrorCodes.fileFailed, 'SHA-256 does not match', {
        'retry': false,
      });
    }
    await File(f.partPath).writeAsBytes(const []);
    f.received = 0;
    f.status = FileTransferStatus.receiving;
    await _repo.updateFile(
      s.rowId,
      fid,
      status: FileTransferStatus.receiving,
      transferredBytes: 0,
      hashAttempts: f.hashAttempts,
    );
    await _setStatus(s, SessionStatus.transferring);
    _log('file $fid: hash mismatch, partial file reset');
    _events.add(FileProgress(s.id, fid, 0, f.offer.size));
    _broadcast(s, ErrorEvent(ErrorCodes.hashMismatch, fileId: fid));
    return _error(422, ErrorCodes.hashMismatch, 'SHA-256 does not match', {
      'retry': true,
    });
  }

  Future<void> _failFile(
    _Session s,
    _ReceivingFile f,
    String code, {
    int? attempts,
  }) async {
    final fid = f.offer.fileId;
    f.status = FileTransferStatus.failed;
    f.errorCode = code;
    f.received = 0;
    f.digest = null;
    f.dropHasher();
    try {
      await File(f.partPath).delete();
    } on FileSystemException {
      // Already gone.
    }
    await _repo.updateFile(
      s.rowId,
      fid,
      status: FileTransferStatus.failed,
      errorCode: code,
      transferredBytes: 0,
      hashAttempts: attempts,
    );
    _events.add(FileFailed(s.id, fid, code));
    _broadcast(s, ErrorEvent(code, fileId: fid));
    await _afterFile(s);
  }

  /// After a file ends: finish the session when no file is left.
  Future<void> _afterFile(_Session s) async {
    if (s.status.isTerminal) return;
    final files = s.files.values;
    if (files.every((f) => f.status.isTerminal)) {
      final anySaved = files.any((f) => f.status == FileTransferStatus.saved);
      if (anySaved) {
        await _setStatus(s, SessionStatus.verifying);
        await _setStatus(s, SessionStatus.done);
      } else {
        s.reason = ErrorCodes.fileFailed;
        await _setStatus(s, SessionStatus.failed, s.reason);
      }
      _log('session ${s.id}: ${s.status.name}');
      await _closeSockets(s);
      await _deleteDir(s.dir);
    } else if (s.status == SessionStatus.verifying) {
      await _setStatus(s, SessionStatus.transferring);
    }
  }

  Future<void> _pauseIfIdle(
    _Session s, {
    required _ReceivingFile except,
  }) async {
    if (s.status.isTerminal) return;
    if (s.files.values.any((f) => f != except && f.busy)) return;
    await _setStatus(s, SessionStatus.paused);
  }

  // ---------------------------------------------------------------- helpers

  Future<void> _setStatus(
    _Session s,
    SessionStatus to, [
    String? reason,
  ]) async {
    if (s.status == to) return;
    if (!s.machine.tryMoveTo(to)) {
      _log('session ${s.id}: ignored ${s.status.name} -> ${to.name}');
      return;
    }
    await _repo.updateSession(s.rowId, status: to, reason: reason);
    _events.add(SessionStateChanged(s.id, to, reason));
  }

  FileStatus _fileStatus(_ReceivingFile f) => FileStatus(
    fileId: f.offer.fileId,
    size: f.offer.size,
    receivedBytes: f.status == FileTransferStatus.saved
        ? f.offer.size
        : f.received,
    status: f.status.name,
  );

  void _broadcast(_Session s, SessionEvent e) {
    final text = jsonEncode(e.toJson());
    for (final ws in s.sockets.toList()) {
      try {
        ws.send(text);
      } on StateError {
        s.sockets.remove(ws);
      }
    }
  }

  static Future<void> _closeSockets(_Session s) async {
    final sockets = s.sockets.toList();
    s.sockets.clear();
    for (final ws in sockets) {
      try {
        await ws.close().timeout(const Duration(seconds: 2));
      } on Object {
        // Already closed or the peer is gone.
      }
    }
  }

  static Future<void> _deleteDir(String dir) async {
    try {
      await Directory(dir).delete(recursive: true);
    } on FileSystemException {
      // Not created yet, or already gone.
    }
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

  static void _log(String message) => logEvent('server', message);
}
