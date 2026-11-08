import 'package:flutter/material.dart';

import '../../core/protocol/models.dart';
import '../../core/security/device_identity.dart';
import 'file_thumbnail.dart';
import 'transfer_format.dart';
import 'transfer_view.dart';
import 'widgets.dart';

/// A transfer that is still running: total and per-file progress, speed,
/// time left, Pause or Resume (sender), and Cancel.
class ProgressView extends StatelessWidget {
  const ProgressView({
    super.key,
    required this.view,
    required this.platform,
    this.onPause,
    this.onResume,
    this.onCancel,
  });

  final TransferView view;

  /// This phone's platform: iPhone gets "Keep CrossDrop open and the
  /// screen on".
  final DevicePlatform platform;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final theme = Theme.of(context);
    final percent = (v.fraction * 100).floor();
    final showCode =
        v.sending && v.stage == TransferStage.waiting && v.pairingCode != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  PlatformIcon(platform: v.peerPlatform, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      v.sending
                          ? 'Sending to ${v.peerName}'
                          : 'Receiving from ${v.peerName}',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(stageText(v), style: theme.textTheme.titleMedium),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: v.stage == TransferStage.connecting ? null : v.fraction,
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
                semanticsLabel: 'Total progress',
                semanticsValue: '$percent%',
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 16,
                children: [
                  Text(
                    '${formatSize(v.doneBytes)} of ${formatSize(v.totalBytes)}'
                    ' ${v.sending ? 'sent' : 'received'} · $percent%',
                  ),
                  if (v.stage == TransferStage.running)
                    Text(
                      [
                        formatSpeed(v.bytesPerSecond),
                        if (formatTimeLeft(v.eta) case final t
                            when t.isNotEmpty)
                          t,
                      ].join(' · '),
                    ),
                ],
              ),
              if (showCode) ...[
                const SizedBox(height: 16),
                PairingCodeBox(
                  code: v.pairingCode!,
                  caption: 'Check that the other phone shows this code:',
                  footer:
                      'If it shows a different code, tap Cancel: you may '
                      'not be connected to the phone you think.',
                ),
              ],
              const SizedBox(height: 16),
              KeepOpenNote(platform: platform, sending: v.sending),
              const SizedBox(height: 16),
              Text(
                '${v.files.length} ${v.files.length == 1 ? 'file' : 'files'}',
                style: theme.textTheme.titleSmall,
              ),
              for (final f in v.files) FileProgressRow(file: f),
            ],
          ),
        ),
        _Buttons(
          view: v,
          onPause: onPause,
          onResume: onResume,
          onCancel: onCancel,
        ),
      ],
    );
  }

  /// One line on where the transfer stands.
  static String stageText(TransferView v) => switch (v.stage) {
    TransferStage.connecting => 'Connecting…',
    TransferStage.waiting when v.sending =>
      'Waiting for ${v.peerName} to accept…',
    TransferStage.waiting => 'Accepted. Waiting for the first bytes…',
    TransferStage.running =>
      v.current == null
          ? 'Checking the files…'
          : '${v.sending ? 'Sending' : 'Receiving'} '
                '${v.files.indexOf(v.current!) + 1} of ${v.files.length}',
    TransferStage.retrying =>
      'Connection lost. Trying again in '
          '${(v.retryIn?.inMilliseconds ?? 0) ~/ 1000 + 1} s…',
    TransferStage.paused when v.pausedByUser => 'Paused. Tap Resume to go on.',
    TransferStage.paused when v.sending =>
      'Paused while CrossDrop is in the background',
    TransferStage.paused => 'Paused. Waiting for ${v.peerName} to reconnect…',
    TransferStage.done => 'Done',
    TransferStage.rejected => 'Declined',
    TransferStage.cancelled => 'Cancelled',
    TransferStage.failed => 'Stopped',
  };
}

/// iPhone: the app must stay open with the screen on (ARCHITECTURE.md,
/// "Screen lock during transfer"). Android: the notification keeps it
/// going.
class KeepOpenNote extends StatelessWidget {
  const KeepOpenNote({
    super.key,
    required this.platform,
    required this.sending,
  });

  final DevicePlatform platform;
  final bool sending;

  @override
  Widget build(BuildContext context) => switch (platform) {
    DevicePlatform.ios => const WarningBox(
      icon: Icons.phonelink_lock,
      error: false,
      text:
          'Keep CrossDrop open and the screen on until the transfer '
          'finishes. If you leave, it pauses and continues when you come '
          'back.',
    ),
    DevicePlatform.android => const WarningBox(
      icon: Icons.notifications_active_outlined,
      error: false,
      text:
          'You can switch apps: the transfer continues and shows in a '
          'notification. Keep CrossDrop open on the other phone too.',
    ),
  };
}

/// One file: its preview, name, a small bar, and the percentage or a
/// status icon.
class FileProgressRow extends StatelessWidget {
  const FileProgressRow({super.key, required this.file});

  final TransferFileView file;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percent = (file.fraction * 100).floor();
    final Widget trailing = switch (file.status) {
      FileTransferStatus.saved => Icon(
        Icons.check_circle,
        color: scheme.primary,
        semanticLabel: 'done',
      ),
      FileTransferStatus.failed => Icon(
        Icons.error,
        color: scheme.error,
        semanticLabel: 'failed',
      ),
      FileTransferStatus.verifying => const Text('checking'),
      _ => Text('$percent%'),
    };
    // One node for screen readers: "IMG_1.HEIC, 40%".
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            FileThumbnail(thumb: file.thumb, kind: file.kind, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    formatSize(file.size),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  ExcludeSemantics(
                    child: LinearProgressIndicator(value: file.fraction),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons({
    required this.view,
    this.onPause,
    this.onResume,
    this.onCancel,
  });

  final TransferView view;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final canPause =
        view.sending &&
        (view.stage == TransferStage.running ||
            view.stage == TransferStage.retrying);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.close),
                label: const Text('Cancel'),
              ),
            ),
            if (view.pausedByUser) ...[
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onResume,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Resume'),
                ),
              ),
            ] else if (canPause) ...[
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onPause,
                  icon: const Icon(Icons.pause),
                  label: const Text('Pause'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
