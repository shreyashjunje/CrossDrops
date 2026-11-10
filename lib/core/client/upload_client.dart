import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../engine/chunked_reader.dart';
import '../log.dart';
import '../engine/sha256_isolate.dart';
import '../engine/speed_meter.dart';
import '../protocol/auth_messages.dart';
import '../protocol/events.dart';
import '../protocol/models.dart';
import '../security/device_credentials.dart';
import '../security/peer_auth.dart';
import '../security/pinning.dart';

class TransferProgress {
  const TransferProgress({
    required this.sentBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
  });

  final int sentBytes;
  final int totalBytes;

  /// Moving average over the last 3 seconds.
  final double bytesPerSecond;

  double get fraction => totalBytes == 0 ? 1 : sentBytes / totalBytes;
}

class UploadException implements Exception {
  const UploadException(
    this.code,
    this.message, {
    this.statusCode,
    this.details = const {},
  });

  /// One of [ErrorCodes], or `network` / `stalled` / `cancelled` /
  /// `bad_response` / `pin_mismatch`.
  final String code;
  final String message;
  final int? statusCode;

  /// The receiver's whole error body (`receivedBytes`, `retry`, ...).
  final Map<String, Object?> details;

  bool get isCancelled => code == 'cancelled';

  @override
  String toString() => 'UploadException($code, $statusCode): $message';
}

/// A file offered to the receiver; pass it to [UploadClient.transfer] to
/// send it, and again to resume after an interruption.
class UploadTarget {
  UploadTarget({
    required this.sessionId,
    required this.fileId,
    required this.size,
    String path = '',
    ByteSource? source,
    this.treeHash = false,
  }) : source = source ?? PathSource(path);

  final String sessionId;
  final String fileId;

  /// Where the bytes come from: a file path or an Android descriptor.
  final ByteSource source;
  final int size;

  /// The receiver checks this file by its tree hash (D-071): only for a
  /// receiver whose info says `treeHash`.
  final bool treeHash;
}

/// Largest JSON reply the client reads from the receiver (audit S9).
const int maxReplyBytes = 1024 * 1024;

/// Largest event message the client accepts before closing the socket.
const int maxEventChars = 64 * 1024;

/// The receiver's event WebSocket for one session.
class EventConnection {
  EventConnection._(this._ws)
    : events = _ws
          .where((m) {
            if (m is! String) return false;
            if (m.length <= maxEventChars) return true;
            // A receiver that floods us is not one we keep listening to.
            unawaited(_ws.close(WebSocketStatus.messageTooBig));
            return false;
          })
          .map((m) {
            try {
              return SessionEvent.fromJson(jsonDecode(m as String));
            } on FormatException {
              return null;
            } on FormatError {
              return null;
            }
          })
          .where((e) => e != null)
          .cast<SessionEvent>();

  final WebSocket _ws;

  /// Ends when the socket closes. Bad or unknown messages are skipped.
  final Stream<SessionEvent> events;

  Future<void> close() async {
    try {
      await _ws.close().timeout(const Duration(seconds: 2));
    } on Object {
      // Peer gone.
    }
  }
}

/// The receiver's certificate is not the pinned one. Never retried.
const String pinMismatchCode = 'pin_mismatch';

/// HTTPS client for the sender side (protocol v1).
///
/// Every connection is pinned to [fingerprint] (the receiver's identity
/// from a QR code, a trusted-device record or the first contact). Before
/// the first request that needs it, the client proves its own identity
/// with [credentials] (`/v1/auth`, D-027).
class UploadClient {
  UploadClient({
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.credentials,
    this.connectTimeout = const Duration(seconds: 10),
    this.stallTimeout = const Duration(seconds: 15),
    this.chunkSize = defaultChunkSize,
  }) : _inWorker = false {
    _http = _newHttpClient();
  }

  /// The client inside an upload worker isolate (D-071): it sends one
  /// upload with the token it was given and never authenticates.
  UploadClient._worker(
    String this._token, {
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.connectTimeout,
    required this.stallTimeout,
    required this.chunkSize,
  }) : credentials = null,
       _inWorker = true {
    _http = _newHttpClient();
  }

  final String host;
  final int port;

  /// The receiver's certificate fingerprint.
  final String fingerprint;

  /// Null only inside an upload worker.
  final DeviceCredentials? credentials;
  final bool _inWorker;

  /// Uploads below this go the plain way: an isolate and a new connection
  /// cost more than they save on a photo.
  static const int fastMinBytes = 8 * 1024 * 1024;

  /// One file is spread over several connections only from this size.
  static const int stripedMinBytes = 32 * 1024 * 1024;

  /// Uploads running in worker isolates for this client.
  final Set<_WorkerUpload> _workers = {};

  /// An upload that makes no progress for this long is aborted
  /// (ARCHITECTURE.md, "Wi-Fi drops mid-transfer"). Also the response
  /// timeout for control requests.
  final Duration stallTimeout;
  final Duration connectTimeout;

  /// Bytes read and written per step of an upload. 1 MB by default; the
  /// benchmark compares 256 KB, 1 MB and 4 MB (docs/BENCHMARKS.md).
  final int chunkSize;
  late HttpClient _http;
  HttpClientRequest? _active;
  Completer<Never>? _abort;
  bool _cancelled = false;
  bool _pauseRequested = false;
  bool _pinMismatch = false;
  String? _token;
  Future<String>? _authenticating;
  String? _pairingCode;

  /// The 6-digit code of the latest authentication; the receiver shows the
  /// same one for offers made after it. Null before authenticating.
  String? get pairingCode => _pairingCode;

  /// The receiver's bearer token for this sender, once authenticated.
  String? get token => _token;

  /// Starts with a token another client to the same receiver already has,
  /// so parallel uploads (D-068) do not each authenticate. If the
  /// receiver refuses it, this client authenticates on its own.
  void adoptToken(String? token) => _token ??= token;

  HttpClient _newHttpClient() => pinnedHttpClient(
    fingerprint: fingerprint,
    connectTimeout: connectTimeout,
    onMismatch: () => _pinMismatch = true,
  );

  /// Maps a connection error to an [UploadException]; a pin mismatch gets
  /// its own code so the app can warn instead of retrying.
  UploadException _networkError(Object e) {
    if (_pinMismatch || e is PinMismatchException) {
      return const UploadException(
        pinMismatchCode,
        'This is not the device you expected.',
      );
    }
    return UploadException('network', e.toString());
  }

  Uri _url(String path, [Map<String, String>? query]) => Uri(
    scheme: 'https',
    host: host,
    port: port,
    path: path,
    queryParameters: query,
  );

  /// `GET /v1/info`: who is listening at [host]:[port]. Needs no token.
  Future<DeviceInfo> info() async =>
      DeviceInfo.fromJson(await _requestJson('GET', '/v1/info', auth: false));

  /// Authenticates now if there is no token yet. Concurrent callers share
  /// one attempt.
  Future<String> _ensureToken() {
    final token = _token;
    if (token != null) return Future.value(token);
    return _authenticating ??= _authenticate().whenComplete(
      () => _authenticating = null,
    );
  }

  Future<String> _authenticate() async {
    final credentials = this.credentials;
    if (credentials == null) {
      // A worker's token ran out: the session's client gets a new one.
      throw const UploadException(ErrorCodes.authRequired, 'token expired');
    }
    final senderNonce = newNonce();
    final challenge = AuthChallenge.fromJson(
      await _requestJson(
        'POST',
        '/v1/auth/challenge',
        body: AuthChallengeRequest(
          commit: authCommitment(
            receiverFingerprint: fingerprint,
            senderFingerprint: credentials.fingerprint,
            senderNonce: senderNonce,
          ),
        ).toJson(),
        auth: false,
      ),
    );
    final signature = credentials.sign(
      authSigningInput(
        receiverFingerprint: fingerprint,
        senderFingerprint: credentials.fingerprint,
        receiverNonce: challenge.nonce,
        senderNonce: senderNonce,
      ),
    );
    final granted = AuthGranted.fromJson(
      await _requestJson(
        'POST',
        '/v1/auth',
        body: AuthRequest(
          certificate: credentials.certificateDer,
          nonce: challenge.nonce,
          senderNonce: senderNonce,
          signature: signature,
        ).toJson(),
        auth: false,
      ),
    );
    _pairingCode = derivePairingCode(
      senderFingerprint: credentials.fingerprint,
      receiverFingerprint: fingerprint,
      senderNonce: senderNonce,
      receiverNonce: challenge.nonce,
    );
    _token = granted.token;
    return granted.token;
  }

  /// `POST /v1/sessions`. The session starts as `offered`; wait for the
  /// `accepted` event before sending bytes.
  Future<SessionCreated> offer(SessionOffer offer) async =>
      SessionCreated.fromJson(
        await _requestJson('POST', '/v1/sessions', body: offer.toJson()),
      );

  /// `GET /v1/sessions/{id}`.
  Future<SessionStatusReply> sessionStatus(String sessionId) async =>
      SessionStatusReply.fromJson(
        await _requestJson('GET', '/v1/sessions/$sessionId'),
      );

  /// `DELETE /v1/sessions/{id}`: cancel from the sender's side.
  Future<SessionStatusReply> cancelSession(String sessionId) async =>
      SessionStatusReply.fromJson(
        await _requestJson('DELETE', '/v1/sessions/$sessionId'),
      );

  /// Opens `WS /v1/sessions/{id}/events`.
  Future<EventConnection> openEvents(String sessionId) async {
    final url = _url('/v1/sessions/$sessionId/events').replace(scheme: 'wss');
    try {
      final token = await _ensureToken();
      final ws = await WebSocket.connect(
        url.toString(),
        headers: {'authorization': 'Bearer $token'},
        customClient: _http,
      ).timeout(connectTimeout);
      ws.pingInterval = const Duration(seconds: 10);
      return EventConnection._(ws);
    } on UploadException {
      rethrow;
    } on TimeoutException {
      throw const UploadException('network', 'event socket timed out');
    } on WebSocketException catch (e) {
      // A 401 on the upgrade: the token expired; the next call re-auths.
      if (e.message.contains('401')) _token = null;
      throw _pinMismatch
          ? _networkError(e)
          : UploadException('network', e.message);
    } on Exception catch (e) {
      // Socket, TLS handshake and HTTP errors.
      throw _pinMismatch
          ? _networkError(e)
          : UploadException('network', e.runtimeType.toString());
    }
  }

  /// Offers one file, waits until the receiver accepts, and returns its
  /// upload target. For tools and tests; the app uses SendSession.
  Future<UploadTarget> offerFile(
    String path, {
    String? name,
    SenderInfo sender = const SenderInfo(
      id: 'phase1',
      name: 'CrossDrop',
      platform: 'unknown',
    ),
    Duration acceptTimeout = const Duration(seconds: 75),
    DeviceInfo? receiver,
  }) async {
    final size = await File(path).length();
    const fileId = 'f1';
    final created = await offer(
      SessionOffer(
        sender: sender,
        files: [
          FileOffer(fileId: fileId, name: name ?? p.basename(path), size: size),
        ],
      ),
    );
    final deadline = DateTime.now().add(acceptTimeout);
    while (true) {
      final s = await sessionStatus(created.sessionId);
      if (s.status == SessionStatus.offered) {
        if (DateTime.now().isAfter(deadline)) {
          throw const UploadException('timeout', 'no answer from receiver');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }
      if (s.status.isTerminal) {
        throw UploadException(
          ErrorCodes.sessionClosed,
          'receiver answered ${s.status.name}',
          details: {'status': s.status.name, 'reason': s.reason},
        );
      }
      break;
    }
    return UploadTarget(
      sessionId: created.sessionId,
      fileId: fileId,
      path: path,
      size: size,
      treeHash: receiver?.treeHash ?? false,
    );
  }

  Future<FileStatus> fileStatus(UploadTarget t) async =>
      FileStatus.fromJson(await _requestJson('GET', _filePath(t)));

  /// Sends the file from wherever the receiver stopped, then asks it to
  /// verify the SHA-256 and save. Use the same call to resume.
  ///
  /// [hash] is the whole file's hash, running in the background; pass the
  /// same one again when resuming so the file is not hashed twice.
  /// Returns the SHA-256 of the whole file. With [receiver] (its info),
  /// a large file goes the fast way if the receiver offers it ([putFast]).
  Future<String> transfer(
    UploadTarget t, {
    void Function(TransferProgress)? onProgress,
    BackgroundFileHash? hash,
    DeviceInfo? receiver,
  }) async {
    _cancelled = false;
    final ownHash = hash == null;
    final h =
        hash ??
        BackgroundFileHash.startSource(t.source, t.size, tree: t.treeHash);
    try {
      for (var attempt = 1; ; attempt++) {
        final status = await fileStatus(t);
        if (status.status == FileTransferStatus.saved.name) {
          throw const UploadException(
            ErrorCodes.alreadySaved,
            'receiver already has this file',
          );
        }
        if (status.status == FileTransferStatus.failed.name) {
          throw const UploadException(ErrorCodes.fileFailed, 'file failed');
        }
        if (status.receivedBytes == t.size) break;
        try {
          final ports = receiver?.dataPorts ?? const <int>[];
          if (ports.isNotEmpty &&
              t.size - status.receivedBytes >= fastMinBytes) {
            await putFast(
              t,
              status.receivedBytes,
              dataPorts: ports,
              stripes: receiver!.stripes,
              onProgress: onProgress,
            );
          } else {
            await put(t, status.receivedBytes, onProgress: onProgress);
          }
          break;
        } on UploadException catch (e) {
          // A previous, interrupted PUT may still be finishing on the server,
          // or the token expired (put re-authenticates on the next call).
          final retry =
              e.code == ErrorCodes.busy ||
              e.code == ErrorCodes.offsetMismatch ||
              e.code == ErrorCodes.authRequired;
          if (!retry || attempt >= 5) rethrow;
          await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
        }
      }
      final sha = await h.digest;
      await complete(t, sha);
      return sha;
    } finally {
      if (ownHash) await h.abort();
    }
  }

  /// `POST .../complete` with the file's SHA-256.
  ///
  /// Throws [UploadException] with `hash_mismatch` (details `retry: true`:
  /// the receiver restarted the file from zero) or `file_failed`.
  Future<void> complete(UploadTarget t, String sha) async {
    await _requestJson(
      'POST',
      '${_filePath(t)}/complete',
      body: CompleteRequest(sha256: sha, tree: t.treeHash).toJson(),
      // After a restart the receiver hashes the whole file from disk.
      // Allow for a slow phone: 2 minutes plus 1 s per 20 MB.
      timeout: Duration(minutes: 2, seconds: t.size ~/ (20 * 1000 * 1000)),
    );
    _log('file ${t.fileId}: verified and saved by receiver');
  }

  /// `PUT .../files/{fileId}?offset=N`: streams bytes [offset, size) and
  /// returns the receiver's status once all of them arrived.
  Future<FileStatus> put(
    UploadTarget t,
    int offset, {
    void Function(TransferProgress)? onProgress,
  }) => _put(t, offset, onProgress: onProgress);

  /// [put] for one connection of a striped upload (D-071): sends only the
  /// blocks of [stripe] and returns the answer for the whole upload, which
  /// comes once every connection has delivered its part.
  Future<FileStatus> putStripe(
    UploadTarget t,
    int offset,
    StripeSpec stripe, {
    void Function(TransferProgress)? onProgress,
  }) => _put(t, offset, stripe: stripe, onProgress: onProgress);

  /// [put] with the TLS work off this isolate (D-071): each connection
  /// runs in its own isolate and goes to one of the receiver's
  /// [dataPorts]. From [stripedMinBytes] the rest of the file is spread
  /// over [stripes] connections. Same errors as [put]; the first
  /// connection to fail ends the others.
  Future<FileStatus> putFast(
    UploadTarget t,
    int offset, {
    required List<int> dataPorts,
    int stripes = 1,
    int lane = 0,
    void Function(TransferProgress)? onProgress,
  }) async {
    _checkCancelled();
    _checkPaused();
    final token = await _ensureToken();
    final count = stripes > 1 && t.size - offset >= stripedMinBytes
        ? stripes
        : 1;
    final meter = SpeedMeter()..add(offset);
    final sent = List.filled(count, 0);
    final uploads = <_WorkerUpload>[];
    final outcome = Completer<FileStatus>();
    try {
      for (var i = 0; i < count; i++) {
        final upload = await _WorkerUpload.start(
          this,
          token,
          dataPorts[(lane + i) % dataPorts.length],
          t,
          offset,
          count == 1 ? null : StripeSpec(index: i, count: count),
          (bytes) {
            sent[i] = bytes - offset;
            final total = offset + sent.fold<int>(0, (a, b) => a + b);
            meter.add(total);
            onProgress?.call(
              TransferProgress(
                sentBytes: total,
                totalBytes: t.size,
                bytesPerSecond: meter.bytesPerSecond,
              ),
            );
          },
        );
        uploads.add(upload);
        _workers.add(upload);
      }
      // Asked while the workers were starting.
      if (_cancelled) {
        for (final u in uploads) {
          u.send('cancel');
        }
      } else if (_pauseRequested) {
        _pauseRequested = false;
        for (final u in uploads) {
          u.send('pause');
        }
      }
      var left = count;
      for (final u in uploads) {
        u.result.future.then(
          (status) {
            if (--left == 0 && !outcome.isCompleted) outcome.complete(status);
          },
          onError: (Object e) {
            if (outcome.isCompleted) return;
            outcome.completeError(e);
            for (final other in uploads) {
              if (!identical(other, u)) other.send('cancel');
            }
          },
        );
      }
      return await outcome.future;
    } on UploadException catch (e) {
      if (e.code == ErrorCodes.authRequired) _token = null;
      rethrow;
    } finally {
      _workers.removeAll(uploads);
      // The next try must not overlap a connection that is still closing.
      await Future.wait([for (final u in uploads) u.stop()]);
    }
  }

  Future<FileStatus> _put(
    UploadTarget t,
    int offset, {
    StripeSpec? stripe,
    void Function(TransferProgress)? onProgress,
  }) async {
    _log(
      'file ${t.fileId}: sending from $offset of ${t.size}'
      '${stripe == null ? '' : ' (part ${stripe.index + 1}/${stripe.count})'}',
    );
    final meter = SpeedMeter()..add(offset);
    var sent = offset;
    // Completes with an error on stall or cancel. Every wait on the socket
    // races against it: a blocked flush on a dead peer never completes.
    final abort = _abort = Completer<Never>();
    Timer? watchdog;
    void kick() {
      watchdog?.cancel();
      watchdog = Timer(stallTimeout, () => _stop(_stalledError()));
    }

    Future<T> guarded<T>(Future<T> f) => Future.any([f, abort.future]);

    try {
      _checkCancelled();
      _checkPaused();
      final HttpClientResponse res;
      try {
        kick();
        final token = await guarded(_ensureToken());
        final req = await guarded(
          _http.openUrl(
            'PUT',
            _url(_filePath(t), {
              'offset': '$offset',
              if (t.treeHash) 'hash': 'tree',
              ...?stripe?.toQuery(),
            }),
          ),
        );
        _active = req;
        if (_pauseRequested) {
          // Asked while authenticating or connecting: send nothing.
          _pauseRequested = false;
          req.abort(_pausedError);
          throw _pausedError;
        }
        req.headers.set('authorization', 'Bearer $token');
        req.contentLength = stripe?.share(t.size - offset) ?? t.size - offset;
        req.headers.contentType = ContentType.binary;
        // Read ahead: the next chunk is read while this one is flushed, so
        // the disk (or Android's descriptor worker) and the network overlap
        // instead of taking turns (review, speed item 4). At most two
        // chunks are in memory, plus the one in the socket buffer.
        final chunks = StreamIterator(
          readSourceRanges(
            t.source,
            stripe?.ranges(offset, t.size) ?? [(start: offset, end: t.size)],
            chunkSize: chunkSize,
            blocking: _inWorker,
          ),
        );
        var next = chunks.moveNext();
        try {
          while (await guarded(next)) {
            final chunk = chunks.current;
            next = chunks.moveNext();
            req.add(chunk);
            // At most one chunk waits in the socket buffer.
            await guarded(req.flush());
            kick();
            if (_pauseRequested) {
              // The current chunk is out; the receiver keeps every byte.
              _pauseRequested = false;
              req.abort(_pausedError);
              throw _pausedError;
            }
            sent += chunk.length;
            meter.add(sent);
            onProgress?.call(
              TransferProgress(
                sentBytes: sent,
                totalBytes: t.size,
                bytesPerSecond: meter.bytesPerSecond,
              ),
            );
          }
        } finally {
          // A read still running when the upload stops must not surface
          // as an uncaught error.
          next.ignore();
          await chunks.cancel();
        }
        // Waits for the receiver's response headers, still guarded.
        res = await guarded(req.close());
      } on UploadException {
        rethrow;
      } on FileSystemException catch (e) {
        // The source file, not the network.
        throw UploadException('source_unreadable', e.message);
      } on Exception catch (e) {
        _checkCancelled();
        throw _networkError(e);
      } on StateError {
        // The socket closed between two chunks: "Cannot add event after
        // closing".
        _checkCancelled();
        throw const UploadException('network', 'connection closed');
      } finally {
        watchdog?.cancel();
        _active = null;
        _abort = null;
      }
      final status = FileStatus.fromJson(await _decodeAuthed(res));
      if (status.receivedBytes != t.size) {
        throw UploadException(
          ErrorCodes.incomplete,
          'receiver has ${status.receivedBytes} of ${t.size} bytes',
          details: {'receivedBytes': status.receivedBytes},
        );
      }
      return status;
    } catch (e) {
      // Error code or type only: messages can contain file paths.
      final reason = e is UploadException ? e.code : e.runtimeType;
      _log('file ${t.fileId}: stopped at $sent bytes ($reason)');
      rethrow;
    }
  }

  /// Stops the running upload after its current chunk with code `paused`
  /// (app going to the background). Asked while no upload runs (between
  /// files, while connecting or authenticating), it is kept, and the next
  /// [put] stops before sending a byte (review M4). Each request stops one
  /// upload; [clearPause] drops one no upload has seen.
  void requestPause() {
    if (_workers.isEmpty) {
      _pauseRequested = true;
    } else {
      for (final w in _workers) {
        w.send('pause');
      }
    }
  }

  /// Forgets a pause request (the app came back before any upload saw it).
  void clearPause() => _pauseRequested = false;

  static const _pausedError = UploadException('paused', 'paused by app');

  void _checkPaused() {
    if (!_pauseRequested) return;
    _pauseRequested = false;
    throw _pausedError;
  }

  /// Aborts the running upload. Bytes already received stay on the
  /// receiver; call [transfer] again to resume.
  void cancel() {
    _cancelled = true;
    for (final w in _workers) {
      w.send('cancel');
    }
    _stop(const UploadException('cancelled', 'cancelled by user'));
  }

  /// Fails the running upload with [reason] and destroys its socket.
  /// The HttpClient is replaced because aborting a request does not free a
  /// socket whose peer is gone.
  void _stop(UploadException reason) {
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.completeError(reason);
    _active?.abort(reason);
    _http.close(force: true);
    _http = _newHttpClient();
  }

  void close() {
    for (final w in _workers) {
      w.send('cancel');
    }
    _http.close(force: true);
  }

  UploadException _stalledError() =>
      UploadException('stalled', 'no progress for ${stallTimeout.inSeconds} s');

  void _checkCancelled() {
    if (_cancelled) {
      throw const UploadException('cancelled', 'cancelled by user');
    }
  }

  String _filePath(UploadTarget t) =>
      '/v1/sessions/${t.sessionId}/files/${t.fileId}';

  /// One JSON request. With [auth], sends the token and, if the receiver
  /// no longer knows it (restart, expiry), authenticates once more and
  /// retries.
  Future<Map<String, Object?>> _requestJson(
    String method,
    String path, {
    Object? body,
    Duration? timeout,
    bool auth = true,
  }) async {
    Future<Map<String, Object?>> run() async {
      final token = auth ? await _ensureToken() : null;
      final req = await _http.openUrl(method, _url(path));
      if (token != null) req.headers.set('authorization', 'Bearer $token');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(body)));
      }
      return auth
          ? _decodeAuthed(await req.close())
          : _decode(await req.close());
    }

    Future<Map<String, Object?>> attempt() async {
      try {
        return await run().timeout(timeout ?? stallTimeout);
      } on UploadException {
        rethrow;
      } on TimeoutException {
        throw _pinMismatch
            ? _networkError(const UploadException('network', 'timeout'))
            : const UploadException('network', 'no response from receiver');
      } on Exception catch (e) {
        throw _networkError(e);
      }
    }

    try {
      return await attempt();
    } on UploadException catch (e) {
      if (!auth || e.code != ErrorCodes.authRequired) rethrow;
      return attempt();
    }
  }

  /// [_decode], and forgets the token when the receiver refuses it.
  Future<Map<String, Object?>> _decodeAuthed(HttpClientResponse res) async {
    try {
      return await _decode(res);
    } on UploadException catch (e) {
      if (e.code == ErrorCodes.authRequired) _token = null;
      rethrow;
    }
  }

  static Future<Map<String, Object?>> _decode(HttpClientResponse res) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in res) {
      bytes.add(chunk);
      if (bytes.length > maxReplyBytes) {
        throw UploadException(
          'bad_response',
          'response too large',
          statusCode: res.statusCode,
        );
      }
    }
    final text = utf8.decode(bytes.takeBytes(), allowMalformed: true);
    Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      json = null;
    }
    if (json is! Map<String, Object?>) {
      throw UploadException(
        'bad_response',
        'unexpected response',
        statusCode: res.statusCode,
      );
    }
    if (res.statusCode != 200) {
      final code = json['error'];
      final message = json['message'];
      throw UploadException(
        code is String ? code : 'http_${res.statusCode}',
        message is String ? message : '',
        statusCode: res.statusCode,
        details: json,
      );
    }
    return json;
  }

  static void _log(String message) => logEvent('client', message);
}

/// One connection of a fast upload, running [UploadClient._put] in its own
/// isolate (D-071).
class _WorkerUpload {
  _WorkerUpload._(this._isolate, this._exited);

  final Isolate _isolate;
  final Future<void> _exited;
  final Completer<FileStatus> result = Completer();
  SendPort? _control;
  final List<String> _early = [];

  static Future<_WorkerUpload> start(
    UploadClient client,
    String token,
    int port,
    UploadTarget t,
    int offset,
    StripeSpec? stripe,
    void Function(int sentBytes) onSent,
  ) async {
    final fromWorker = ReceivePort();
    final exit = ReceivePort();
    final isolate = await Isolate.spawn(
      _uploadWorker,
      [
        fromWorker.sendPort,
        client.host,
        port,
        client.fingerprint,
        token,
        client.connectTimeout,
        client.stallTimeout,
        client.chunkSize,
        t.sessionId,
        t.fileId,
        t.source,
        t.size,
        offset,
        stripe?.index,
        stripe?.count,
        stripe?.block,
        t.treeHash,
      ],
      debugName: 'upload',
      onExit: exit.sendPort,
    );
    final exited = exit.first.then<void>((_) {
      exit.close();
      fromWorker.close();
    });
    final upload = _WorkerUpload._(isolate, exited);
    // The answer was lost with the worker: the next try asks the receiver.
    upload.result.future.ignore();
    unawaited(
      exited.then((_) {
        if (!upload.result.isCompleted) {
          upload.result.completeError(
            const UploadException('network', 'upload worker stopped'),
          );
        }
      }),
    );
    fromWorker.listen((m) {
      switch (m) {
        case final SendPort control:
          upload._control = control;
          upload._early.forEach(control.send);
          upload._early.clear();
        case final int sentBytes:
          onSent(sentBytes);
        case ['ok', final Object? json]:
          upload.result.complete(FileStatus.fromJson(json));
        case [
          'error',
          final String code,
          final String message,
          final int? status,
          final Map<Object?, Object?> details,
        ]:
          upload.result.completeError(
            UploadException(
              code,
              message,
              statusCode: status,
              details: details.cast<String, Object?>(),
            ),
          );
      }
    });
    return upload;
  }

  /// `pause` or `cancel`, as [UploadClient.requestPause] and
  /// [UploadClient.cancel].
  void send(String command) {
    final control = _control;
    control == null ? _early.add(command) : control.send(command);
  }

  /// Completes when the worker is gone, ending it if it still runs.
  Future<void> stop() {
    if (!result.isCompleted) send('cancel');
    return _exited.timeout(
      const Duration(seconds: 5),
      onTimeout: () => _isolate.kill(priority: Isolate.immediate),
    );
  }
}

Future<void> _uploadWorker(List<Object?> a) async {
  final toMain = a[0]! as SendPort;
  final client = UploadClient._worker(
    a[4]! as String,
    host: a[1]! as String,
    port: a[2]! as int,
    fingerprint: a[3]! as String,
    connectTimeout: a[5]! as Duration,
    stallTimeout: a[6]! as Duration,
    chunkSize: a[7]! as int,
  );
  final control = ReceivePort()
    ..listen((m) => m == 'pause' ? client.requestPause() : client.cancel());
  toMain.send(control.sendPort);
  final index = a[13] as int?;
  try {
    final status = await client._put(
      UploadTarget(
        sessionId: a[8]! as String,
        fileId: a[9]! as String,
        source: a[10]! as ByteSource,
        size: a[11]! as int,
        treeHash: a[16]! as bool,
      ),
      a[12]! as int,
      stripe: index == null
          ? null
          : StripeSpec(
              index: index,
              count: a[14]! as int,
              block: a[15]! as int,
            ),
      onProgress: (p) => toMain.send(p.sentBytes),
    );
    toMain.send(['ok', status.toJson()]);
  } on UploadException catch (e) {
    toMain.send(['error', e.code, e.message, e.statusCode, e.details]);
  } on Object catch (e) {
    toMain.send(['error', 'network', '${e.runtimeType}', null, const {}]);
  } finally {
    client.close();
    control.close();
  }
}
