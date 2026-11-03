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
import '../protocol/auth_messages.dart';
import '../protocol/events.dart';
import '../protocol/models.dart';
import '../security/device_credentials.dart';
import '../storage/transfer_repository.dart';
import '../storage/trust_repository.dart';
import 'rate_limiter.dart';
import '../media/save_target.dart';
import 'file_store.dart';
import 'sender_auth.dart';

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
  const FileSaved(
    super.sessionId,
    this.fileId,
    this.savedPath,
    this.size, {
    this.collection = SaveCollection.files,
    this.fallback,
  });
  final String fileId;

  /// Opaque location (path, content URI, Photos id); never shown or logged.
  final String savedPath;
  final int size;

  /// Where the user finds it.
  final SaveCollection collection;

  /// Why it is not in the gallery although it is a photo or video
  /// ([SaveFallback]).
  final String? fallback;
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
    required this.senderFingerprint,
    required this.pairingCode,
    this.trust = PeerTrust.unknown,
  });

  final String sessionId;

  /// What the sender claims; only [senderFingerprint] is proven.
  final SenderInfo sender;
  final List<FileOffer> files;
  final String senderFingerprint;

  /// The 6-digit code the sender shows too. The user checks it before
  /// accepting from an untrusted device (ARCHITECTURE.md, "Pairing").
  final String pairingCode;
  final PeerTrust trust;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);
}

/// Shows the Accept prompt; completes with true to accept. The server
/// rejects with `timeout` if it takes longer than its accept timeout.
typedef OfferDecider = Future<bool> Function(IncomingOffer offer);

/// Free bytes on the volume holding [path], or null if unknown.
typedef FreeSpaceProbe = Future<int?> Function(String path);

/// Whether [fingerprint] is trusted, given what the sender claims to be.
typedef TrustLookup = Future<PeerTrust> Function(
  String fingerprint,
  SenderInfo claimed,
);

Future<PeerTrust> _trustNobody(String _, SenderInfo _) async =>
    PeerTrust.unknown;

/// Limits for one server (ARCHITECTURE.md, "Abuse limits", D-032).
class ServerLimits {
  const ServerLimits({
    this.offerBurst = 3,
    this.offerRefill = const Duration(seconds: 20),
    this.authBurst = 10,
    this.authRefill = const Duration(seconds: 3),
    this.maxHeaderBytes = 16 * 1024,
    this.maxControlBodyBytes = 16 * 1024,
    this.maxOfferBodyBytes = 4 * 1024 * 1024,
  });

  /// `POST /v1/sessions` per IP address: [offerBurst] at once, then one
  /// per [offerRefill] (3 a minute).
  final int offerBurst;
  final Duration offerRefill;

  /// `POST /v1/auth/challenge` and `/v1/auth` per IP address.
  final int authBurst;
  final Duration authRefill;

  /// Sum of header names and values. dart:io itself stops at 1 MB.
  final int maxHeaderBytes;

  /// Auth and `complete` bodies: small JSON.
  final int maxControlBodyBytes;

  /// An offer of 10,000 files with long names fits.
  final int maxOfferBodyBytes;
}

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
    this.location, {
    this.status = FileTransferStatus.pending,
    this.received = 0,
    this.hashAttempts = 0,
    this.savedPath,
    this.errorCode,
  });

  final FileOffer offer;

  /// Where the partial file is ([ReceivedFileStore]); may change when the
  /// part is first created.
  String location;
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
    required this.senderFingerprint,
    required this.files,
    required this.machine,
    this.pairingCode = '',
    this.trust = PeerTrust.unknown,
  });

  final String id;
  final int rowId;
  final String dir;
  final SenderInfo sender;

  /// Only this sender may see or continue the session.
  final String senderFingerprint;

  /// From the authentication that made the offer; empty after a restart
  /// (restored sessions are past the Accept prompt).
  final String pairingCode;
  final PeerTrust trust;

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
/// Senders authenticate first (`/v1/auth`, D-027); every session belongs
/// to the fingerprint that offered it.
class ReceiveServer {
  ReceiveServer._(
    this._info,
    this._auth,
    this._trustLookup,
    this._acceptsUntrusted,
    this._limits,
    this._tempDir,
    this._saveDir,
    this._store,
    this._repo,
    this._decider,
    this._freeSpace,
    this._bodyIdleTimeout,
    this._acceptTimeout,
    this._checkpointBytes,
    this._freeSpaceReserve,
  );

  final DeviceInfo _info;
  final SenderAuthenticator _auth;
  final TrustLookup _trustLookup;
  final bool Function() _acceptsUntrusted;
  final ServerLimits _limits;
  late final RateLimiter _offerLimiter = RateLimiter(
    burst: _limits.offerBurst,
    refillEvery: _limits.offerRefill,
  );
  late final RateLimiter _authLimiter = RateLimiter(
    burst: _limits.authBurst,
    refillEvery: _limits.authRefill,
  );
  final String _tempDir;

  /// A folder on the volume files are saved to, for the free-space check.
  final String _saveDir;
  final ReceivedFileStore _store;
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

  /// Unfinished sessions at once, from all senders. More offers get 503.
  static const int maxOpenSessions = 8;

  /// Starts listening on [port] (0 = random, as ARCHITECTURE.md asks) and
  /// restores unfinished sessions from [repository].
  ///
  /// TLS 1.3 with [credentials]. [trustLookup] tells trusted senders apart;
  /// while [acceptsUntrusted] returns false, offers from untrusted senders
  /// get 403 `receiving_off`.
  ///
  /// Session folders are `<tempDir>/<sessionId>`. [store] holds partial
  /// files and saves verified ones; by default a [FolderStore] that moves
  /// them into [saveDir].
  static Future<ReceiveServer> start({
    required DeviceInfo info,
    required DeviceCredentials credentials,
    required String tempDir,
    required String saveDir,
    ReceivedFileStore? store,
    required TransferRepository repository,
    required OfferDecider decider,
    TrustLookup trustLookup = _trustNobody,
    bool Function()? acceptsUntrusted,
    ServerLimits limits = const ServerLimits(),
    SenderAuthenticator? authenticator,
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
      authenticator ??
          SenderAuthenticator(ownFingerprint: credentials.fingerprint),
      trustLookup,
      acceptsUntrusted ?? () => true,
      limits,
      tempDir,
      saveDir,
      store ?? FolderStore(saveDir),
      repository,
      decider,
      freeSpace,
      bodyIdleTimeout,
      acceptTimeout,
      checkpointBytes,
      freeSpaceReserve,
    );
    await Directory(tempDir).create(recursive: true);
    if (store == null) await Directory(saveDir).create(recursive: true);
    await server._restore();
    server._server = await shelf_io.serve(
      server._handler(),
      address ?? InternetAddress.anyIPv4,
      port,
      securityContext: credentials.serverContext(),
    );
    // Idle keep-alive connections are closed sooner than dart:io's 120 s.
    server._server.idleTimeout = const Duration(seconds: 30);
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

  Handler _handler() => const Pipeline()
      .addMiddleware(_limitHeaders)
      .addMiddleware(_requireAuth)
      .addHandler(_router().call);

  Router _router() => Router(notFoundHandler: (_) => _notFound())
    ..get('/v1/info', (Request _) => _json(200, _info))
    ..post('/v1/auth/challenge', _challenge)
    ..post('/v1/auth', _authenticate)
    ..post('/v1/sessions', _createSession)
    ..get('/v1/sessions/<sid>', _getSession)
    ..delete('/v1/sessions/<sid>', _deleteSession)
    ..get('/v1/sessions/<sid>/events', _eventSocket)
    ..get('/v1/sessions/<sid>/files/<fid>', _getFile)
    ..put('/v1/sessions/<sid>/files/<fid>', _putFile)
    ..post('/v1/sessions/<sid>/files/<fid>/complete', _complete);

  // ------------------------------------------------- authentication, limits

  static const String _peerKey = 'crossdrop.peer';

  /// Paths that need a token: everything under `/v1/sessions`.
  static bool _needsAuth(Request req) =>
      req.url.path == 'v1/sessions' || req.url.path.startsWith('v1/sessions/');

  /// The authenticated sender of a request that passed [_requireAuth].
  static AuthenticatedSender _peer(Request req) =>
      req.context[_peerKey]! as AuthenticatedSender;

  /// The session [sid] if it belongs to the caller. Someone else's session
  /// looks the same as one that does not exist.
  _Session? _owned(Request req, String sid) {
    final s = _sessions[sid];
    if (s == null || s.senderFingerprint != _peer(req).fingerprint) {
      return null;
    }
    return s;
  }

  Handler _limitHeaders(Handler inner) => (req) {
    var total = 0;
    req.headersAll.forEach((name, values) {
      total += name.length;
      for (final v in values) {
        total += v.length;
      }
    });
    if (total > _limits.maxHeaderBytes) {
      return _error(431, ErrorCodes.headersTooLarge, 'headers too large');
    }
    return inner(req);
  };

  Handler _requireAuth(Handler inner) => (req) {
    if (!_needsAuth(req)) return inner(req);
    final header = req.headers['authorization'] ?? '';
    const prefix = 'Bearer ';
    final sender = header.startsWith(prefix)
        ? _auth.lookup(header.substring(prefix.length))
        : null;
    if (sender == null) {
      return _error(401, ErrorCodes.authRequired, 'authenticate first');
    }
    return inner(req.change(context: {_peerKey: sender}));
  };

  /// Null if [req]'s address may go on; otherwise a 429 reply.
  Response? _rateLimit(RateLimiter limiter, Request req) {
    final info = req.context['shelf.io.connection_info'];
    final ip = info is HttpConnectionInfo
        ? info.remoteAddress.address
        : 'unknown';
    final wait = limiter.take(ip);
    if (wait == null) return null;
    _log('rate limited ${req.url.path}');
    final seconds = (wait.inMilliseconds / 1000).ceil();
    return Response(
      429,
      body: jsonEncode({
        'error': ErrorCodes.rateLimited,
        'message': 'too many requests',
        'retryAfter': seconds,
      }),
      headers: {'content-type': 'application/json', 'retry-after': '$seconds'},
    );
  }

  Future<Response> _challenge(Request req) async {
    final limited = _rateLimit(_authLimiter, req);
    if (limited != null) return limited;
    try {
      final body = AuthChallengeRequest.fromJson(
        await _readJson(req, _limits.maxControlBodyBytes),
      );
      return _json(200, AuthChallenge(nonce: _auth.challenge(body.commit)));
    } on _BodyTooLarge {
      return _error(413, ErrorCodes.bodyTooLarge, 'body too large');
    } on FormatError catch (e) {
      return _error(400, ErrorCodes.badRequest, e.message);
    }
  }

  Future<Response> _authenticate(Request req) async {
    final limited = _rateLimit(_authLimiter, req);
    if (limited != null) return limited;
    final AuthRequest body;
    try {
      body = AuthRequest.fromJson(
        await _readJson(req, _limits.maxControlBodyBytes),
      );
    } on _BodyTooLarge {
      return _error(413, ErrorCodes.bodyTooLarge, 'body too large');
    } on FormatError catch (e) {
      return _error(400, ErrorCodes.badRequest, e.message);
    }
    try {
      final granted = _auth.authenticate(body);
      _log(
        'sender ${granted.sender.fingerprint.substring(0, 8)} '
        'authenticated',
      );
      return _json(
        200,
        AuthGranted(token: granted.token, expiresIn: _auth.tokenTtl.inSeconds),
      );
    } on AuthFailure catch (e) {
      _log('authentication refused: ${e.reason}');
      return _error(401, ErrorCodes.authFailed, 'authentication failed');
    }
  }

  // ---------------------------------------------------------------- restore

  Future<void> _restore() async {
    for (final stored in await _repo.unfinished(TransferDirection.receive)) {
      final dir = p.join(_tempDir, stored.sessionId);
      final senderFp = stored.peerFingerprint;
      if (senderFp == null) {
        // Stored before Phase 4: nobody can prove they own it.
        await _repo.updateSession(
          stored.rowId,
          status: SessionStatus.failed,
          reason: 'expired',
        );
        await _discardStored(stored, dir);
        continue;
      }
      if (stored.status == SessionStatus.offered) {
        // The prompt died with the app; the sender will see `rejected`.
        await _repo.updateSession(
          stored.rowId,
          status: SessionStatus.rejected,
          reason: RejectReasons.timeout,
        );
        await _discardStored(stored, dir);
        continue;
      }
      final files = <String, _ReceivingFile>{};
      for (final f in stored.files) {
        final offer = f.toOffer();
        final part = f.tempPath ?? _store.initialLocation(dir, offer);
        var received = 0;
        if (!f.status.isTerminal) {
          try {
            received = await _store.restore(part, f.transferredBytes);
          } on FileSystemException {
            received = 0;
          }
          if (received != f.transferredBytes) {
            await _repo.updateFile(
              stored.rowId,
              f.fileId,
              transferredBytes: received,
            );
          }
        }
        files[f.fileId] = _ReceivingFile(
          offer,
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
        senderFingerprint: senderFp,
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

  /// Deletes the partial files of a stored session nobody will finish.
  Future<void> _discardStored(StoredSession stored, String dir) async {
    for (final f in stored.files) {
      final loc = f.tempPath;
      if (loc != null && f.status != FileTransferStatus.saved) {
        await _store.delete(loc);
      }
    }
    await _deleteDir(dir);
  }

  // ----------------------------------------------------------------- offers

  Future<Response> _createSession(Request req) async {
    final limited = _rateLimit(_offerLimiter, req);
    if (limited != null) return limited;
    final peer = _peer(req);
    final SessionOffer offer;
    try {
      offer = SessionOffer.fromJson(
        await _readJson(req, _limits.maxOfferBodyBytes),
      );
    } on _BodyTooLarge {
      return _error(413, ErrorCodes.bodyTooLarge, 'offer too large');
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
    final PeerTrust trust;
    try {
      trust = await _trustLookup(peer.fingerprint, offer.sender);
    } catch (e) {
      _log('trust lookup failed: ${e.runtimeType}');
      return _error(503, ErrorCodes.busy, 'try again');
    }
    if (!trust.isTrusted && !_acceptsUntrusted()) {
      _events.add(OfferRefused(offer.sender, ErrorCodes.receivingOff));
      return _error(
        403,
        ErrorCodes.receivingOff,
        'receiving is turned off on this device',
      );
    }
    final open = _sessions.values.where((s) => !s.status.isTerminal);
    // One unfinished session per sender, by proven fingerprint.
    if (open.any((s) => s.senderFingerprint == peer.fingerprint)) {
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
      peerFingerprint: peer.fingerprint,
      status: SessionStatus.offered,
      files: [
        for (final f in offer.files)
          StoredFile.fromOffer(f, tempPath: _store.initialLocation(dir, f)),
      ],
    );
    final session = _Session(
      id: id,
      rowId: rowId,
      dir: dir,
      sender: offer.sender,
      senderFingerprint: peer.fingerprint,
      pairingCode: peer.pairingCode,
      trust: trust,
      files: Map.fromEntries([
        for (final f in offer.files)
          MapEntry(f.fileId, _ReceivingFile(f, _store.initialLocation(dir, f))),
      ]),
      machine: SessionStateMachine(),
    );
    _sessions[id] = session;
    _log('session $id: offered, ${offer.files.length} file(s)');
    _events.add(SessionOffered(id, offer.sender, offer.files));
    unawaited(_decide(session));
    return _json(
      200,
      SessionCreated(
        sessionId: id,
        status: SessionStatus.offered.name,
        trusted: trust.isTrusted,
      ),
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
    final offer = IncomingOffer(
      sessionId: s.id,
      sender: s.sender,
      files: [for (final f in s.files.values) f.offer],
      senderFingerprint: s.senderFingerprint,
      pairingCode: s.pairingCode,
      trust: s.trust,
    );
    // Auto-accept only for the exact trusted fingerprint the user chose.
    final auto = s.trust.trusted?.autoAccept ?? false;
    if (auto) _log('session ${s.id}: auto-accepted (trusted device)');
    (auto ? Future.value(true) : _decider(offer)).then(
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
    await _discardParts(s);
  }

  // ------------------------------------------------------- session routes

  Response _getSession(Request req, String sid) {
    final s = _owned(req, sid);
    if (s == null) return _notFound();
    return _json(200, _sessionStatus(s));
  }

  Future<Response> _deleteSession(Request req, String sid) async {
    final s = _owned(req, sid);
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
    await _discardParts(s);
  }

  FutureOr<Response> _eventSocket(Request req, String sid) {
    final s = _owned(req, sid);
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
  (_Session, _ReceivingFile)? _lookup(Request req, String sid, String fid) {
    final s = _owned(req, sid);
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
    final found = _lookup(req, sid, fid);
    if (found == null) return _notFound();
    final (s, f) = found;
    final gate = _sessionGate(s);
    if (gate != null) return gate;
    return _json(200, _fileStatus(f));
  }

  Future<Response> _putFile(Request req, String sid, String fid) async {
    final found = _lookup(req, sid, fid);
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
    final received = await _store.length(f.location);
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
    final PartFile raf;
    try {
      raf = await _openPart(s, f);
    } on FileSystemException catch (e) {
      f.dropHasher();
      return _diskError(s, f, e);
    }
    var written = offset;
    var checkpointed = offset;
    var overflow = false;
    var stopped = false;
    Object? interruption;
    final buffer = BytesBuilder(copy: false);

    Future<void> checkpoint() async {
      await raf.sync(); // the count we store must be on disk
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
        await raf.append(bytes);
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
    final onDisk = await _store.length(f.location);
    f.received = onDisk;
    await _repo.updateFile(s.rowId, f.offer.fileId, transferredBytes: onDisk);
    _broadcast(s, ErrorEvent(code, fileId: f.offer.fileId));
    await _pauseIfIdle(s, except: f);
    return _error(507, code, 'could not write the file', {
      'receivedBytes': onDisk,
    });
  }

  static bool _isNoSpace(FileSystemException e) => isNoSpace(e);

  /// Opens the part, creating it on first use, and stores a new location.
  Future<PartFile> _openPart(_Session s, _ReceivingFile f) async {
    final (part, location) = await _store.open(
      f.location,
      sessionDir: s.dir,
      offer: f.offer,
    );
    if (location != f.location) {
      f.location = location;
      await _repo.updateFile(s.rowId, f.offer.fileId, tempPath: location);
    }
    return part;
  }

  Future<Response> _complete(Request req, String sid, String fid) async {
    final found = _lookup(req, sid, fid);
    if (found == null) return _notFound();
    final (s, f) = found;
    final gate = _sessionGate(s) ?? _fileGate(f);
    if (gate != null) return gate;
    if (f.busy) {
      return _error(409, ErrorCodes.busy, 'upload still in progress');
    }
    final CompleteRequest body;
    try {
      body = CompleteRequest.fromJson(
        await _readJson(req, _limits.maxControlBodyBytes),
      );
    } on _BodyTooLarge {
      return _error(413, ErrorCodes.bodyTooLarge, 'body too large');
    } on FormatError catch (e) {
      return _error(400, ErrorCodes.badRequest, e.message);
    }
    if (f.busy) {
      return _error(409, ErrorCodes.busy, 'upload still in progress');
    }
    f.lock();
    try {
      final size = f.offer.size;
      if (size == 0) await (await _openPart(s, f)).close();
      final received = await _store.length(f.location);
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
      final digest = f.digest ?? await _hashPart(s, f);
      if (s.status.isTerminal) return _sessionGate(s)!;
      if (digest != body.sha256) return await _hashMismatch(s, f);

      final SaveResult saved;
      try {
        saved = await _store.save(f.location, f.offer);
      } on Exception catch (e) {
        f.status = FileTransferStatus.receiving;
        await _repo.updateFile(
          s.rowId,
          fid,
          status: FileTransferStatus.receiving,
        );
        await _pauseIfIdle(s, except: f);
        final full =
            e is StoreFull || (e is FileSystemException && _isNoSpace(e));
        final code = full ? ErrorCodes.noSpace : ErrorCodes.ioError;
        _log('file $fid: save failed ($code)');
        _broadcast(s, ErrorEvent(code, fileId: fid));
        return _error(507, code, 'could not save file');
      }
      final dest = saved.location;
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
      final note = saved.fallback == null ? '' : ', ${saved.fallback}';
      _log(
        'file $fid: verified and saved '
        '($size bytes, ${saved.collection.name}$note)',
      );
      _events.add(
        FileSaved(
          s.id,
          fid,
          dest,
          size,
          collection: saved.collection,
          fallback: saved.fallback,
        ),
      );
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
    final part = await _openPart(s, f);
    try {
      await part.truncate(0);
      await part.sync();
    } finally {
      await part.close();
    }
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
    await _store.delete(f.location);
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
      await _discardParts(s);
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

  /// Deletes the partial files of every file not saved, then the session
  /// folder. MediaStore parts live outside the folder (D-040).
  Future<void> _discardParts(_Session s) async {
    for (final f in s.files.values) {
      if (f.status != FileTransferStatus.saved) await _store.delete(f.location);
    }
    await _deleteDir(s.dir);
  }

  static Future<void> _deleteDir(String dir) async {
    try {
      await Directory(dir).delete(recursive: true);
    } on FileSystemException {
      // Not created yet, or already gone.
    }
  }

  /// SHA-256 of the part on disk, after an app restart lost the running
  /// hash.
  Future<String> _hashPart(_Session s, _ReceivingFile f) async {
    final part = await _openPart(s, f);
    try {
      final hasher = await Sha256Isolate.spawn();
      await hasher.addSourcePrefix(part.source, f.offer.size);
      return await hasher.close();
    } finally {
      await part.close();
    }
  }

  /// Reads at most [maxBytes]; throws [_BodyTooLarge] beyond that, and
  /// [FormatError] if it is not JSON.
  static Future<Object?> _readJson(Request req, int maxBytes) async {
    final declared = req.contentLength;
    if (declared != null && declared > maxBytes) throw const _BodyTooLarge();
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in req.read()) {
      bytes.add(chunk);
      if (bytes.length > maxBytes) throw const _BodyTooLarge();
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

class _BodyTooLarge implements Exception {
  const _BodyTooLarge();
}
