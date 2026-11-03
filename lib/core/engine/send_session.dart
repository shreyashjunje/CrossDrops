import 'dart:async';

import '../client/upload_client.dart';
import '../log.dart';
import '../protocol/events.dart';
import '../protocol/models.dart';
import '../security/device_credentials.dart';
import '../storage/transfer_repository.dart';
import 'backoff.dart';
import 'chunked_reader.dart';
import 'progress_tracker.dart';
import 'sha256_isolate.dart';
import 'source_opener.dart';

enum SendPhase {
  connecting,
  waitingForAccept,
  sending,

  /// Connection lost; waiting [SendSnapshot.retryIn] before trying again.
  retrying,

  /// The app is in the background (iOS); continues on [SendSession.resume].
  paused,
  done,
  rejected,
  cancelled,
  failed;

  bool get isFinished =>
      this == done || this == rejected || this == cancelled || this == failed;
}

/// Why a send stopped, beyond the protocol's own codes.
abstract final class SendReasons {
  /// No common protocol version.
  static const version = 'version';

  /// A different device answered at the address.
  static const identityMismatch = 'identity_mismatch';

  /// Gave up after about 2 minutes without progress. Resumable.
  static const network = 'network';

  /// The receiver never answered the offer.
  static const timeout = 'timeout';

  /// The file to send is gone or changed size.
  static const sourceUnreadable = 'source_unreadable';

  /// The receiver no longer knows the session (expired or wiped).
  static const sessionLost = 'session_lost';

  /// The receiver's certificate is not the pinned one. Never retried
  /// (CLAUDE.md hard rule 4).
  static const pinMismatch = 'pin_mismatch';
}

/// A file to send.
class SendItem {
  const SendItem({
    required this.path,
    required this.name,
    required this.size,
    this.mime,
    this.kind = FileKind.file,
    this.created,
    this.livePhotoGroup,
  });

  /// A file path, or a `content://` URI on Android, opened by the
  /// session's [SourceOpener].
  final String path;
  final String name;
  final int size;
  final String? mime;
  final String kind;
  final DateTime? created;

  /// Same value on a Live Photo's still and video (ARCHITECTURE.md,
  /// "Offer manifest").
  final String? livePhotoGroup;
}

class SendFileProgress {
  const SendFileProgress({
    required this.fileId,
    required this.name,
    required this.size,
    required this.sentBytes,
    required this.status,
    this.error,
  });

  final String fileId;
  final String name;
  final int size;
  final int sentBytes;
  final FileTransferStatus status;
  final String? error;
}

/// What the Send screen shows.
class SendSnapshot {
  const SendSnapshot({
    required this.phase,
    required this.files,
    required this.totalBytes,
    required this.sentBytes,
    this.sessionId,
    this.reason,
    this.neededBytes,
    this.bytesPerSecond = 0,
    this.eta,
    this.retryIn,
    this.pairingCode,
  });

  final SendPhase phase;
  final String? sessionId;

  /// The 6-digit code to show while the receiver decides, when it does
  /// not trust this phone yet (ARCHITECTURE.md, "Pairing").
  final String? pairingCode;

  /// One of [SendReasons], [RejectReasons] or [ErrorCodes].
  final String? reason;

  /// For a no-space rejection.
  final int? neededBytes;
  final List<SendFileProgress> files;
  final int totalBytes;
  final int sentBytes;
  final double bytesPerSecond;
  final Duration? eta;
  final Duration? retryIn;

  double get fraction => totalBytes == 0 ? 1 : sentBytes / totalBytes;

  int get savedCount =>
      files.where((f) => f.status == FileTransferStatus.saved).length;

  int get failedCount =>
      files.where((f) => f.status == FileTransferStatus.failed).length;

  /// A later run of the same session can pick up from here.
  bool get canResume =>
      sessionId != null &&
      phase == SendPhase.failed &&
      (reason == SendReasons.network || reason == ErrorCodes.noSpace);
}

typedef ClientFactory = UploadClient Function(String host, int port);

/// Finds the receiver again (by device id, through discovery) when its
/// address stops answering. Null if it can't be found.
typedef PeerLocator = Future<({String host, int port})?> Function();

/// Ends [SendSession.run] with an outcome.
class _Stop implements Exception {
  const _Stop(this.phase, [this.reason, this.neededBytes]);
  final SendPhase phase;
  final String? reason;
  final int? neededBytes;
}

class _File {
  _File(this.fileId, this.item);

  final String fileId;
  final SendItem item;
  FileTransferStatus status = FileTransferStatus.pending;
  String? error;

  /// Bytes the receiver confirmed.
  int confirmed = 0;
}

/// Sends files to one receiver, one after another over one connection
/// (ARCHITECTURE.md, "Transfer rules" 4), resuming after drops.
class SendSession {
  SendSession({
    required String host,
    required int port,
    required this.sender,
    required List<SendItem> items,
    required this.receiverFingerprint,
    required DeviceCredentials credentials,
    this.expectedDeviceId,
    TransferRepository? repository,
    PeerLocator? locate,
    ClientFactory? clientFactory,
    Backoff Function()? backoff,
    SourceOpener? opener,
    this.acceptTimeout = const Duration(seconds: 75),
    this.pollInterval = const Duration(seconds: 2),
    int chunkSize = defaultChunkSize,
  }) : _host = host,
       _port = port,
       _repo = repository,
       _locator = locate,
       _clientFactory =
           clientFactory ??
           ((h, p) => UploadClient(
             host: h,
             port: p,
             fingerprint: receiverFingerprint,
             credentials: credentials,
             chunkSize: chunkSize,
           )),
       _newBackoff = backoff ?? Backoff.new,
       _opener = opener ?? const FileSourceOpener(),
       _files = [for (final (i, item) in items.indexed) _File('f$i', item)] {
    _client = _clientFactory(host, port);
    _tracker = ProgressTracker({for (final f in _files) f.fileId: f.item.size});
  }

  /// Continues a session stored by an earlier run (app restart). Throws
  /// [StateError] for a session stored without the receiver's fingerprint
  /// (before Phase 4): it cannot be resumed safely.
  factory SendSession.resume(
    StoredSession stored, {
    required SenderInfo sender,
    required DeviceCredentials credentials,
    TransferRepository? repository,
    PeerLocator? locate,
    ClientFactory? clientFactory,
    Backoff Function()? backoff,
    SourceOpener? opener,
  }) {
    final fingerprint = stored.peerFingerprint;
    if (fingerprint == null) {
      throw StateError('stored without a receiver fingerprint');
    }
    final s = SendSession(
      host: stored.peerHost ?? '',
      port: stored.peerPort ?? 0,
      sender: sender,
      receiverFingerprint: fingerprint,
      credentials: credentials,
      expectedDeviceId: stored.peer.id,
      items: [
        for (final f in stored.files)
          SendItem(
            path: f.sourcePath ?? '',
            name: f.name,
            size: f.size,
            mime: f.mime,
            kind: f.kind,
            created: f.created,
            livePhotoGroup: f.livePhotoGroup,
          ),
      ],
      repository: repository,
      locate: locate,
      clientFactory: clientFactory,
      backoff: backoff,
      opener: opener,
    );
    s._sessionId = stored.sessionId;
    s._rowId = stored.rowId;
    s._peer = stored.peer;
    for (final (i, f) in stored.files.indexed) {
      final file = s._files[i] = _File(f.fileId, s._files[i].item);
      file.status = f.status;
      file.confirmed = f.transferredBytes;
      s._tracker.set(
        f.fileId,
        f.status == FileTransferStatus.saved ? f.size : f.transferredBytes,
      );
    }
    return s;
  }

  final SenderInfo sender;

  /// Every connection to the receiver is pinned to this.
  final String receiverFingerprint;

  /// The receiver's device id, if known (nearby list, QR code, stored).
  final String? expectedDeviceId;
  final Duration acceptTimeout;
  final Duration pollInterval;

  String _host;
  int _port;
  final TransferRepository? _repo;
  final PeerLocator? _locator;
  final ClientFactory _clientFactory;
  final Backoff Function() _newBackoff;
  final List<_File> _files;
  late UploadClient _client;
  late final ProgressTracker _tracker;
  final Map<String, BackgroundFileHash> _hashes = {};

  /// Sources open for the file being sent, closed when it ends.
  final Map<String, OpenedSource> _opened = {};
  final SourceOpener _opener;
  final StreamController<SendSnapshot> _updates = StreamController.broadcast();
  EventConnection? _events;
  StreamSubscription<SessionEvent>? _eventSub;

  String? _sessionId;
  int? _rowId;
  SenderInfo? _peer;
  String? _pairingCode;
  SendPhase _phase = SendPhase.connecting;
  String? _reason;
  int? _neededBytes;
  Duration? _retryIn;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  Completer<SessionEvent>? _decision;
  final Completer<void> _stopSignal = Completer<void>();
  bool _localCancel = false;
  bool _remoteCancel = false;
  Completer<void>? _pauseGate;
  bool _resumedFromPause = false;
  bool _running = false;

  /// Set while a PUT runs; completes when it stops.
  Completer<void>? _uploading;

  /// `POST /v1/sessions` is on its way; a cancel waits for it briefly.
  bool _offering = false;
  Timer? _offerCancel;

  Stream<SendSnapshot> get updates => _updates.stream;

  String? get sessionId => _sessionId;

  SendSnapshot get snapshot => SendSnapshot(
    phase: _phase,
    sessionId: _sessionId,
    reason: _reason,
    neededBytes: _neededBytes,
    files: [
      for (final f in _files)
        SendFileProgress(
          fileId: f.fileId,
          name: f.item.name,
          size: f.item.size,
          sentBytes: _tracker.bytesOf(f.fileId),
          status: f.status,
          error: f.error,
        ),
    ],
    totalBytes: _tracker.totalBytes,
    sentBytes: _tracker.doneBytes,
    bytesPerSecond: _phase == SendPhase.sending ? _tracker.bytesPerSecond : 0,
    eta: _phase == SendPhase.sending ? _tracker.eta : null,
    retryIn: _retryIn,
    pairingCode: _pairingCode,
  );

  /// Runs until the session is done, rejected, cancelled or failed.
  /// Call once.
  Future<SendSnapshot> run() async {
    if (_running) throw StateError('already running');
    _running = true;
    try {
      if (_sessionId == null) {
        await _offer();
      } else {
        await _reattach();
      }
      await _waitForAccept();
      await _setStored(SessionStatus.transferring);
      for (final f in _files) {
        if (f.status.isTerminal) continue;
        await _sendFile(f);
      }
      final anySaved = _files.any((f) => f.status == FileTransferStatus.saved);
      await _finish(
        anySaved ? SendPhase.done : SendPhase.failed,
        anySaved ? null : ErrorCodes.fileFailed,
      );
    } on _Stop catch (s) {
      await _finish(s.phase, s.reason, s.neededBytes);
    } on Exception catch (e) {
      logEvent('send', 'unexpected error: ${e.runtimeType}');
      await _finish(SendPhase.failed, 'error');
    } finally {
      await _eventSub?.cancel();
      await _events?.close();
      for (final h in _hashes.values) {
        await h.abort();
      }
      // After the hashers: they read the same descriptors.
      for (final o in _opened.values) {
        await o.close();
      }
      _opened.clear();
      _client.close();
    }
    return snapshot;
  }

  /// Cancels from this side: stops sending and tells the receiver, which
  /// deletes its partial files.
  Future<void> cancel() async {
    if (_phase.isFinished || _localCancel) return;
    _localCancel = true;
    _wake();
    final decision = _decision;
    if (decision != null && !decision.isCompleted) {
      decision.complete(const CancelledEvent('sender'));
    }
    if (_offering) {
      // Let an offer on its way finish, so _offer can withdraw it instead
      // of leaving it on the receiver (review M5); not for long on a dead
      // network.
      _offerCancel = Timer(const Duration(seconds: 3), _client.cancel);
    } else {
      _client.cancel();
    }
    final sid = _sessionId;
    if (sid != null) {
      final c = _clientFactory(_host, _port);
      try {
        await c.cancelSession(sid);
      } on UploadException catch (e) {
        // The receiver learns on its own when it can't reach us.
        _log('cancel not delivered (${e.code})');
      } finally {
        c.close();
      }
    }
  }

  /// The app goes to the background, or the user tapped Pause: stop after
  /// the current chunk. Completes once no upload is running, so an iOS
  /// background task knows when bytes have stopped (review M4).
  Future<void> pause() {
    if (_phase.isFinished) return Future<void>.value();
    if (_pauseGate == null) {
      _pauseGate = Completer<void>();
      _client.requestPause();
      _emit(SendPhase.paused, force: true);
    }
    return _uploading?.future ?? Future<void>.value();
  }

  /// Back in the foreground: continue where the receiver stopped.
  void resume() {
    final gate = _pauseGate;
    if (gate == null) return;
    _pauseGate = null;
    _resumedFromPause = true;
    // A pause no upload saw would stop the next one for nothing.
    _client.clearPause();
    gate.complete();
  }

  // ------------------------------------------------------------ the steps

  Future<void> _offer() async {
    _emit(SendPhase.connecting, force: true);
    final DeviceInfo info;
    try {
      info = await _client.info();
    } on UploadException catch (e) {
      // A cancel kills the connection: that is a cancel, not "network".
      _checkStop();
      throw _Stop(SendPhase.failed, e.code);
    } on FormatError {
      _checkStop();
      throw const _Stop(SendPhase.failed, 'bad_response');
    }
    if (negotiateVersion(info.versions) == null) {
      throw const _Stop(SendPhase.failed, SendReasons.version);
    }
    final expected = expectedDeviceId;
    if (expected != null && info.id != expected) {
      throw const _Stop(SendPhase.failed, SendReasons.identityMismatch);
    }
    _peer = SenderInfo(id: info.id, name: info.name, platform: info.platform);
    for (final f in _files) {
      if (!await _sourceIntact(f)) {
        throw const _Stop(SendPhase.failed, SendReasons.sourceUnreadable);
      }
    }
    _checkStop();
    final SessionCreated created;
    _offering = true;
    try {
      created = await _client.offer(
        SessionOffer(
          sender: sender,
          files: [
            for (final f in _files)
              FileOffer(
                fileId: f.fileId,
                name: f.item.name,
                size: f.item.size,
                mime: f.item.mime,
                kind: f.item.kind,
                created: f.item.created,
                livePhotoGroup: f.item.livePhotoGroup,
              ),
          ],
        ),
      );
    } on UploadException catch (e) {
      _checkStop();
      // Not retried: a lost reply could leave a duplicate offer behind.
      throw switch (e.code) {
        ErrorCodes.noSpace => _Stop(
          SendPhase.rejected,
          RejectReasons.noSpace,
          e.details['neededBytes'] as int?,
        ),
        ErrorCodes.senderBusy => const _Stop(
          SendPhase.rejected,
          RejectReasons.senderBusy,
        ),
        ErrorCodes.unsupportedVersion => const _Stop(
          SendPhase.failed,
          SendReasons.version,
        ),
        ErrorCodes.receivingOff => const _Stop(
          SendPhase.rejected,
          ErrorCodes.receivingOff,
        ),
        _ => _Stop(SendPhase.failed, e.code),
      };
    } finally {
      _offering = false;
      _offerCancel?.cancel();
      _offerCancel = null;
    }
    _sessionId = created.sessionId;
    if (_localCancel) {
      // Cancelled while the offer was on its way: withdraw it, or the
      // receiver keeps it and, if accepted, waits for bytes (review M5).
      _log('session ${created.sessionId}: cancelled while offering');
      await _cancelRemote();
      throw const _Stop(SendPhase.cancelled, 'sender');
    }
    // The receiver shows the code of the authentication behind this offer.
    _pairingCode = created.trusted ? null : _client.pairingCode;
    _log('session ${created.sessionId}: offered ${_files.length} file(s)');
    final repo = _repo;
    if (repo != null) {
      _rowId = await repo.createSession(
        sessionId: created.sessionId,
        direction: TransferDirection.send,
        peer: _peer!,
        status: SessionStatus.offered,
        peerHost: _host,
        peerPort: _port,
        peerFingerprint: receiverFingerprint,
        files: [
          for (final f in _files)
            StoredFile(
              fileId: f.fileId,
              name: f.item.name,
              size: f.item.size,
              mime: f.item.mime,
              kind: f.item.kind,
              created: f.item.created,
              livePhotoGroup: f.item.livePhotoGroup,
              status: FileTransferStatus.pending,
              sourcePath: f.item.path,
            ),
        ],
      );
    }
  }

  /// A stored session: find the receiver and ask where it stands.
  Future<void> _reattach() async {
    _emit(SendPhase.connecting, force: true);
    final backoff = _newBackoff();
    while (true) {
      _checkStop();
      try {
        final info = await _client.info();
        final expected = expectedDeviceId;
        if (expected != null && info.id != expected) {
          throw const UploadException(
            SendReasons.identityMismatch,
            'another device at this address',
          );
        }
        return;
      } on UploadException catch (e) {
        if (!_isTransient(e) && e.code != SendReasons.identityMismatch) {
          _checkStop();
          throw _Stop(SendPhase.failed, e.code);
        }
        await _retryWait(backoff, relocateAfter: 1);
      } on FormatError {
        await _retryWait(backoff, relocateAfter: 1);
      }
    }
  }

  Future<void> _waitForAccept() async {
    final sid = _sessionId!;
    _emit(SendPhase.waitingForAccept, force: true);
    final decision = _decision = Completer<SessionEvent>();
    await _openEvents();
    final deadline = DateTime.now().add(acceptTimeout);
    while (!decision.isCompleted) {
      _checkStop();
      try {
        final s = await _client.sessionStatus(sid);
        final e = _eventFor(s);
        if (e != null && !decision.isCompleted) decision.complete(e);
      } on UploadException catch (e) {
        if (e.code == ErrorCodes.notFound) {
          throw const _Stop(SendPhase.failed, SendReasons.sessionLost);
        }
        // Keep waiting; the events socket may still deliver the answer.
      } on FormatError {
        // Same.
      }
      if (decision.isCompleted) break;
      if (DateTime.now().isAfter(deadline)) {
        throw const _Stop(SendPhase.failed, SendReasons.timeout);
      }
      await Future.any([
        decision.future,
        Future<void>.delayed(pollInterval),
        _stopSignal.future,
      ]);
    }
    final answer = await decision.future;
    switch (answer) {
      case AcceptedEvent():
        _log('session $sid: accepted');
      case RejectedEvent(:final reason, :final neededBytes):
        throw _Stop(SendPhase.rejected, reason, neededBytes);
      case CancelledEvent(:final by):
        throw _Stop(SendPhase.cancelled, by);
      case ErrorEvent(:final code):
        throw _Stop(SendPhase.failed, code);
      default:
        throw const _Stop(SendPhase.failed, 'error');
    }
  }

  /// The decision a session status implies, if any.
  static SessionEvent? _eventFor(SessionStatusReply s) => switch (s.status) {
    SessionStatus.offered => null,
    SessionStatus.rejected => RejectedEvent(s.reason ?? 'declined'),
    SessionStatus.cancelled => CancelledEvent(s.reason ?? 'receiver'),
    SessionStatus.failed => ErrorEvent(s.reason ?? 'error'),
    _ => const AcceptedEvent(),
  };

  Future<void> _sendFile(_File f) async {
    final opened = await _openFor(f);
    if (opened == null) {
      await _cancelRemote();
      throw const _Stop(SendPhase.failed, SendReasons.sourceUnreadable);
    }
    final target = UploadTarget(
      sessionId: _sessionId!,
      fileId: f.fileId,
      source: opened.source,
      size: f.item.size,
    );
    final hash = _hashes[f.fileId] ??= BackgroundFileHash.startSource(
      opened.source,
      f.item.size,
    );
    final backoff = _newBackoff();
    while (true) {
      await _waitWhilePaused();
      _checkStop();
      if (_resumedFromPause) {
        // Time in the background doesn't count against the deadline.
        _resumedFromPause = false;
        backoff.reset();
      }
      try {
        final status = await _client.fileStatus(target);
        if (status.status == FileTransferStatus.saved.name) {
          return await _fileEnded(f, FileTransferStatus.saved);
        }
        if (status.status == FileTransferStatus.failed.name) {
          return await _fileEnded(
            f,
            FileTransferStatus.failed,
            ErrorCodes.fileFailed,
          );
        }
        if (status.receivedBytes > f.confirmed) backoff.reset();
        await _confirm(f, status.receivedBytes);
        if (status.receivedBytes < f.item.size) {
          // Paused during the requests above: wait before sending a byte.
          if (_pauseGate != null) continue;
          f.status = FileTransferStatus.receiving;
          _emit(SendPhase.sending, force: true);
          final uploading = _uploading = Completer<void>();
          try {
            await _client.put(
              target,
              status.receivedBytes,
              onProgress: (p) {
                _tracker.set(f.fileId, p.sentBytes);
                // The last chunks before a pause takes effect stay paused.
                _emit(
                  _pauseGate == null ? SendPhase.sending : SendPhase.paused,
                );
              },
            );
          } finally {
            _uploading = null;
            uploading.complete();
          }
          await _confirm(f, f.item.size);
        }
        f.status = FileTransferStatus.verifying;
        _emit(SendPhase.sending, force: true);
        final String sha;
        try {
          sha = await hash.digest;
        } catch (_) {
          await _cancelRemote();
          throw const _Stop(SendPhase.failed, SendReasons.sourceUnreadable);
        }
        await _client.complete(target, sha);
        return await _fileEnded(f, FileTransferStatus.saved);
      } on UploadException catch (e) {
        switch (e.code) {
          case 'paused':
            continue;
          case 'cancelled':
            throw _Stop(
              SendPhase.cancelled,
              _remoteCancel ? 'receiver' : 'sender',
            );
          case ErrorCodes.sessionClosed:
            throw await _closedOutcome();
          case ErrorCodes.notFound:
            throw const _Stop(SendPhase.failed, SendReasons.sessionLost);
          case ErrorCodes.hashMismatch:
            // The receiver started the file again from zero (once).
            _log('file ${f.fileId}: hash mismatch, sending again');
            f.confirmed = 0;
            _tracker.set(f.fileId, 0);
            continue;
          case ErrorCodes.fileFailed:
          case ErrorCodes.tooManyBytes:
            return await _fileEnded(f, FileTransferStatus.failed, e.code);
          case ErrorCodes.alreadySaved:
            return await _fileEnded(f, FileTransferStatus.saved);
          case ErrorCodes.noSpace:
            throw const _Stop(SendPhase.failed, ErrorCodes.noSpace);
          case 'source_unreadable':
            await _cancelRemote();
            throw const _Stop(SendPhase.failed, SendReasons.sourceUnreadable);
        }
        if (!_isTransient(e)) throw _Stop(SendPhase.failed, e.code);
        _log('file ${f.fileId}: ${e.code}, will retry');
        await _retryWait(backoff);
      } on FormatError {
        await _retryWait(backoff);
      }
    }
  }

  /// Network trouble that a retry can fix.
  static bool _isTransient(UploadException e) =>
      e.code == 'network' ||
      e.code == 'stalled' ||
      e.code == 'bad_response' ||
      e.code == ErrorCodes.busy ||
      e.code == ErrorCodes.offsetMismatch ||
      e.code == ErrorCodes.incomplete ||
      (e.statusCode != null && e.statusCode! >= 500 && e.statusCode != 507);

  /// Waits before the next try, or gives up. After [relocateAfter] failed
  /// tries, asks discovery where the receiver is now (its IP or port may
  /// have changed).
  Future<void> _retryWait(Backoff backoff, {int relocateAfter = 3}) async {
    final delay = backoff.next();
    if (delay == null) {
      throw const _Stop(SendPhase.failed, SendReasons.network);
    }
    _retryIn = delay;
    _emit(SendPhase.retrying, force: true);
    await Future.any([Future<void>.delayed(delay), _stopSignal.future]);
    _retryIn = null;
    _checkStop();
    if (backoff.attempts >= relocateAfter) await _relocate();
    // A new client: the old one may hold a socket to a dead peer.
    _client.close();
    _client = _clientFactory(_host, _port);
    if (_events == null && _decision?.isCompleted == true) {
      await _openEvents();
    }
  }

  Future<void> _relocate() async {
    final locate = _locator;
    if (locate == null) return;
    try {
      final found = await locate();
      if (found == null) return;
      if (found.host != _host || found.port != _port) {
        _log('receiver moved, trying the new address');
        _host = found.host;
        _port = found.port;
        await _events?.close();
        _events = null;
        final row = _rowId;
        if (row != null) {
          await _repo?.updateSession(row, peerHost: _host, peerPort: _port);
        }
      }
    } on Exception catch (e) {
      _log('locating receiver failed: ${e.runtimeType}');
    }
  }

  Future<void> _openEvents() async {
    final sid = _sessionId;
    if (sid == null) return;
    try {
      final conn = _events = await _client.openEvents(sid);
      _eventSub = conn.events.listen(
        _onEvent,
        onDone: () {
          if (_events == conn) _events = null;
        },
        onError: (Object _) {
          if (_events == conn) _events = null;
        },
      );
    } on UploadException {
      // Polling and HTTP replies still carry everything we need.
      _events = null;
    }
  }

  void _onEvent(SessionEvent e) {
    final decision = _decision;
    switch (e) {
      case AcceptedEvent() || RejectedEvent():
        if (decision != null && !decision.isCompleted) decision.complete(e);
      case CancelledEvent(:final by) when by == 'receiver':
        _remoteCancel = true;
        if (decision != null && !decision.isCompleted) decision.complete(e);
        _wake();
        _client.cancel();
      default:
        // progress, file_done and error are confirmed by HTTP replies too.
        break;
    }
  }

  Future<_Stop> _closedOutcome() async {
    try {
      final s = await _clientFactory(_host, _port).sessionStatus(_sessionId!);
      return switch (s.status) {
        SessionStatus.cancelled => _Stop(SendPhase.cancelled, s.reason),
        SessionStatus.rejected => _Stop(SendPhase.rejected, s.reason),
        _ => _Stop(SendPhase.failed, s.reason ?? ErrorCodes.sessionClosed),
      };
    } on Exception {
      return const _Stop(SendPhase.failed, ErrorCodes.sessionClosed);
    }
  }

  Future<void> _cancelRemote() async {
    final sid = _sessionId;
    if (sid == null) return;
    try {
      await _client.cancelSession(sid);
    } on UploadException {
      // Best effort.
    }
  }

  // ------------------------------------------------------------- helpers

  /// The source still exists and has the offered size. Opens and closes
  /// it, so checking 10,000 files never holds 10,000 descriptors.
  Future<bool> _sourceIntact(_File f) async {
    try {
      final o = await _opener.open(f.item.path);
      await o.close();
      return o.length == f.item.size;
    } on SourceUnavailable {
      return false;
    }
  }

  /// The open source for [f], opened once per file. Null if it is gone or
  /// changed size since the offer.
  Future<OpenedSource?> _openFor(_File f) async {
    final open = _opened[f.fileId];
    if (open != null) return open;
    final OpenedSource o;
    try {
      o = await _opener.open(f.item.path);
    } on SourceUnavailable catch (e) {
      _log('file ${f.fileId}: source unavailable (${e.reason})');
      return null;
    }
    if (o.length != f.item.size) {
      await o.close();
      _log('file ${f.fileId}: source changed size');
      return null;
    }
    return _opened[f.fileId] = o;
  }

  Future<void> _confirm(_File f, int bytes) async {
    f.confirmed = bytes;
    _tracker.set(f.fileId, bytes);
    final row = _rowId;
    if (row != null) {
      await _repo?.updateFile(
        row,
        f.fileId,
        transferredBytes: bytes,
        status: FileTransferStatus.receiving,
      );
    }
  }

  Future<void> _fileEnded(
    _File f,
    FileTransferStatus status, [
    String? error,
  ]) async {
    f.status = status;
    f.error = error;
    if (status == FileTransferStatus.saved) {
      _tracker.set(f.fileId, f.item.size);
    } else {
      _tracker.drop(f.fileId);
    }
    await _hashes.remove(f.fileId)?.abort();
    await _opened.remove(f.fileId)?.close();
    _log('file ${f.fileId}: ${status.name}');
    final row = _rowId;
    if (row != null) {
      await _repo?.updateFile(
        row,
        f.fileId,
        status: status,
        errorCode: error,
        transferredBytes: status == FileTransferStatus.saved
            ? f.item.size
            : null,
      );
    }
    _emit(SendPhase.sending, force: true);
  }

  Future<void> _finish(SendPhase phase, String? reason, [int? needed]) async {
    _reason = reason;
    _neededBytes = needed;
    _retryIn = null;
    final stored = switch (phase) {
      SendPhase.done => SessionStatus.done,
      SendPhase.rejected => SessionStatus.rejected,
      SendPhase.cancelled => SessionStatus.cancelled,
      // Resumable failures stay unfinished so a restart offers them.
      SendPhase.failed
          when reason == SendReasons.network || reason == ErrorCodes.noSpace =>
        SessionStatus.paused,
      _ => SessionStatus.failed,
    };
    await _setStored(stored, reason);
    _log('session ${_sessionId ?? '-'}: ${phase.name} (${reason ?? 'ok'})');
    _emit(phase, force: true);
    await _updates.close();
  }

  Future<void> _setStored(SessionStatus status, [String? reason]) async {
    final row = _rowId;
    if (row == null) return;
    await _repo?.updateSession(row, status: status, reason: reason);
  }

  Future<void> _waitWhilePaused() async {
    while (_pauseGate != null) {
      _emit(SendPhase.paused, force: true);
      await Future.any([_pauseGate!.future, _stopSignal.future]);
      _checkStop();
    }
  }

  void _checkStop() {
    if (_localCancel) throw const _Stop(SendPhase.cancelled, 'sender');
    if (_remoteCancel) throw const _Stop(SendPhase.cancelled, 'receiver');
  }

  void _wake() {
    if (!_stopSignal.isCompleted) _stopSignal.complete();
  }

  /// At most about 10 updates per second, except state changes.
  void _emit(SendPhase phase, {bool force = false}) {
    if (_phase.isFinished && phase != _phase) return;
    final now = DateTime.now();
    final changed = phase != _phase;
    _phase = phase;
    if (!force && !changed && now.difference(_lastEmit).inMilliseconds < 100) {
      return;
    }
    _lastEmit = now;
    if (!_updates.isClosed) _updates.add(snapshot);
  }

  static void _log(String message) => logEvent('send', message);
}
