import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/keep_alive.dart';
import '../../app/providers.dart';
import '../../core/client/peer_check.dart';
import '../../core/discovery/peer_locator.dart';
import '../../core/engine/send_session.dart';
import '../../core/protocol/file_type.dart';
import '../../core/protocol/models.dart';
import '../../core/security/device_identity.dart';
import '../../core/storage/transfer_repository.dart';
import '../transfer/transfer_format.dart';

class SendState {
  const SendState({
    this.items = const [],
    this.snapshot,
    this.error,
    this.receiverName,
  });

  /// Files picked, in sending order.
  final List<SendItem> items;

  /// Null until a send starts.
  final SendSnapshot? snapshot;
  final String? error;
  final String? receiverName;

  bool get isRunning => snapshot != null && !snapshot!.phase.isFinished;

  bool get canResume => snapshot?.canResume ?? false;

  int get totalBytes => items.fold(0, (sum, i) => sum + i.size);

  SendState copyWith({
    List<SendItem>? items,
    SendSnapshot? Function()? snapshot,
    String? Function()? error,
    String? receiverName,
  }) => SendState(
    items: items ?? this.items,
    snapshot: snapshot != null ? snapshot() : this.snapshot,
    error: error != null ? error() : this.error,
    receiverName: receiverName ?? this.receiverName,
  );
}

/// App-wide, not tied to the Send screen: a transfer keeps running while
/// the user moves around the app.
final sendControllerProvider = NotifierProvider<SendController, SendState>(
  SendController.new,
);

/// Picks files and runs one [SendSession] at a time.
class SendController extends Notifier<SendState> implements BackgroundAware {
  SendSession? _session;
  StreamSubscription<SendSnapshot>? _sub;
  final Object _keepAliveKey = Object();

  @override
  SendState build() {
    final keepAlive = ref.read(keepAliveProvider);
    ref.onDispose(() {
      _sub?.cancel();
      unawaited(keepAlive.end(_keepAliveKey));
    });
    return const SendState();
  }

  Future<void> pickFiles() async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty || !ref.mounted) return;
    final items = <SendItem>[];
    var unreadable = 0;
    for (final f in picked) {
      final path = f.path;
      if (path == null) {
        unreadable++;
        continue;
      }
      final type = guessFileType(f.name);
      items.add(
        SendItem(
          path: path,
          name: f.name,
          size: await File(path).length(),
          mime: type.mime,
          kind: type.kind,
        ),
      );
    }
    if (!ref.mounted) return;
    state = SendState(
      items: [...state.items, ...items],
      error: unreadable == 0
          ? null
          : '$unreadable file(s) cannot be read directly and were skipped.',
    );
  }

  void clearFiles() {
    if (state.isRunning) return;
    state = const SendState();
  }

  /// Offers the picked files to [target] and sends them.
  Future<void> send(ConnectTarget target) async {
    if (state.isRunning || state.items.isEmpty) return;
    final device = await ref.read(identityProvider.future);
    final deviceId = target.deviceId;
    final session = SendSession(
      host: target.host,
      port: target.port,
      sender: _senderInfo(device),
      items: state.items,
      expectedDeviceId: deviceId,
      repository: ref.read(transferRepositoryProvider),
      locate: deviceId == null ? null : _locator(deviceId, device.deviceId),
    );
    state = state.copyWith(receiverName: target.name ?? target.host);
    await _run(session);
  }

  /// Continues the last session after it gave up (network) or the
  /// receiver ran out of space.
  Future<void> resume() async {
    final sid = state.snapshot?.sessionId;
    if (!state.canResume || sid == null) return;
    final stored = await ref
        .read(transferRepositoryProvider)
        .find(sid, TransferDirection.send);
    if (stored != null) await resumeStored(stored);
  }

  /// Continues a session stored by an earlier app run.
  Future<void> resumeStored(StoredSession stored) async {
    if (state.isRunning) return;
    final device = await ref.read(identityProvider.future);
    final session = SendSession.resume(
      stored,
      sender: _senderInfo(device),
      repository: ref.read(transferRepositoryProvider),
      locate: _locator(stored.peer.id, device.deviceId),
    );
    state = SendState(
      items: [
        for (final f in stored.files)
          SendItem(
            path: f.sourcePath ?? '',
            name: f.name,
            size: f.size,
            mime: f.mime,
            kind: f.kind,
          ),
      ],
      receiverName: stored.peer.name,
    );
    await _run(session);
  }

  Future<void> cancel() async => _session?.cancel();

  @override
  Future<void> onBackground() async {
    final s = _session;
    if (s == null || s.snapshot.phase.isFinished) return;
    s.pause();
    // Wait until the current chunk is out and the upload stopped.
    await s.updates
        .firstWhere((u) => u.phase == SendPhase.paused || u.phase.isFinished)
        .timeout(const Duration(seconds: 10), onTimeout: () => s.snapshot);
  }

  @override
  void onForeground() => _session?.resume();

  Future<void> _run(SendSession session) async {
    _session = session;
    final keepAlive = ref.read(keepAliveProvider);
    final count = state.items.length;
    await keepAlive.begin(
      _keepAliveKey,
      this,
      title: 'Sending to ${state.receiverName}',
      text: '$count ${count == 1 ? 'file' : 'files'}',
    );
    await _sub?.cancel();
    _sub = session.updates.listen((u) {
      if (!ref.mounted) return;
      state = state.copyWith(snapshot: () => u, error: () => null);
      unawaited(
        keepAlive.progress(
          _keepAliveKey,
          '${(u.fraction * 100).floor()}% · ${formatTimeLeft(u.eta)}',
        ),
      );
    });
    try {
      final result = await session.run();
      if (ref.mounted) state = state.copyWith(snapshot: () => result);
    } finally {
      await keepAlive.end(_keepAliveKey);
      if (_session == session) _session = null;
    }
  }

  PeerLocator _locator(String deviceId, String ownDeviceId) =>
      () => locatePeer(
        ref.read(mdnsBackendFactoryProvider)(),
        deviceId: deviceId,
        ownDeviceId: ownDeviceId,
      );

  static SenderInfo _senderInfo(DeviceIdentity device) => SenderInfo(
    id: device.deviceId,
    name: device.deviceName,
    platform: DevicePlatform.current.name,
  );
}
