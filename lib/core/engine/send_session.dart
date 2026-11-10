import 'dart:async';

import '../client/upload_client.dart';
import '../log.dart';
import '../media/thumb_ref.dart';
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

  /// The user gave up an unfinished send (Discard, or a new selection
  /// that released its files). Stored with status `cancelled`.
  static const discarded = 'discarded';
}

/// Gives up a stored, unfinished send for good: marks it `cancelled`
/// ([SendReasons.discarded]) so neither History nor the launch prompt
/// offers a Resume, then tells the receiver (best effort, short
/// timeouts). The receiver deletes its partial files and frees this
/// phone's slot; without that, the next send to it gets `sender_busy`
/// until its session expires.
Future<void> discardStoredSend(
  TransferRepository repo,
  StoredSession s, {
  required DeviceCredentials credentials,
  ClientFactory? clientFactory,
}) async {
  if (s.direction != TransferDirection.send || s.status.isTerminal) return;
  await repo.updateSession(
    s.rowId,
    status: SessionStatus.cancelled,
    reason: SendReasons.discarded,
  );
  final host = s.peerHost;
  final port = s.peerPort;
  final fingerprint = s.peerFingerprint;
  if (host == null || port == null || fingerprint == null) return;
  final client =
      clientFactory?.call(host, port) ??
      UploadClient(
        host: host,
        port: port,
        fingerprint: fingerprint,
        credentials: credentials,
        connectTimeout: const Duration(seconds: 3),
        stallTimeout: const Duration(seconds: 3),
      );
  try {
    await client.cancelSession(s.sessionId);
  } on UploadException {
    // The receiver expires it after 24 hours anyway.
  } finally {
    client.close();
  }
  logEvent('send', 'session ${s.sessionId}: discarded');
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
    this.thumb,
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

  /// Where the screens get its preview: the library item it came from, or
  /// the file itself. Never sent, never stored.
  final ThumbRef? thumb;
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

/// One upload lane (D-068): lane 0 uses the session's own client, the
/// others their own connection to the same receiver.
class _Lane {
  _Lane(this.own);

  /// Null for lane 0.
  UploadClient? own;

  /// Set while a PUT runs on this lane; completes when it stops.
  Completer<void>? uploading;

  /// Back from a pause: the time away doesn't count against the deadline.
  bool resumed = false;
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

/// Sends files to one receiver, up to [SendSession.parallelUploads] at
/// once, each on its own connection, as many as the receiver takes
/// (ARCHITECTURE.md, "Transfer rules" 4, D-068), resuming after drops.
class SendSession {
  SendSession({
    required String host,
    required int port,
    required this.sender,
    required List<SendItem> items,
    required this.receiverFingerprint,
    required DeviceCredentials credentials,
    this.expectedDeviceId,
    this.receiverTrusted = false,
    TransferRepository? repository,
    PeerLocator? locate,
    ClientFactory? clientFactory,
    Backoff Function()? backoff,
    SourceOpener? opener,
    this.acceptTimeout = const Duration(seconds: 75),
    this.pollInterval = const Duration(seconds: 2),
    this.parallelUploads = defaultParallelUploads,
    int chunkSize = defaultChunkSize,
  }) : assert(parallelUploads >= 1),
       _host = host,
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
    int parallelUploads = defaultParallelUploads,
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
      parallelUploads: parallelUploads,
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

  /// Whether this phone already trusts the receiver. The code is shown
  /// unless it does and the receiver trusts this phone too.
  final bool receiverTrusted;
  final Duration acceptTimeout;
  final Duration pollInterval;

  /// Files sent at the same time, at most; cut to the receiver's
  /// uploadSlots (1 for older receivers).
  final int parallelUploads;

  /// Small photos gain the most: each file costs a few round trips
  /// (status, upload, verify) that run side by side (D-068).
  static const int defaultParallelUploads = 3;

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
  bool _running = false;

  /// Lanes the receiver allows, from its info; 1 until known.
  int _slots = 1;

  /// The receiver's ports for large uploads and the connections it takes
  /// per file, from its info (D-071). Emptied when they keep failing.
  List<int> _dataPorts = const [];
  int _stripes = 1;

  /// Files are checked by their tree hash, if the receiver can (D-071).
  bool _treeHash = false;

  /// Large uploads running now. One alone is spread over [_stripes]
  /// connections; several side by side already use as many.
  int _largeUploads = 0;
  final List<_Lane> _lanes = [];

  /// The first outcome a lane reached; the other lanes stop with it.
  _Stop? _halt;
  Future<void>? _eventsOpening;
  Future<void>? _relocating;

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
      await _sendAll();
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
      for (final l in _lanes) {
        l.own?.close();
      }
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
    for (final l in _lanes) {
      l.own?.cancel();
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
      for (final c in _clients) {
        c.requestPause();
      }
      _emit(SendPhase.paused, force: true);
    }
    return Future.wait([
      for (final l in _lanes)
        if (l.uploading case final u?) u.future,
    ]);
  }

  /// Back in the foreground: continue where the receiver stopped.
  void resume() {
    final gate = _pauseGate;
    if (gate == null) return;
    _pauseGate = null;
    for (final l in _lanes) {
      l.resumed = true;
    }
    // A pause no upload saw would stop the next one for nothing.
    for (final c in _clients) {
      c.clearPause();
    }
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
    _slots = _slotsFor(info);
    _peer = SenderInfo(id: info.id, name: info.name, platform: info.platform);
    if (!await _allSourcesIntact()) {
      throw const _Stop(SendPhase.failed, SendReasons.sourceUnreadable);
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
    // Hidden only when both phones already trust each other: a receiver
    // (or a man in the middle) saying "trusted" is not enough (audit S13).
    _pairingCode = created.trusted && receiverTrusted
        ? null
        : _client.pairingCode;
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
        _slots = _slotsFor(info);
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

  /// Sends every unfinished file, [_slots] at a time; each lane takes the
  /// next file in offer order. The first lane to reach an outcome (a
  /// cancel, the receiver gone, no space, ...) stops the others with it.
  Future<void> _sendAll() async {
    final queue = [
      for (final f in _files)
        if (!f.status.isTerminal) f,
    ];
    if (queue.isEmpty) return;
    final count = _slots < queue.length ? _slots : queue.length;
    _lanes
      ..clear()
      ..add(_Lane(null));
    for (var i = 1; i < count; i++) {
      _lanes.add(_Lane(_laneClient()));
    }
    if (_pauseGate != null) {
      for (final l in _lanes) {
        l.own?.requestPause();
      }
    }
    if (count > 1) _log('sending $count files at once');
    var next = 0;
    Object? error;
    StackTrace? trace;
    Future<void> drive(_Lane lane) async {
      while (_halt == null && error == null && next < queue.length) {
        final f = queue[next++];
        try {
          await _sendFile(f, lane);
        } on _Stop catch (stop) {
          _haltLanes(stop, except: lane);
          return;
        } catch (e, st) {
          error = e;
          trace = st;
          _haltLanes(const _Stop(SendPhase.failed, 'error'), except: lane);
          return;
        }
      }
    }

    await Future.wait([for (final l in _lanes) drive(l)]);
    if (error case final e?) Error.throwWithStackTrace(e, trace!);
    if (_halt case final h?) throw h;
  }

  /// Ends the other lanes with [stop]: wakes the waiting ones and breaks
  /// the uploads that run.
  void _haltLanes(_Stop stop, {required _Lane except}) {
    if (_halt != null) return;
    _halt = stop;
    _wake();
    for (final l in _lanes) {
      if (!identical(l, except)) _clientOf(l).cancel();
    }
  }

  UploadClient _clientOf(_Lane lane) => lane.own ?? _client;

  /// The session's client and every lane's.
  List<UploadClient> get _clients => [_client, for (final l in _lanes) ?l.own];

  /// A connection for another lane, reusing the session's token.
  UploadClient _laneClient() =>
      _clientFactory(_host, _port)..adoptToken(_client.token);

  int _slotsFor(DeviceInfo info) {
    _dataPorts = info.dataPorts;
    _stripes = info.stripes;
    _treeHash = info.treeHash;
    final n = info.uploadSlots < parallelUploads
        ? info.uploadSlots
        : parallelUploads;
    return n < 1 ? 1 : n;
  }

  Future<void> _sendFile(_File f, _Lane lane) async {
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
      treeHash: _treeHash,
    );
    final hash = _hashes[f.fileId] ??= BackgroundFileHash.startSource(
      opened.source,
      f.item.size,
      tree: _treeHash,
    );
    final backoff = _newBackoff();
    var deadPortTries = 0;
    while (true) {
      await _waitWhilePaused();
      _checkStop();
      if (lane.resumed) {
        // Time in the background doesn't count against the deadline.
        lane.resumed = false;
        backoff.reset();
      }
      // Fresh each round: a retry replaces the lane's client.
      final client = _clientOf(lane);
      try {
        final status = await client.fileStatus(target);
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
          final uploading = lane.uploading = Completer<void>();
          final from = status.receivedBytes;
          // Large uploads go to the receiver's data ports, with the TLS
          // work off this isolate on both phones (D-071).
          final fast =
              _dataPorts.isNotEmpty &&
              f.item.size - from >= UploadClient.fastMinBytes;
          var moved = false;
          void onProgress(TransferProgress p) {
            moved = moved || p.sentBytes > from;
            _tracker.set(f.fileId, p.sentBytes);
            // The last chunks before a pause takes effect stay paused.
            _emit(_pauseGate == null ? SendPhase.sending : SendPhase.paused);
          }

          if (fast) _largeUploads++;
          try {
            if (fast) {
              await client.putFast(
                target,
                from,
                dataPorts: _dataPorts,
                stripes: _largeUploads == 1 ? _stripes : 1,
                lane: _lanes.indexOf(lane),
                onProgress: onProgress,
              );
            } else {
              await client.put(target, from, onProgress: onProgress);
            }
          } on UploadException catch (e) {
            // The main port just answered, and a data port twice took not
            // one byte: it is gone (iOS can reclaim a listening socket).
            // The rest of the session uses the main port.
            if (fast && !moved && _isTransient(e) && ++deadPortTries >= 2) {
              _log('data ports do not answer, using the main port');
              _dataPorts = const [];
            }
            rethrow;
          } finally {
            if (fast) _largeUploads--;
            lane.uploading = null;
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
        await client.complete(target, sha);
        return await _fileEnded(f, FileTransferStatus.saved);
      } on UploadException catch (e) {
        switch (e.code) {
          case 'paused':
            continue;
          case 'cancelled':
            // Another lane's outcome, or a cancel from either side.
            _checkStop();
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
        await _retryWait(backoff, lane: lane);
      } on FormatError {
        await _retryWait(backoff, lane: lane);
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
  Future<void> _retryWait(
    Backoff backoff, {
    int relocateAfter = 3,
    _Lane? lane,
  }) async {
    final delay = backoff.next();
    if (delay == null) {
      throw const _Stop(SendPhase.failed, SendReasons.network);
    }
    _retryIn = delay;
    _emit(SendPhase.retrying, force: true);
    await Future.any([Future<void>.delayed(delay), _stopSignal.future]);
    _retryIn = null;
    _checkStop();
    if (backoff.attempts >= relocateAfter) {
      // Lanes that fail together ask discovery once.
      await (_relocating ??= _relocate().whenComplete(
        () => _relocating = null,
      ));
    }
    // A new client: the old one may hold a socket to a dead peer.
    final own = lane?.own;
    if (lane == null || own == null) {
      _client.close();
      _client = _clientFactory(_host, _port);
    } else {
      own.close();
      final fresh = lane.own = _laneClient();
      if (_pauseGate != null) fresh.requestPause();
    }
    if (_events == null && _decision?.isCompleted == true) {
      await (_eventsOpening ??= _openEvents().whenComplete(
        () => _eventsOpening = null,
      ));
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
        for (final c in _clients) {
          c.cancel();
        }
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

  /// [_sourceIntact] for every file, a few at a time: on Android each is
  /// a round trip to the content provider.
  Future<bool> _allSourcesIntact() async {
    var next = 0;
    var ok = true;
    Future<void> worker() async {
      while (ok && next < _files.length) {
        if (!await _sourceIntact(_files[next++])) ok = false;
      }
    }

    await Future.wait([
      for (var i = 0; i < 4 && i < _files.length; i++) worker(),
    ]);
    return ok;
  }

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
    if (_halt case final h?) throw h;
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
