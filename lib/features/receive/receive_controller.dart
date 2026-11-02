import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/app_dirs.dart';
import '../../app/providers.dart';
import '../../core/discovery/discovery_service.dart';
import '../../core/discovery/network_monitor.dart';
import '../../core/discovery/txt_record.dart';
import '../../core/engine/progress_tracker.dart';
import '../../core/log.dart';
import '../../core/protocol/connect_payload.dart';
import '../../core/protocol/models.dart';
import '../../core/security/device_identity.dart';
import '../../core/security/ephemeral_identity.dart';
import '../../core/server/receive_server.dart';

class IncomingFile {
  const IncomingFile({
    required this.name,
    required this.size,
    this.receivedBytes = 0,
    this.status = FileTransferStatus.pending,
    this.savedPath,
    this.error,
  });

  final String name;
  final int size;
  final int receivedBytes;
  final FileTransferStatus status;
  final String? savedPath;
  final String? error;

  IncomingFile copyWith({
    int? receivedBytes,
    FileTransferStatus? status,
    String? savedPath,
    String? error,
  }) => IncomingFile(
    name: name,
    size: size,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    status: status ?? this.status,
    savedPath: savedPath ?? this.savedPath,
    error: error ?? this.error,
  );
}

/// One session as the Receive screen shows it.
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
  });

  /// Null while the server is starting.
  final int? port;
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
  }) => ReceiveState(
    port: port ?? this.port,
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
  );
}

final receiveControllerProvider =
    NotifierProvider.autoDispose<ReceiveController, ReceiveState>(
      ReceiveController.new,
    );

/// Runs the receive server while the Receive screen is open, advertises it
/// on the local network, asks the user about each offer and tracks
/// progress.
class ReceiveController extends Notifier<ReceiveState> {
  ReceiveServer? _server;
  StreamSubscription<ReceiveEvent>? _sub;
  Advertiser? _advertiser;
  NetworkMonitor? _monitor;
  StreamSubscription<List<LocalAddress>>? _networkSub;
  AppLifecycleListener? _lifecycle;
  ConnectPayload Function(LocalAddress)? _payloadFor;
  final Map<String, ProgressTracker> _trackers = {};
  final Map<String, Completer<bool>> _decisions = {};
  DateTime _lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  ReceiveState build() {
    ref.onDispose(_stop);
    unawaited(_start());
    return const ReceiveState();
  }

  /// Answers the Accept prompt for [sessionId].
  void answer(String sessionId, {required bool accept}) {
    _decisions.remove(sessionId)?.complete(accept);
    _dropPending(sessionId);
  }

  /// Cancels a session from this side. An offer still waiting is declined.
  Future<void> cancel(String sessionId) async {
    answer(sessionId, accept: false);
    await _server?.cancel(sessionId);
  }

  void clearNotice() => state = state.copyWith(notice: () => null);

  Future<void> _start() async {
    try {
      final dirs = await AppDirs.resolve();
      final device = await ref.read(identityProvider.future);
      final identity = await EphemeralIdentity.generate();
      final freeSpace = ref.read(freeSpaceProvider);
      final server = await ReceiveServer.start(
        info: DeviceInfo(
          id: device.deviceId,
          name: device.deviceName,
          platform: DevicePlatform.current.name,
        ),
        securityContext: identity.serverContext(),
        tempDir: dirs.incomingTemp,
        saveDir: dirs.received,
        repository: ref.read(transferRepositoryProvider),
        decider: _ask,
        freeSpace: freeSpace.freeBytes,
      );
      if (!ref.mounted) {
        await server.close();
        return;
      }
      _server = server;
      _sub = server.events.listen(_onEvent);
      _restoreSessions(server.sessions);
      await WakelockPlus.enable();

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
      _lifecycle = AppLifecycleListener(
        onResume: _onResume,
        onHide: _onBackground,
      );
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
    }
  }

  Future<void> _stop() async {
    for (final c in _decisions.values) {
      c.complete(false);
    }
    _decisions.clear();
    _lifecycle?.dispose();
    await _networkSub?.cancel();
    await _monitor?.dispose();
    await _advertiser?.stop();
    await _sub?.cancel();
    await _server?.close();
    await WakelockPlus.disable();
  }

  Future<bool> _ask(IncomingOffer offer) {
    final c = Completer<bool>();
    _decisions[offer.sessionId] = c;
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

  /// Going to the background: save progress before iOS suspends the app.
  Future<void> _onBackground() async {
    await _server?.checkpointAll();
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
                  f.fileId: IncomingFile(name: f.name, size: f.size),
              },
            ),
          },
        );
        return;
      case SessionStateChanged(:final sessionId, :final status, :final reason):
        if (status != SessionStatus.offered) {
          // Timed out or withdrawn while the prompt was open.
          _decisions.remove(sessionId)?.complete(false);
          _dropPending(sessionId);
        }
        _update(sessionId, (s) => s.copyWith(status: status, reason: reason));
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
        _updateFile(
          sessionId,
          fileId,
          (f) => f.copyWith(
            receivedBytes: receivedBytes,
            status: FileTransferStatus.receiving,
          ),
        );
      case FileSaved(:final sessionId, :final fileId, :final savedPath):
        final tracker = _trackers[sessionId];
        tracker?.set(fileId, tracker.sizeOf(fileId));
        _updateFile(
          sessionId,
          fileId,
          (f) => f.copyWith(
            receivedBytes: f.size,
            status: FileTransferStatus.saved,
            savedPath: savedPath,
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
