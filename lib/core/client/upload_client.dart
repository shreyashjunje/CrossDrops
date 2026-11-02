import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../engine/chunked_reader.dart';
import '../log.dart';
import '../engine/sha256_isolate.dart';
import '../engine/speed_meter.dart';
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
  const UploadException(this.code, this.message, {this.statusCode});

  /// One of [ErrorCodes], or `network` / `cancelled` / `bad_response`.
  final String code;
  final String message;
  final int? statusCode;

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

/// HTTPS client for the sender side (protocol v1, Phase 1 subset).
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

  /// Offers one file and returns its upload target.
  Future<UploadTarget> offerFile(
    String path, {
    String? name,
    SenderInfo sender = const SenderInfo(
      id: 'phase1',
      name: 'CrossDrop',
      platform: 'unknown',
    ),
  }) async {
    final size = await File(path).length();
    const fileId = 'f1';
    final offer = SessionOffer(
      sender: sender,
      files: [
        FileOffer(fileId: fileId, name: name ?? p.basename(path), size: size),
      ],
    );
    final body = await _requestJson('POST', '/v1/sessions', offer.toJson());
    final created = SessionCreated.fromJson(body);
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
  /// Returns the SHA-256 of the whole file.
  Future<String> transfer(
    UploadTarget t, {
    void Function(TransferProgress)? onProgress,
  }) async {
    _cancelled = false;
    String? sha;
    for (var attempt = 1; sha == null; attempt++) {
      final status = await fileStatus(t);
      if (status.status == 'saved') {
        throw const UploadException(
          ErrorCodes.alreadySaved,
          'receiver already has this file',
        );
      }
      try {
        sha = await _put(t, status.receivedBytes, onProgress);
      } on UploadException catch (e) {
        // A previous, interrupted PUT may still be finishing on the server.
        final retry =
            e.code == ErrorCodes.busy || e.code == ErrorCodes.offsetMismatch;
        if (!retry || attempt >= 5) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
      }
    }
    await _requestJson(
      'POST',
      '${_filePath(t)}/complete',
      CompleteRequest(sha256: sha).toJson(),
      // The receiver may have to hash the whole file from disk.
      const Duration(minutes: 2),
    );
    _log('file ${t.fileId}: verified and saved by receiver');
    return sha;
  }

  Future<String> _put(
    UploadTarget t,
    int offset,
    void Function(TransferProgress)? onProgress,
  ) async {
    _log('file ${t.fileId}: sending from $offset of ${t.size}');
    final hasher = await Sha256Isolate.spawn();
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
      // Rebuild the hash of bytes the receiver already has, from disk.
      await hasher.addFilePrefix(t.path, offset);
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
          await guarded(hasher.add(chunk));
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
      } on Exception catch (e) {
        _checkCancelled();
        throw UploadException('network', e.toString());
      } finally {
        watchdog?.cancel();
        _active = null;
        _abort = null;
      }
      final json = await _decode(res);
      final status = FileStatus.fromJson(json);
      if (status.receivedBytes != t.size) {
        throw UploadException(
          ErrorCodes.incomplete,
          'receiver has ${status.receivedBytes} of ${t.size} bytes',
        );
      }
      return await hasher.close();
    } catch (e) {
      hasher.abort();
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
      throw UploadException(
        json['error'] as String? ?? 'http_${res.statusCode}',
        json['message'] as String? ?? '',
        statusCode: res.statusCode,
      );
    }
    return json;
  }

  static void _log(String message) => logEvent('client', message);
}
