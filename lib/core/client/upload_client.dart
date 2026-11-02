import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../engine/chunked_reader.dart';
import '../log.dart';
import '../engine/sha256_isolate.dart';
import '../engine/speed_meter.dart';
import '../protocol/events.dart';
import '../protocol/models.dart';

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
  /// `bad_response`.
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
  const UploadTarget({
    required this.sessionId,
    required this.fileId,
    required this.path,
    required this.size,
  });

  final String sessionId;
  final String fileId;
  final String path;
  final int size;
}

/// The receiver's event WebSocket for one session.
class EventConnection {
  EventConnection._(this._ws)
    : events = _ws
          .where((m) => m is String)
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

/// HTTPS client for the sender side (protocol v1).
class UploadClient {
  UploadClient({
    required this.host,
    required this.port,
    this.connectTimeout = const Duration(seconds: 10),
    this.stallTimeout = const Duration(seconds: 15),
  }) {
    _http = _newHttpClient();
  }

  final String host;
  final int port;

  /// An upload that makes no progress for this long is aborted
  /// (ARCHITECTURE.md, "Wi-Fi drops mid-transfer"). Also the response
  /// timeout for control requests.
  final Duration stallTimeout;
  final Duration connectTimeout;
  late HttpClient _http;
  HttpClientRequest? _active;
  Completer<Never>? _abort;
  bool _cancelled = false;

  // TODO(phase4): remove. This accepts ANY server certificate (no pinning,
  // no client certificate), so it gives encryption but no protection from a
  // man in the middle. Phase 4 replaces it with mutual TLS pinned to the
  // receiver's fingerprint, with no fallback (CLAUDE.md hard rule 4).
  HttpClient _newHttpClient() =>
      HttpClient(context: SecurityContext(withTrustedRoots: false))
        ..connectionTimeout = connectTimeout
        ..badCertificateCallback = ((_, _, _) => true);

  Uri _url(String path, [Map<String, String>? query]) => Uri(
    scheme: 'https',
    host: host,
    port: port,
    path: path,
    queryParameters: query,
  );

  /// `GET /v1/info`: who is listening at [host]:[port].
  Future<DeviceInfo> info() async =>
      DeviceInfo.fromJson(await _requestJson('GET', '/v1/info'));

  /// `POST /v1/sessions`. The session starts as `offered`; wait for the
  /// `accepted` event before sending bytes.
  Future<SessionCreated> offer(SessionOffer offer) async =>
      SessionCreated.fromJson(
        await _requestJson('POST', '/v1/sessions', offer.toJson()),
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
      final ws = await WebSocket.connect(
        url.toString(),
        customClient: _http,
      ).timeout(connectTimeout);
      ws.pingInterval = const Duration(seconds: 10);
      return EventConnection._(ws);
    } on TimeoutException {
      throw const UploadException('network', 'event socket timed out');
    } on WebSocketException catch (e) {
      throw UploadException('network', e.message);
    } on SocketException catch (e) {
      throw UploadException('network', e.message);
    } on HttpException catch (e) {
      throw UploadException('network', e.message);
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
    );
  }

  Future<FileStatus> fileStatus(UploadTarget t) async =>
      FileStatus.fromJson(await _requestJson('GET', _filePath(t)));

  /// Sends the file from wherever the receiver stopped, then asks it to
  /// verify the SHA-256 and save. Use the same call to resume.
  ///
  /// [hash] is the whole file's hash, running in the background; pass the
  /// same one again when resuming so the file is not hashed twice.
  /// Returns the SHA-256 of the whole file.
  Future<String> transfer(
    UploadTarget t, {
    void Function(TransferProgress)? onProgress,
    BackgroundFileHash? hash,
  }) async {
    _cancelled = false;
    final ownHash = hash == null;
    final h = hash ?? BackgroundFileHash.start(t.path, t.size);
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
          await put(t, status.receivedBytes, onProgress: onProgress);
          break;
        } on UploadException catch (e) {
          // A previous, interrupted PUT may still be finishing on the server.
          final retry =
              e.code == ErrorCodes.busy || e.code == ErrorCodes.offsetMismatch;
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
      CompleteRequest(sha256: sha).toJson(),
      // After a restart the receiver hashes the whole file from disk.
      // Allow for a slow phone: 2 minutes plus 1 s per 20 MB.
      Duration(minutes: 2, seconds: t.size ~/ (20 * 1000 * 1000)),
    );
    _log('file ${t.fileId}: verified and saved by receiver');
  }

  /// `PUT .../files/{fileId}?offset=N`: streams bytes [offset, size) and
  /// returns the receiver's status once all of them arrived.
  Future<FileStatus> put(
    UploadTarget t,
    int offset, {
    void Function(TransferProgress)? onProgress,
  }) async {
    _log('file ${t.fileId}: sending from $offset of ${t.size}');
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
      final HttpClientResponse res;
      try {
        kick();
        final req = await guarded(
          _http.openUrl('PUT', _url(_filePath(t), {'offset': '$offset'})),
        );
        _active = req;
        req.contentLength = t.size - offset;
        req.headers.contentType = ContentType.binary;
        await for (final chunk in readFileChunks(
          t.path,
          start: offset,
          end: t.size,
        )) {
          req.add(chunk);
          // At most one chunk waits in the socket buffer.
          await guarded(req.flush());
          kick();
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
        // Waits for the receiver's response headers, still guarded.
        res = await guarded(req.close());
      } on UploadException {
        rethrow;
      } on FileSystemException catch (e) {
        // The source file, not the network.
        throw UploadException('source_unreadable', e.message);
      } on Exception catch (e) {
        _checkCancelled();
        throw UploadException('network', e.toString());
      } finally {
        watchdog?.cancel();
        _active = null;
        _abort = null;
      }
      final status = FileStatus.fromJson(await _decode(res));
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

  /// Aborts the running upload. Bytes already received stay on the
  /// receiver; call [transfer] again to resume.
  void cancel() {
    _cancelled = true;
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

  void close() => _http.close(force: true);

  UploadException _stalledError() =>
      UploadException('stalled', 'no progress for ${stallTimeout.inSeconds} s');

  void _checkCancelled() {
    if (_cancelled) {
      throw const UploadException('cancelled', 'cancelled by user');
    }
  }

  String _filePath(UploadTarget t) =>
      '/v1/sessions/${t.sessionId}/files/${t.fileId}';

  Future<Map<String, Object?>> _requestJson(
    String method,
    String path, [
    Object? body,
    Duration? timeout,
  ]) async {
    Future<Map<String, Object?>> run() async {
      final req = await _http.openUrl(method, _url(path));
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(body)));
      }
      return _decode(await req.close());
    }

    try {
      return await run().timeout(timeout ?? stallTimeout);
    } on UploadException {
      rethrow;
    } on TimeoutException {
      throw const UploadException('network', 'no response from receiver');
    } on Exception catch (e) {
      throw UploadException('network', e.toString());
    }
  }

  static Future<Map<String, Object?>> _decode(HttpClientResponse res) async {
    final text = await res.transform(utf8.decoder).join();
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
