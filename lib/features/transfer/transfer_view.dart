import '../../core/engine/send_session.dart';
import '../../core/media/save_target.dart';
import '../../core/protocol/models.dart';
import '../../core/security/device_identity.dart';
import '../../core/storage/transfer_repository.dart';
import '../receive/receive_controller.dart';

/// Where a transfer stands, the same for both directions (D-048).
enum TransferStage {
  /// Sender: reaching the receiver.
  connecting,

  /// Waiting for the receiver's Accept, or for the first bytes after it.
  waiting,
  running,

  /// Sender: connection lost, trying again shortly.
  retrying,

  /// Paused: app in the background, by the user, or waiting for the
  /// sender to reconnect.
  paused,
  done,
  rejected,
  cancelled,
  failed;

  bool get isFinished =>
      this == done || this == rejected || this == cancelled || this == failed;
}

/// One file as the Progress, Done and Failed screens show it.
class TransferFileView {
  const TransferFileView({
    required this.name,
    required this.size,
    required this.doneBytes,
    required this.status,
    this.savedTo,
    this.saveFallback,
    this.location,
    this.error,
  });

  final String name;
  final int size;
  final int doneBytes;
  final FileTransferStatus status;

  /// Received files: where the user finds it.
  final SaveCollection? savedTo;
  final String? saveFallback;

  /// Received files: a path, content URI or `photos:<id>` for Open. Never
  /// shown.
  final String? location;

  /// One of [ErrorCodes] or [SendReasons].
  final String? error;

  double get fraction => size == 0 ? 1 : (doneBytes / size).clamp(0, 1);
}

/// A transfer, sent or received, as the transfer screens show it.
class TransferView {
  const TransferView({
    required this.direction,
    required this.peerName,
    required this.stage,
    required this.files,
    this.peerPlatform,
    this.doneBytes = 0,
    this.bytesPerSecond = 0,
    this.eta,
    this.retryIn,
    this.reason,
    this.neededBytes,
    this.pairingCode,
    this.canResume = false,
    this.pausedByUser = false,
    this.finishedAt,
  });

  /// From the Send flow's state; null before a send starts.
  static TransferView? fromSend(
    SendSnapshot? s, {
    required String peerName,
    String? peerPlatform,
    bool pausedByUser = false,
  }) {
    if (s == null) return null;
    final stage = switch (s.phase) {
      SendPhase.connecting => TransferStage.connecting,
      SendPhase.waitingForAccept => TransferStage.waiting,
      SendPhase.sending => TransferStage.running,
      SendPhase.retrying => TransferStage.retrying,
      SendPhase.paused => TransferStage.paused,
      SendPhase.done =>
        s.savedCount == 0 ? TransferStage.failed : TransferStage.done,
      SendPhase.rejected => TransferStage.rejected,
      SendPhase.cancelled => TransferStage.cancelled,
      SendPhase.failed => TransferStage.failed,
    };
    return TransferView(
      direction: TransferDirection.send,
      peerName: peerName,
      peerPlatform: DevicePlatform.tryParse(peerPlatform ?? ''),
      stage: stage,
      files: [
        for (final f in s.files)
          TransferFileView(
            name: f.name,
            size: f.size,
            doneBytes: f.sentBytes,
            status: f.status,
            error: f.error,
          ),
      ],
      doneBytes: s.sentBytes,
      bytesPerSecond: s.bytesPerSecond,
      eta: s.eta,
      retryIn: s.retryIn,
      reason: s.phase == SendPhase.done && s.savedCount == 0 && s.reason == null
          ? ErrorCodes.fileFailed
          : s.reason,
      neededBytes: s.neededBytes,
      pairingCode: s.pairingCode,
      canResume: s.canResume,
      pausedByUser: pausedByUser && s.phase == SendPhase.paused,
    );
  }

  factory TransferView.fromIncoming(IncomingSession s) => TransferView(
    direction: TransferDirection.receive,
    peerName: s.sender.name,
    peerPlatform: DevicePlatform.tryParse(s.sender.platform),
    stage: _stageOf(s.status),
    files: [
      for (final f in s.files.values)
        TransferFileView(
          name: f.name,
          size: f.size,
          doneBytes: f.receivedBytes,
          status: f.status,
          savedTo: f.savedTo,
          saveFallback: f.saveFallback,
          location: f.savedPath,
          error: f.error,
        ),
    ],
    doneBytes: s.doneBytes,
    bytesPerSecond: s.bytesPerSecond,
    eta: s.eta,
    reason: s.reason,
  );

  /// From the database, for History. Nothing is moving.
  factory TransferView.fromStored(StoredSession s) {
    final platform = DevicePlatform.current;
    final receive = s.direction == TransferDirection.receive;
    return TransferView(
      direction: s.direction,
      peerName: s.peer.name,
      peerPlatform: DevicePlatform.tryParse(s.peer.platform),
      stage: _stageOf(s.status),
      files: [
        for (final f in s.files)
          TransferFileView(
            name: f.name,
            size: f.size,
            doneBytes: f.transferredBytes,
            status: f.status,
            savedTo: receive && f.status == FileTransferStatus.saved
                ? collectionOfLocation(f.finalLocation, platform)
                : null,
            location: receive ? f.finalLocation : null,
            error: f.errorCode,
          ),
      ],
      doneBytes: s.transferredBytes,
      reason: s.reason,
      finishedAt: s.finishedAt ?? s.updatedAt,
    );
  }

  final TransferDirection direction;
  final String peerName;
  final DevicePlatform? peerPlatform;
  final TransferStage stage;
  final List<TransferFileView> files;
  final int doneBytes;
  final double bytesPerSecond;
  final Duration? eta;
  final Duration? retryIn;

  /// Why it stopped: [RejectReasons], [ErrorCodes], [SendReasons], or who
  /// cancelled (`sender`, `receiver`).
  final String? reason;
  final int? neededBytes;

  /// Sender, untrusted receiver: the 6-digit code to compare.
  final String? pairingCode;

  /// Sender: a later run can pick up from here.
  final bool canResume;

  /// Sender: paused with the Pause button, not by the app going away.
  final bool pausedByUser;
  final DateTime? finishedAt;

  bool get sending => direction == TransferDirection.send;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);

  double get fraction =>
      totalBytes == 0 ? 1 : (doneBytes / totalBytes).clamp(0, 1);

  int get savedCount =>
      files.where((f) => f.status == FileTransferStatus.saved).length;

  int get failedCount =>
      files.where((f) => f.status == FileTransferStatus.failed).length;

  /// Done with every file saved.
  bool get isSuccess => stage == TransferStage.done && failedCount == 0;

  /// The file being transferred now, if any.
  TransferFileView? get current {
    for (final f in files) {
      if (!f.status.isTerminal && f.doneBytes > 0) return f;
    }
    for (final f in files) {
      if (!f.status.isTerminal) return f;
    }
    return null;
  }

  static TransferStage _stageOf(SessionStatus s) => switch (s) {
    SessionStatus.offered || SessionStatus.accepted => TransferStage.waiting,
    SessionStatus.transferring ||
    SessionStatus.verifying => TransferStage.running,
    SessionStatus.paused => TransferStage.paused,
    SessionStatus.done => TransferStage.done,
    SessionStatus.rejected => TransferStage.rejected,
    SessionStatus.cancelled => TransferStage.cancelled,
    SessionStatus.failed => TransferStage.failed,
  };
}

/// The collection a stored `finalLocation` points into, or null if it
/// cannot tell.
SaveCollection? collectionOfLocation(
  String? location,
  DevicePlatform platform,
) {
  if (location == null) return null;
  if (location.startsWith('photos:')) return SaveCollection.photos;
  if (location.startsWith('content://')) {
    // content://media/external/images/media/12, .../video/media/12,
    // .../downloads/12 or .../file/12.
    if (location.contains('/images/')) return SaveCollection.photos;
    if (location.contains('/video/')) return SaveCollection.videos;
    return SaveCollection.files;
  }
  return SaveCollection.files;
}
