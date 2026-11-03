import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/keep_alive.dart';
import '../../app/media_providers.dart';
import '../../app/providers.dart';
import '../../core/client/peer_check.dart';
import '../../core/client/upload_client.dart';
import '../../core/discovery/peer_locator.dart';
import '../../core/engine/send_session.dart';
import '../../core/log.dart';
import '../../core/media/format_plan.dart';
import '../../core/media/prepare.dart';
import '../../core/protocol/models.dart';
import '../../core/security/device_identity.dart';
import '../../core/storage/transfer_repository.dart';
import '../nearby/nearby_controller.dart';
import '../transfer/transfer_format.dart';

class SendState {
  const SendState({
    this.picked = const [],
    this.items = const [],
    this.preparing,
    this.skipped = const [],
    this.snapshot,
    this.error,
    this.receiverName,
    this.receiver,
    this.receiverTrusted = false,
    this.pausedByUser = false,
  });

  /// The user tapped Pause; the send waits for Resume, even when the app
  /// comes back to the foreground.
  final bool pausedByUser;

  /// What the user chose, before it is prepared.
  final List<PickedItem> picked;

  /// Files of the current or last send, after preparing.
  final List<SendItem> items;

  /// Set while picked items are being prepared (exports, iCloud).
  final PrepareProgress? preparing;

  /// Items left out by the last preparation, with the reason.
  final List<SkippedItem> skipped;

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

  /// Null until a send starts.
  final SendSnapshot? snapshot;
  final String? error;
  final String? receiverName;

  bool get isPreparing => preparing != null;

  bool get isRunning =>
      isPreparing || (snapshot != null && !snapshot!.phase.isFinished);

  bool get canResume => snapshot?.canResume ?? false;

  bool get canSend => !isRunning && picked.isNotEmpty;

  SendState copyWith({
    List<PickedItem>? picked,
    List<SendItem>? items,
    PrepareProgress? Function()? preparing,
    List<SkippedItem>? skipped,
    SendSnapshot? Function()? snapshot,
    String? Function()? error,
    String? receiverName,
    ConnectTarget? receiver,
    bool? receiverTrusted,
    bool? pausedByUser,
  }) => SendState(
    picked: picked ?? this.picked,
    items: items ?? this.items,
    preparing: preparing != null ? preparing() : this.preparing,
    skipped: skipped ?? this.skipped,
    snapshot: snapshot != null ? snapshot() : this.snapshot,
    error: error != null ? error() : this.error,
    receiverName: receiverName ?? this.receiverName,
    receiver: receiver ?? this.receiver,
    receiverTrusted: receiverTrusted ?? this.receiverTrusted,
    pausedByUser: pausedByUser ?? this.pausedByUser,
  );
}

/// App-wide, not tied to the Send screen: a transfer keeps running while
/// the user moves around the app.
final sendControllerProvider = NotifierProvider<SendController, SendState>(
  SendController.new,
);

/// Picks, prepares and runs one [SendSession] at a time.
class SendController extends Notifier<SendState> implements BackgroundAware {
  SendSession? _session;
  StreamSubscription<SendSnapshot>? _sub;
  PrepareControl? _prepare;

  /// The receiver is being checked before preparing (typed address).
  bool _checking = false;
  final Object _keepAliveKey = Object();

  /// What the last send leaves behind: staged copies and content grants,
  /// released once it ends for good (not while it can still resume).
  _Leftovers? _leftovers;

  @override
  SendState build() {
    final keepAlive = ref.read(keepAliveProvider);
    ref.onDispose(() {
      _sub?.cancel();
      unawaited(keepAlive.end(_keepAliveKey));
    });
    return const SendState();
  }

  /// Adds photos and videos from the gallery picker, without duplicates.
  void addMedia(List<LibraryAsset> assets) {
    if (state.isRunning || assets.isEmpty) return;
    final have = {
      for (final p in state.picked)
        if (p is PickedAsset) p.asset.id,
    };
    _setPicked([
      ...state.picked,
      for (final a in assets)
        if (have.add(a.id)) PickedAsset(a),
    ]);
  }

  /// Adds files from another app's share sheet or intent.
  void addShared(List<PickedFile> files) {
    if (state.isRunning || files.isEmpty) return;
    _setPicked([...state.picked, ...files]);
  }

  Future<void> pickDocuments() async {
    if (state.isRunning) return;
    final picker = await ref.read(documentPickerProvider.future);
    final files = await picker.pick();
    if (!ref.mounted || files.isEmpty) return;
    _setPicked([...state.picked, ...files]);
  }

  void _setPicked(List<PickedItem> picked) {
    // A new selection starts a new send; the last one's files go.
    unawaited(_releaseLeftovers());
    state = SendState(
      picked: picked,
      receiver: state.receiver,
      receiverName: state.receiverName,
      receiverTrusted: state.receiverTrusted,
    );
  }

  /// Takes one item out of the selection.
  Future<void> removePicked(PickedItem item) async {
    if (state.isRunning) return;
    final left = [
      for (final p in state.picked)
        if (!identical(p, item)) p,
    ];
    if (left.length == state.picked.length) return;
    state = state.copyWith(picked: left);
    if (item is PickedFile) await _releaseDocs([item]);
  }

  Future<void> clearFiles() async {
    if (state.isRunning) return;
    final docs = [
      for (final p in state.picked)
        if (p is PickedFile) p,
    ];
    state = const SendState();
    await _releaseLeftovers();
    await _releaseDocs(docs);
  }

  /// Prepares the picked items, offers them to [target] and sends them. A
  /// target that was not checked yet (an address typed on the Send
  /// screen) is checked first, so every connection is pinned to the
  /// receiver's fingerprint.
  Future<void> send(ConnectTarget target) async {
    if (!state.canSend) return;
    // Cancel works from here on: during the peer check below there is no
    // preparation or session yet, and Cancel used to do nothing (review
    // L4).
    final control = _prepare = PrepareControl();
    // Running from now on, so the transfer screen never shows the last
    // send's result.
    state = state.copyWith(
      snapshot: () => null,
      error: () => null,
      skipped: const [],
      preparing: () => PrepareProgress(0, state.picked.length, null),
    );
    var checked = target;
    if (target.pinSource == null) {
      _checking = true;
      var ok = false;
      try {
        checked = await ref.read(peerCheckProvider)(target);
        ok = true;
      } on UploadException catch (e) {
        if (ref.mounted && !control.isCancelled) {
          state = state.copyWith(
            preparing: () => null,
            error: () => _checkError(e),
          );
        }
        return;
      } finally {
        _checking = false;
        if ((!ok || control.isCancelled) && identical(_prepare, control)) {
          _prepare = null;
        }
      }
      // Cancelled meanwhile: cancel() already reset the state.
      if (control.isCancelled || !ref.mounted) return;
    }
    final prepared = await _prepareFor(checked, control);
    if (prepared == null || !ref.mounted) return;

    final device = await ref.read(identityProvider.future);
    final credentials = await ref.read(credentialsProvider.future);
    final deviceId = checked.deviceId;
    final session = SendSession(
      host: checked.host,
      port: checked.port,
      sender: _senderInfo(device),
      items: prepared.items,
      receiverFingerprint: checked.fingerprint!,
      credentials: credentials,
      expectedDeviceId: deviceId,
      repository: ref.read(transferRepositoryProvider),
      locate: deviceId == null ? null : _locator(deviceId, device.deviceId),
      opener: ref.read(sourceOpenerProvider),
    );
    if (checked.trust.isTrusted) {
      await ref.read(trustRepositoryProvider).touch(checked.fingerprint!);
    }
    _leftovers = _Leftovers(
      stagingDirs: [?prepared.stagingDir],
      docs: [
        for (final p in state.picked)
          if (p is PickedFile) p,
      ],
    );
    state = state.copyWith(
      items: prepared.items,
      skipped: prepared.skipped,
      receiverName: checked.name ?? checked.host,
      receiver: checked,
      receiverTrusted: checked.trust.isTrusted,
    );
    await _run(session);
  }

  /// Exports and checks the picked items. Null if cancelled or nothing
  /// is left to send; the state then says why.
  Future<PrepareResult?> _prepareFor(
    ConnectTarget target,
    PrepareControl control,
  ) async {
    final dirs = await ref.read(appDirsProvider.future);
    final settings = await ref
        .read(settingsRepositoryProvider)
        .formatSettings();
    final preparer = Preparer(
      platform: ref.read(mediaPlatformProvider),
      opener: ref.read(sourceOpenerProvider),
      stagingRoot: dirs.outgoingStaging,
      settings: settings,
      receiver: DevicePlatform.tryParse(target.platform ?? ''),
    );
    _prepare = control;
    final picked = state.picked;
    state = state.copyWith(
      preparing: () => PrepareProgress(0, picked.length, null),
      skipped: const [],
      snapshot: () => null,
      error: () => null,
    );
    final keepAlive = ref.read(keepAliveProvider);
    await keepAlive.begin(
      _keepAliveKey,
      this,
      title: 'Preparing files',
      text: '${picked.length} ${picked.length == 1 ? 'item' : 'items'}',
    );
    PrepareResult result;
    try {
      result = await preparer.prepare(
        picked,
        control: control,
        onProgress: (p) {
          if (ref.mounted) state = state.copyWith(preparing: () => p);
        },
      );
    } catch (e) {
      logEvent('prepare', 'failed: ${e.runtimeType}');
      result = PrepareResult(
        items: const [],
        skipped: [
          for (final p in picked) SkippedItem(p.label, SkipReason.unreadable),
        ],
      );
    } finally {
      _prepare = null;
      await keepAlive.end(_keepAliveKey);
    }
    if (!ref.mounted) return null;
    if (result.cancelled) {
      state = state.copyWith(preparing: () => null);
      return null;
    }
    if (result.items.isEmpty) {
      state = state.copyWith(
        preparing: () => null,
        skipped: result.skipped,
        error: () => 'Nothing could be prepared for sending.',
      );
      return null;
    }
    state = state.copyWith(preparing: () => null, skipped: result.skipped);
    return result;
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
      'Could not reach that phone. Check the IP and port under "Show my QR '
          'code" on it.',
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
        opener: ref.read(sourceOpenerProvider),
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
    final items = [
      for (final f in stored.files)
        SendItem(
          path: f.sourcePath ?? '',
          name: f.name,
          size: f.size,
          mime: f.mime,
          kind: f.kind,
        ),
    ];
    if (_leftovers == null) {
      // Started by an earlier run: work out what it left behind.
      final dirs = await ref.read(appDirsProvider.future);
      _leftovers = _Leftovers(
        stagingDirs: {
          for (final i in items) ?stagingBatchOf(i.path, dirs.outgoingStaging),
        }.toList(),
        docs: [
          for (final i in items)
            if (i.path.startsWith('content://'))
              PickedFile(ref: i.path, name: i.name),
        ],
      );
    }
    state = SendState(items: items, receiverName: stored.peer.name);
    await _run(session);
  }

  Future<void> cancel() async {
    final prepare = _prepare;
    if (prepare != null) {
      if (_checking) {
        // The peer check cannot be stopped; its answer is ignored.
        state = state.copyWith(preparing: () => null);
      }
      return prepare.cancel();
    }
    await _session?.cancel();
  }

  /// Pauses the running send after the current chunk. The receiver keeps
  /// what arrived; [continueSending] picks up from there.
  void pause() {
    final s = _session;
    if (s == null) return;
    final phase = s.snapshot.phase;
    if (phase != SendPhase.sending && phase != SendPhase.retrying) return;
    unawaited(s.pause());
    state = state.copyWith(pausedByUser: true);
  }

  void continueSending() {
    if (!state.pausedByUser) return;
    state = state.copyWith(pausedByUser: false);
    _session?.resume();
  }

  @override
  Future<void> onBackground() async {
    final s = _session;
    if (s == null || s.snapshot.phase.isFinished || state.pausedByUser) {
      return;
    }
    // Completes once the current chunk is out and no upload runs. Waiting
    // for a `paused` update instead missed the one pause() sends at once,
    // and always took the full 10 s (review M4).
    await s.pause().timeout(const Duration(seconds: 10), onTimeout: () {});
  }

  @override
  void onForeground() {
    if (!state.pausedByUser) _session?.resume();
  }

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
    SendSnapshot? result;
    try {
      result = await session.run();
      if (ref.mounted) {
        state = state.copyWith(snapshot: () => result, pausedByUser: false);
      }
    } finally {
      await keepAlive.end(_keepAliveKey);
      if (_session == session) _session = null;
      // A send that can resume keeps its files; any other end frees them.
      if (result != null && !result.canResume) {
        await _releaseLeftovers();
        if (ref.mounted) state = state.copyWith(picked: const []);
      }
    }
  }

  Future<void> _releaseLeftovers() async {
    final l = _leftovers;
    _leftovers = null;
    if (l == null) return;
    for (final d in l.stagingDirs) {
      await deleteStaging(d);
    }
    await _releaseDocs(l.docs);
  }

  Future<void> _releaseDocs(List<PickedFile> docs) async {
    if (docs.isEmpty) return;
    try {
      final picker = await ref.read(documentPickerProvider.future);
      await picker.release(docs);
    } catch (e) {
      logEvent('send', 'could not release picks: ${e.runtimeType}');
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

class _Leftovers {
  const _Leftovers({required this.stagingDirs, required this.docs});
  final List<String> stagingDirs;
  final List<PickedFile> docs;
}
