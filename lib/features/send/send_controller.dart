import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/keep_alive.dart';
import '../../app/providers.dart';
import '../../core/client/peer_check.dart';
import '../../core/client/upload_client.dart';
import '../../core/discovery/peer_locator.dart';
import '../../core/engine/send_session.dart';
import '../../core/protocol/file_type.dart';
import '../../core/protocol/models.dart';
import '../../core/security/device_identity.dart';
import '../../core/storage/transfer_repository.dart';
import '../nearby/nearby_controller.dart';
import '../transfer/transfer_format.dart';

class SendState {
  const SendState({
    this.items = const [],
    this.snapshot,
    this.error,
    this.receiverName,
    this.receiver,
    this.receiverTrusted = false,
  });

  /// The receiver of the current or last send, after [checkPeer].
  final ConnectTarget? receiver;

  /// This phone trusts the receiver's fingerprint.
  final bool receiverTrusted;

  /// Offer "Trust this device" once a send to an untrusted receiver
  /// reached it (the user compared the code, or scanned its QR).
  bool get canTrustReceiver =>
      !receiverTrusted &&
      receiver?.fingerprint != null &&
      receiver?.deviceId != null &&
      snapshot?.phase == SendPhase.done;

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
    ConnectTarget? receiver,
    bool? receiverTrusted,
  }) => SendState(
    items: items ?? this.items,
    snapshot: snapshot != null ? snapshot() : this.snapshot,
    error: error != null ? error() : this.error,
    receiverName: receiverName ?? this.receiverName,
    receiver: receiver ?? this.receiver,
    receiverTrusted: receiverTrusted ?? this.receiverTrusted,
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

  /// Offers the picked files to [target] and sends them. A target that
  /// was not checked yet (an address typed on the Send screen) is checked
  /// first, so every connection is pinned to the receiver's fingerprint.
  Future<void> send(ConnectTarget target) async {
    if (state.isRunning || state.items.isEmpty) return;
    var checked = target;
    if (target.pinSource == null) {
      try {
        checked = await ref.read(peerCheckProvider)(target);
      } on UploadException catch (e) {
        if (ref.mounted) {
          state = state.copyWith(error: () => _checkError(e));
        }
        return;
      }
    }
    final device = await ref.read(identityProvider.future);
    final credentials = await ref.read(credentialsProvider.future);
    final deviceId = checked.deviceId;
    final session = SendSession(
      host: checked.host,
      port: checked.port,
      sender: _senderInfo(device),
      items: state.items,
      receiverFingerprint: checked.fingerprint!,
      credentials: credentials,
      expectedDeviceId: deviceId,
      repository: ref.read(transferRepositoryProvider),
      locate: deviceId == null ? null : _locator(deviceId, device.deviceId),
    );
    if (checked.trust.isTrusted) {
      await ref.read(trustRepositoryProvider).touch(checked.fingerprint!);
    }
    state = state.copyWith(
      receiverName: checked.name ?? checked.host,
      receiver: checked,
      receiverTrusted: checked.trust.isTrusted,
    );
    await _run(session);
  }

  /// Trusts the receiver of the last send: later sends to it are pinned
  /// to this fingerprint and a different key is reported.
  Future<void> trustReceiver() async {
    final r = state.receiver;
    final fp = r?.fingerprint;
    final id = r?.deviceId;
    if (r == null || fp == null || id == null) return;
    await ref
        .read(trustRepositoryProvider)
        .trust(
          fingerprint: fp,
          deviceId: id,
          name: r.name ?? r.host,
          platform: r.platform ?? 'unknown',
        );
    if (ref.mounted) state = state.copyWith(receiverTrusted: true);
  }

  static String _checkError(UploadException e) => switch (e.code) {
    pinMismatchCode =>
      "That isn't the expected device: its security key is different. "
          'Nothing was sent.',
    'identity_mismatch' => 'A different device answered at this address.',
    'version' => 'Update CrossDrop on the other phone.',
    _ =>
      'Could not reach that phone. Check the IP and port on its Receive '
          'screen.',
  };

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
    final credentials = await ref.read(credentialsProvider.future);
    final SendSession session;
    try {
      session = SendSession.resume(
        stored,
        sender: _senderInfo(device),
        credentials: credentials,
        repository: ref.read(transferRepositoryProvider),
        locate: _locator(stored.peer.id, device.deviceId),
      );
    } on StateError {
      // Stored before Phase 4, without the receiver's fingerprint.
      state = state.copyWith(
        error: () =>
            'This transfer was started by an older version of CrossDrop '
            'and cannot be resumed safely. Send the files again.',
      );
      return;
    }
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
