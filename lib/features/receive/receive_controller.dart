import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_dirs.dart';
import '../../app/keep_alive.dart';
import '../../app/media_providers.dart';
import '../../app/providers.dart';
import '../../core/discovery/discovery_service.dart';
import '../../core/discovery/network_monitor.dart';
import '../../core/discovery/subnet.dart';
import '../../core/discovery/txt_record.dart';
import '../../core/engine/progress_tracker.dart';
import '../../core/log.dart';
import '../../core/protocol/connect_payload.dart';
import '../../core/media/save_target.dart';
import '../../core/protocol/models.dart';
import '../../core/security/device_identity.dart';
import '../../core/server/receive_server.dart';
import '../../core/storage/trust_repository.dart';
import '../transfer/transfer_format.dart';
import '../transfer/unfinished_transfers.dart';
import 'session_keep_alive.dart';

class IncomingFile {
  const IncomingFile({
    required this.name,
    required this.size,
    this.kind = FileKind.file,
    this.receivedBytes = 0,
    this.status = FileTransferStatus.pending,
    this.savedPath,
    this.savedTo,
    this.saveFallback,
    this.error,
  });

  final String name;
  final int size;

  /// The offer's [FileKind], for the icon and the preview.
  final String kind;
  final int receivedBytes;
  final FileTransferStatus status;
  final String? savedPath;

  /// Where the user finds it, once saved.
  final SaveCollection? savedTo;

  /// Why a photo or video is not in the gallery ([SaveFallback]).
  final String? saveFallback;
  final String? error;

  IncomingFile copyWith({
    int? receivedBytes,
    FileTransferStatus? status,
    String? savedPath,
    SaveCollection? savedTo,
    String? saveFallback,
    String? error,
  }) => IncomingFile(
    name: name,
    size: size,
    kind: kind,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    status: status ?? this.status,
    savedPath: savedPath ?? this.savedPath,
    savedTo: savedTo ?? this.savedTo,
    saveFallback: saveFallback ?? this.saveFallback,
    error: error ?? this.error,
  );
}

/// One received session, as the transfer screens show it.
class IncomingSession {
  const IncomingSession({
    required this.sessionId,
    required this.sender,
    required this.status,
    required this.files,
    this.reason,
    this.doneBytes = 0,
    this.bytesPerSecond = 0,
    this.eta,
  });

  final String sessionId;
  final SenderInfo sender;
  final SessionStatus status;
  final String? reason;

  /// Keyed by file id, in manifest order.
  final Map<String, IncomingFile> files;
  final int doneBytes;
  final double bytesPerSecond;
  final Duration? eta;

  int get totalBytes => files.values.fold(0, (sum, f) => sum + f.size);

  double get fraction => totalBytes == 0 ? 1 : doneBytes / totalBytes;

  bool get isActive => !status.isTerminal && status != SessionStatus.offered;

  IncomingSession copyWith({
    SessionStatus? status,
    String? reason,
    Map<String, IncomingFile>? files,
    int? doneBytes,
    double? bytesPerSecond,
    Duration? Function()? eta,
  }) => IncomingSession(
    sessionId: sessionId,
    sender: sender,
    status: status ?? this.status,
    reason: reason ?? this.reason,
    files: files ?? this.files,
    doneBytes: doneBytes ?? this.doneBytes,
    bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
    eta: eta != null ? eta() : this.eta,
  );
}

class ReceiveState {
  const ReceiveState({
    this.port,
    this.deviceName,
    this.addresses = const [],
    this.qrPayload,
    this.advertising = false,
    this.advertiseError,
    this.saveDir,
    this.sessions = const {},
    this.pendingOffers = const [],
    this.notice,
    this.error,
    this.receivingOff = false,
  });

  /// Null while the server is starting or stopped.
  final int? port;

  /// The "Receiving" switch is off: nothing listens and nothing is
  /// advertised once running transfers end (D-031).
  final bool receivingOff;
  final String? deviceName;

  /// Addresses other phones may reach (no mobile data or VPN).
  final List<LocalAddress> addresses;

  /// `crossdrop://connect?...` for the QR code; null without a reachable
  /// address. Never log it (CLAUDE.md hard rule 7).
  final String? qrPayload;
  final bool advertising;

  /// Discovery could not start; the QR code still works.
  final String? advertiseError;
  final String? saveDir;

  /// Keyed by session id, oldest first.
  final Map<String, IncomingSession> sessions;

  /// Offers waiting for Accept or Decline, oldest first.
  final List<IncomingOffer> pendingOffers;

  /// A one-off message, such as an offer refused for lack of space.
  final String? notice;
  final String? error;

  bool get isReceiving => sessions.values.any((s) => s.isActive);

  ReceiveState copyWith({
    int? port,
    String? deviceName,
    List<LocalAddress>? addresses,
    String? Function()? qrPayload,
    bool? advertising,
    String? Function()? advertiseError,
    String? saveDir,
    Map<String, IncomingSession>? sessions,
    List<IncomingOffer>? pendingOffers,
    String? Function()? notice,
    String? error,
    bool? receivingOff,
    bool clearPort = false,
  }) => ReceiveState(
    port: clearPort ? null : (port ?? this.port),
    deviceName: deviceName ?? this.deviceName,
    addresses: addresses ?? this.addresses,
    qrPayload: qrPayload != null ? qrPayload() : this.qrPayload,
    advertising: advertising ?? this.advertising,
    advertiseError: advertiseError != null
        ? advertiseError()
        : this.advertiseError,
    saveDir: saveDir ?? this.saveDir,
    sessions: sessions ?? this.sessions,
    pendingOffers: pendingOffers ?? this.pendingOffers,
    notice: notice != null ? notice() : this.notice,
    error: error ?? this.error,
    receivingOff: receivingOff ?? this.receivingOff,
  );
}

final receiveControllerProvider =
    NotifierProvider.autoDispose<ReceiveController, ReceiveState>(
      ReceiveController.new,
    );

/// Runs the receive server while the app is open and the "Receiving"
/// switch is on (D-046), advertises it on the local network, asks the user
/// about each offer and tracks progress. Kept alive by `ReceiveHost` at
/// the app root.
///
/// Turning the switch off stops advertising and refuses offers from
/// untrusted devices at once; the server stops as soon as no transfer is
/// running (D-031). When the app has been hidden for [idleInBackground]
/// with nothing in flight, the server stops too and starts again when the
/// app is back. A new random port is used at every start.
class ReceiveController extends Notifier<ReceiveState> {
  /// How long the app may be hidden, idle, before the server stops.
  static const idleInBackground = Duration(seconds: 30);

  ReceiveServer? _server;
  bool _receivingOn = true;
  bool _starting = false;

  /// Stopped because the app is hidden; starts again when it is shown.
  bool _suspended = false;
  bool _hidden = false;
  Timer? _idleTimer;
  AppLifecycleListener? _visibility;
  final Map<String, IncomingOffer> _offers = {};
  StreamSubscription<ReceiveEvent>? _sub;
  Advertiser? _advertiser;
  NetworkMonitor? _monitor;
  StreamSubscription<List<LocalAddress>>? _networkSub;
  AppLifecycleListener? _lifecycle;
  ConnectPayload Function(LocalAddress)? _payloadFor;
  final Map<String, ProgressTracker> _trackers = {};
  final Map<String, Completer<bool>> _decisions = {};
  DateTime _lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  late KeepAliveCoordinator _keepAlive;

  /// Which sessions are registered with [_keepAlive].
  late final SessionKeepAlive _kept = SessionKeepAlive(
    onBegin: (sid) => unawaited(_beginKeepAlive(sid)),
    onEnd: (sid) => unawaited(_keepAlive.end(sid)),
    onGraceOver: _onPausedGraceOver,
  );

  @override
  ReceiveState build() {
    _keepAlive = ref.read(keepAliveProvider);
    _visibility = AppLifecycleListener(onHide: _onHide, onShow: _onShow);
    ref.onDispose(() {
      _idleTimer?.cancel();
      _visibility?.dispose();
      unawaited(_stop());
    });
    ref.listen(receivingEnabledProvider, (_, next) {
      final on = next.value;
      if (on != null) unawaited(_onSwitch(on));
    });
    // Renamed in Settings: advertise and show the new name.
    ref.listen(identityProvider, (prev, next) {
      final before = prev?.value?.deviceName;
      final now = next.value?.deviceName;
      if (before != null && now != null && before != now) {
        unawaited(_restartIfIdle());
      }
    });
    unawaited(_start());
    return const ReceiveState();
  }

  /// Answers the Accept prompt for [sessionId]. With [trust], the sender's
  /// fingerprint is added to the trusted devices (the user compared the
  /// pairing code).
  void answer(String sessionId, {required bool accept, bool trust = false}) {
    final offer = _offers.remove(sessionId);
    if (accept && trust && offer != null) {
      unawaited(
        ref
            .read(trustRepositoryProvider)
            .trust(
              fingerprint: offer.senderFingerprint,
              deviceId: offer.sender.id,
              name: offer.sender.name,
              platform: offer.sender.platform,
            ),
      );
    }
    if (accept &&
        Platform.isIOS &&
        offer != null &&
        offer.files.any((f) => f.kind != FileKind.file)) {
      // Ask now, while the user is looking, not at the first save. The
      // accept does not wait; a save waits for the answer.
      unawaited(ref.read(photosSaverProvider).requestAccess());
    }
    _decisions.remove(sessionId)?.complete(accept);
    _dropPending(sessionId);
  }

  /// The QR payload for this phone at [ip], e.g. its hotspot address;
  /// null while the server is not running. Never log it (CLAUDE.md hard
  /// rule 7).
  ConnectPayload? payloadFor(String ip) =>
      _server == null ? null : _payloadFor?.call(LocalAddress(ip, ''));

  /// Sets the global "Receiving" switch.
  Future<void> setReceiving(bool on) =>
      ref.read(settingsRepositoryProvider).setReceivingEnabled(on);

  Future<void> _onSwitch(bool on) async {
    if (!ref.mounted || on == _receivingOn) return;
    _receivingOn = on;
    state = state.copyWith(receivingOff: !on);
    if (on) {
      if (_server == null && !_suspended) await _start();
      return;
    }
    // Off: nobody new should find this phone.
    await _advertiser?.stop();
    if (!ref.mounted) return;
    state = state.copyWith(advertising: false, qrPayload: () => null);
    await _stopIfIdle();
  }

  /// With the switch off, stops the server once no transfer needs it. A
  /// session paused for longer than its grace does not (review L6).
  Future<void> _stopIfIdle() async {
    if (_receivingOn || _server == null || _holdsServer) return;
    await _stopServer();
    if (ref.mounted) state = state.copyWith(clearPort: true);
  }

  /// Something the server must stay up for: an offer waiting for an
  /// answer, or bytes moving. A paused session does not count: its sender
  /// finds this phone again by id when it is back.
  bool get _busy =>
      state.pendingOffers.isNotEmpty ||
      state.sessions.values.any(
        (s) => switch (s.status) {
          SessionStatus.offered ||
          SessionStatus.accepted ||
          SessionStatus.transferring ||
          SessionStatus.verifying => true,
          _ => false,
        },
      );

  /// [_busy], or a session paused moments ago whose sender is probably
  /// retrying ([SessionKeepAlive.grace]).
  bool get _holdsServer => _busy || _kept.anyInGrace;

  /// A paused session's sender did not come back in time: let the server
  /// stop if nothing else needs it.
  void _onPausedGraceOver() {
    if (!ref.mounted) return;
    unawaited(_stopIfIdle());
    if (_hidden && !_holdsServer) {
      _idleTimer?.cancel();
      _idleTimer = Timer(idleInBackground, _suspendIfIdle);
    }
  }

  void _onHide() {
    _hidden = true;
    _idleTimer?.cancel();
    _idleTimer = Timer(idleInBackground, _suspendIfIdle);
  }

  Future<void> _onShow() async {
    _hidden = false;
    _idleTimer?.cancel();
    if (!ref.mounted) return;
    if (!_suspended) return _restartIfDead();
    _suspended = false;
    if (_receivingOn) await _start();
  }

  /// iOS suspends an idle app a few seconds after it is hidden, long before
  /// [idleInBackground] stops the server, and may reclaim the listening
  /// socket meanwhile (TN2277). If the server no longer answers, start it
  /// again on a new port and advertise that (review M6).
  Future<void> _restartIfDead() async {
    final server = _server;
    if (server == null || _starting) return;
    if (await server.isListening()) return;
    if (!ref.mounted || _server != server) return;
    logEvent('receive', 'listening socket gone after suspension: restarting');
    await _stopServer();
    if (!ref.mounted) return;
    state = state.copyWith(
      clearPort: true,
      advertising: false,
      qrPayload: () => null,
    );
    if (_receivingOn) await _start();
  }

  Future<void> _restartIfIdle() async {
    if (_server == null || _holdsServer || !ref.mounted) return;
    await _stopServer();
    if (!ref.mounted) return;
    state = state.copyWith(clearPort: true, advertising: false);
    await _start();
  }

  /// Hidden for a while: nobody should find a phone whose owner is not
  /// looking at it (ARCHITECTURE.md, "Server lifetime").
  Future<void> _suspendIfIdle() async {
    if (!_hidden || _suspended || _server == null || !ref.mounted) return;
    if (_holdsServer) return;
    _suspended = true;
    logEvent('receive', 'hidden and idle: server stopped');
    await _stopServer();
    if (ref.mounted) {
      state = state.copyWith(
        clearPort: true,
        advertising: false,
        qrPayload: () => null,
      );
    }
  }

  /// The pairing code and trust are checked by the server; this answers
  /// what the TrustLookup asks, and notes that a trusted device was seen.
  List<InterfaceAddress>? _interfaces;

  /// The server's local-network check (audit S8). A cached match passes;
  /// otherwise the interfaces are read again before refusing, since the
  /// peer may be on a network that just came up (a hotspot).
  Future<bool> _isLocalPeer(String ip) async {
    final cached = _interfaces;
    if (cached != null && isLocalPeer(cached, ip)) return true;
    final mine = _interfaces = await ref
        .read(networkPlatformProvider)
        .interfaces();
    return isLocalPeer(mine, ip);
  }

  Future<PeerTrust> _lookupTrust(String fingerprint, SenderInfo claimed) async {
    final repo = ref.read(trustRepositoryProvider);
    final trust = await repo.check(
      fingerprint: fingerprint,
      deviceId: claimed.id,
      name: claimed.name,
    );
    if (trust.isTrusted) await repo.touch(fingerprint);
    return trust;
  }

  /// Cancels a session from this side. An offer still waiting is declined.
  Future<void> cancel(String sessionId) async {
    answer(sessionId, accept: false);
    await _server?.cancel(sessionId);
  }

  void clearNotice() => state = state.copyWith(notice: () => null);

  Future<void> _start() async {
    if (_starting || _server != null) return;
    _starting = true;
    try {
      _receivingOn = await ref
          .read(settingsRepositoryProvider)
          .receivingEnabled();
      if (!ref.mounted) return;
      if (!_receivingOn) {
        state = state.copyWith(receivingOff: true);
        return;
      }
      state = state.copyWith(receivingOff: false);
      // Receiving starts at launch now (D-046): let the launch cleanup of
      // expired partial files finish before the server restores sessions.
      await ref.read(unfinishedTransfersProvider.future);
      if (!ref.mounted) return;
      final dirs = await AppDirs.resolve();
      final device = await ref.read(identityProvider.future);
      final identity = await ref.read(credentialsProvider.future);
      final freeSpace = ref.read(freeSpaceProvider);
      final server = await ReceiveServer.start(
        info: DeviceInfo(
          id: device.deviceId,
          name: device.deviceName,
          platform: DevicePlatform.current.name,
        ),
        credentials: identity,
        tempDir: dirs.incomingTemp,
        saveDir: dirs.received,
        store: await ref.read(receivedFileStoreProvider.future),
        repository: ref.read(transferRepositoryProvider),
        decider: _ask,
        trustLookup: _lookupTrust,
        acceptsUntrusted: () => _receivingOn,
        freeSpace: freeSpace.freeBytes,
        allowPeer: _isLocalPeer,
        dataLanes: ReceiveServer.maxParallelUploads,
      );
      if (!ref.mounted) {
        await server.close();
        return;
      }
      _server = server;
      _sub = server.events.listen(_onEvent);
      _restoreSessions(server.sessions);

      _payloadFor = (a) => ConnectPayload(
        ip: a.ip,
        port: server.port,
        fingerprint: identity.fingerprint,
        deviceId: device.deviceId,
        name: device.deviceName,
      );
      final monitor = _monitor = NetworkMonitor(
        connectivityEvents: ref.read(connectivityEventsProvider),
      );
      await monitor.start();
      if (!ref.mounted) return;
      _networkSub = monitor.changes.listen(_onNetworkChanged);
      _lifecycle = AppLifecycleListener(onResume: _onResume);
      state = state.copyWith(
        port: server.port,
        deviceName: device.deviceName,
        saveDir: dirs.received,
      );
      _showAddresses(monitor.current);

      final advertiser = _advertiser = Advertiser(
        ref.read(mdnsBackendProvider),
      );
      try {
        await advertiser.start(
          txt: TxtRecord.forDevice(
            identity: device,
            platform: DevicePlatform.current,
            fingerprint: identity.fingerprint,
          ),
          port: server.port,
        );
        if (ref.mounted) state = state.copyWith(advertising: true);
      } catch (e) {
        logEvent('discovery', 'advertising failed: ${e.runtimeType}');
        if (ref.mounted) {
          state = state.copyWith(
            advertiseError: () =>
                'Nearby discovery is not available. The QR code still works.',
          );
        }
      }
    } catch (e) {
      if (ref.mounted) state = state.copyWith(error: 'Could not start: $e');
    } finally {
      _starting = false;
    }
  }

  Future<void> _stop() async {
    for (final c in _decisions.values) {
      c.complete(false);
    }
    _decisions.clear();
    _offers.clear();
    await _stopServer();
  }

  Future<void> _stopServer() async {
    _lifecycle?.dispose();
    _lifecycle = null;
    await _networkSub?.cancel();
    _networkSub = null;
    await _monitor?.dispose();
    _monitor = null;
    await _advertiser?.stop();
    _advertiser = null;
    await _sub?.cancel();
    _sub = null;
    final server = _server;
    _server = null;
    try {
      await server?.close();
    } catch (e) {
      // A socket iOS reclaimed may fail to close; it is gone either way.
      logEvent('receive', 'server close failed: ${e.runtimeType}');
    }
    _kept.clear();
  }

  /// Keeps the app alive while [sessionId] moves bytes ([SessionKeepAlive]
  /// decides when).
  Future<void> _beginKeepAlive(String sessionId) async {
    final server = _server;
    if (server == null) return;
    final from = state.sessions[sessionId]?.sender.name ?? 'another phone';
    await _keepAlive.begin(
      sessionId,
      _ServerKeepAlive(server),
      title: 'Receiving from $from',
      text: 'Keep CrossDrop open until the transfer finishes',
    );
  }

  Future<bool> _ask(IncomingOffer offer) {
    final c = Completer<bool>();
    _decisions[offer.sessionId] = c;
    _offers[offer.sessionId] = offer;
    if (ref.mounted) {
      state = state.copyWith(pendingOffers: [...state.pendingOffers, offer]);
    }
    return c.future;
  }

  void _dropPending(String sessionId) {
    if (!state.pendingOffers.any((o) => o.sessionId == sessionId)) return;
    state = state.copyWith(
      pendingOffers: [
        for (final o in state.pendingOffers)
          if (o.sessionId != sessionId) o,
      ],
    );
  }

  void _restoreSessions(List<ReceiveSessionSnapshot> restored) {
    if (restored.isEmpty) return;
    final sessions = Map.of(state.sessions);
    for (final s in restored) {
      final tracker = _trackers[s.sessionId] = ProgressTracker({
        for (final f in s.files) f.offer.fileId: f.offer.size,
      });
      for (final f in s.files) {
        tracker.set(f.offer.fileId, f.receivedBytes);
      }
      sessions[s.sessionId] = IncomingSession(
        sessionId: s.sessionId,
        sender: s.sender,
        status: s.status,
        reason: s.reason,
        doneBytes: tracker.doneBytes,
        files: {
          for (final f in s.files)
            f.offer.fileId: IncomingFile(
              name: f.offer.name,
              size: f.offer.size,
              kind: f.offer.kind,
              receivedBytes: f.receivedBytes,
              status: f.status,
              savedPath: f.savedPath,
              error: f.errorCode,
            ),
        },
      );
    }
    state = state.copyWith(sessions: sessions);
  }

  void _showAddresses(List<LocalAddress> addresses) {
    final qr = pickQrAddress(addresses);
    state = state.copyWith(
      addresses: addresses,
      qrPayload: () => qr == null ? null : _payloadFor!(qr).toUri(),
    );
  }

  /// Wi-Fi or IP changed: register again so peers learn the new address,
  /// and redraw the QR code.
  Future<void> _onNetworkChanged(List<LocalAddress> addresses) async {
    if (!ref.mounted) return;
    _showAddresses(addresses);
    await _restartAdvertising();
  }

  /// iOS pauses the app when the screen locks; the network may have
  /// changed meanwhile.
  Future<void> _onResume() async {
    if (!ref.mounted) return;
    _showAddresses(reachableAddresses(await listLocalAddresses()));
    await _restartAdvertising();
  }

  Future<void> _restartAdvertising() async {
    try {
      await _advertiser?.restart();
    } catch (e) {
      logEvent('discovery', 'advertising restart failed: ${e.runtimeType}');
    }
  }

  void _onEvent(ReceiveEvent e) {
    if (!ref.mounted) return;
    switch (e) {
      case OfferRefused(:final reason, :final neededBytes):
        state = state.copyWith(
          notice: () => switch (reason) {
            RejectReasons.noSpace =>
              'Refused a transfer: not enough free space '
                  '(${((neededBytes ?? 0) / 1e9).toStringAsFixed(1)} GB '
                  'needed).',
            ErrorCodes.receivingOff =>
              'Refused a transfer from an untrusted device: receiving is '
                  'off.',
            _ =>
              'Refused a transfer: that phone already has an unfinished '
                  'transfer here.',
          },
        );
        return;
      case SessionOffered(:final sessionId, :final sender, :final files):
        _trackers[sessionId] = ProgressTracker({
          for (final f in files) f.fileId: f.size,
        });
        state = state.copyWith(
          sessions: {
            ...state.sessions,
            sessionId: IncomingSession(
              sessionId: sessionId,
              sender: sender,
              status: SessionStatus.offered,
              files: {
                for (final f in files)
                  f.fileId: IncomingFile(
                    name: f.name,
                    size: f.size,
                    kind: f.kind,
                  ),
              },
            ),
          },
        );
        return;
      case SessionStateChanged(:final sessionId, :final status, :final reason):
        final before = state.sessions[sessionId]?.status;
        if (status != SessionStatus.offered) {
          // Timed out or withdrawn while the prompt was open.
          _decisions.remove(sessionId)?.complete(false);
          _offers.remove(sessionId);
          _dropPending(sessionId);
        }
        if (status.isTerminal && before == SessionStatus.offered) {
          // Declined, timed out or withdrawn before Accept: no screen shows
          // it, and keeping every offer's file list would let any phone on
          // the network grow this map (review M1).
          _trackers.remove(sessionId);
          state = state.copyWith(
            sessions: {...state.sessions}..remove(sessionId),
          );
        } else {
          _update(sessionId, (s) => s.copyWith(status: status, reason: reason));
        }
        _kept.update(sessionId, status);
        if (status.isTerminal) unawaited(_stopIfIdle());
        if (_hidden && !_holdsServer) {
          // The last transfer ended while the app was hidden.
          _idleTimer?.cancel();
          _idleTimer = Timer(idleInBackground, _suspendIfIdle);
        }
        return;
      case FileProgress(:final sessionId, :final fileId, :final receivedBytes):
        final tracker = _trackers[sessionId];
        tracker?.set(fileId, receivedBytes);
        // Limit rebuilds to about 10 per second; later events carry the
        // newer count anyway.
        final now = DateTime.now();
        final current = state.sessions[sessionId]?.files[fileId];
        final last = current != null && receivedBytes == current.size;
        if (!last && now.difference(_lastUiUpdate).inMilliseconds < 100) {
          return;
        }
        _lastUiUpdate = now;
        if (tracker != null) {
          unawaited(
            _keepAlive.progress(
              sessionId,
              '${(tracker.fraction * 100).floor()}% · '
              '${formatTimeLeft(tracker.eta)}',
            ),
          );
        }
        _updateFile(
          sessionId,
          fileId,
          (f) => f.copyWith(
            receivedBytes: receivedBytes,
            status: FileTransferStatus.receiving,
          ),
        );
      case FileSaved(
        :final sessionId,
        :final fileId,
        :final savedPath,
        :final collection,
        :final fallback,
      ):
        final tracker = _trackers[sessionId];
        tracker?.set(fileId, tracker.sizeOf(fileId));
        _updateFile(
          sessionId,
          fileId,
          (f) => f.copyWith(
            receivedBytes: f.size,
            status: FileTransferStatus.saved,
            savedPath: savedPath,
            savedTo: collection,
            saveFallback: fallback,
          ),
        );
      case FileFailed(:final sessionId, :final fileId, :final code):
        _trackers[sessionId]?.drop(fileId);
        _updateFile(
          sessionId,
          fileId,
          (f) => f.copyWith(
            status: FileTransferStatus.failed,
            error: code,
            receivedBytes: 0,
          ),
        );
    }
  }

  void _updateFile(
    String sessionId,
    String fileId,
    IncomingFile Function(IncomingFile) change,
  ) {
    final tracker = _trackers[sessionId];
    _update(sessionId, (s) {
      final file = s.files[fileId];
      if (file == null) return s;
      return s.copyWith(
        files: {...s.files, fileId: change(file)},
        doneBytes: tracker?.doneBytes,
        bytesPerSecond: tracker?.bytesPerSecond,
        eta: () => tracker?.eta,
      );
    });
  }

  void _update(
    String sessionId,
    IncomingSession Function(IncomingSession) change,
  ) {
    final s = state.sessions[sessionId];
    if (s == null) return;
    state = state.copyWith(sessions: {...state.sessions, sessionId: change(s)});
  }
}

/// What a receiving session does when iOS is about to suspend the app:
/// save every running upload's progress. The sender reconnects when the
/// app is back.
class _ServerKeepAlive implements BackgroundAware {
  _ServerKeepAlive(this._server);

  final ReceiveServer _server;

  @override
  Future<void> onBackground() => _server.checkpointAll();

  @override
  void onForeground() {}
}
