import 'package:flutter/material.dart';

import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
import '../../core/protocol/models.dart';
import '../../core/security/device_identity.dart';
import 'file_thumbnail.dart';
import 'flow_track.dart';
import 'transfer_format.dart';
import 'transfer_view.dart';
import 'widgets.dart';

/// A transfer that is still running: the files flowing between the two
/// phones, big percentage, speed and time left, per-file progress, Pause
/// or Resume (sender) and Cancel (D-069).
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
    final c = context.cd;
    final v = view;
    final percent = (v.fraction * 100).floor();
    final showCode =
        v.sending && v.stage == TransferStage.waiting && v.pairingCode != null;
    final halted =
        v.stage == TransferStage.paused || v.stage == TransferStage.retrying;
    final timeLeft = formatTimeLeft(v.eta);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              CdSpace.gutter,
              8,
              CdSpace.gutter,
              CdSpace.l,
            ),
            children: [
              Row(
                children: [
                  DeviceAvatar(
                    name: v.peerName,
                    platform: v.peerPlatform,
                    size: 44,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      v.sending
                          ? 'Sending to ${v.peerName}'
                          : 'Receiving from ${v.peerName}',
                      style: CdType.titleM.copyWith(
                        fontSize: 17,
                        color: c.text,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FlowTrack(
                sending: v.sending,
                peerName: v.peerName,
                peerPlatform: v.peerPlatform,
                mode: switch (v.stage) {
                  TransferStage.running => FlowMode.flowing,
                  TransferStage.retrying => FlowMode.broken,
                  TransferStage.paused => FlowMode.frozen,
                  _ => FlowMode.waiting,
                },
              ),
              const SizedBox(height: 12),
              Center(
                child: _StageChip(
                  text: stageText(v),
                  tone: switch (v.stage) {
                    TransferStage.running => BadgeTone.trusted,
                    TransferStage.retrying => BadgeTone.warning,
                    _ => BadgeTone.neutral,
                  },
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 16,
                runSpacing: 8,
                children: [
                  ExcludeSemantics(
                    child: Text(
                      '$percent%',
                      style: CdType.displayXL.copyWith(
                        color: halted ? c.text2 : c.text,
                      ),
                    ),
                  ),
                  if (v.stage == TransferStage.running)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Wrap(
                        spacing: 20,
                        children: [
                          _Stat(formatSpeed(v.bytesPerSecond)),
                          if (timeLeft.isNotEmpty) _Stat(timeLeft),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (v.stage == TransferStage.connecting)
                const LinearProgressIndicator(
                  minHeight: 10,
                  semanticsLabel: 'Total progress',
                )
              else
                CdProgressBar(
                  value: v.fraction,
                  paused: halted,
                  semanticLabel: 'Total progress',
                ),
              const SizedBox(height: 8),
              Text(
                '${formatSize(v.doneBytes)} of ${formatSize(v.totalBytes)}'
                ' ${v.sending ? 'sent' : 'received'} · $percent%',
                style: CdType.small.copyWith(color: c.text2),
              ),
              if (showCode) ...[
                const SizedBox(height: 20),
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
              const SizedBox(height: 20),
              Semantics(
                header: true,
                child: Text(
                  '${v.files.length} ${v.files.length == 1 ? 'FILE' : 'FILES'}',
                  style: CdType.overline.copyWith(color: c.text2),
                ),
              ),
              const SizedBox(height: 4),
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
    TransferStage.running => _runningText(v),
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

  /// "Sending 2 of 5", or "Sending 3 files at once · 4 of 10 done" while
  /// several move together (D-068).
  static String _runningText(TransferView v) {
    final verb = v.sending ? 'Sending' : 'Receiving';
    final active = v.files
        .where(
          (f) =>
              f.status == FileTransferStatus.receiving ||
              f.status == FileTransferStatus.verifying,
        )
        .length;
    if (active > 1) {
      final done = v.files.where((f) => f.status.isTerminal).length;
      return '$verb $active files at once · $done of ${v.files.length} done';
    }
    final current = v.current;
    if (current == null) return 'Checking the files…';
    return '$verb ${v.files.indexOf(current) + 1} of ${v.files.length}';
  }
}

/// The stage sentence in a pill, read out when it changes.
class _StageChip extends StatelessWidget {
  const _StageChip({required this.text, required this.tone});

  final String text;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final (bg, fg, dot) = switch (tone) {
      BadgeTone.trusted => (c.accentSoft, c.accentInk, c.accent),
      BadgeTone.warning => (c.warning, c.onWarning, c.onWarning),
      _ => (c.surface2, c.text, c.text3),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: CdType.titleS.copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value);

  /// "18.4 MB/s", "7 s left": the unit says what it is.
  final String value;

  @override
  Widget build(BuildContext context) => Text(
    value,
    style: CdType.h2.copyWith(
      color: context.cd.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
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
    DevicePlatform.ios => const NoticeCard(
      tone: NoticeTone.accent,
      icon: Icons.phonelink_lock_outlined,
      text:
          'Keep CrossDrop open and the screen on until the transfer '
          'finishes. If you leave, it pauses and continues when you come '
          'back.',
    ),
    DevicePlatform.android => const NoticeCard(
      icon: Icons.notifications_active_outlined,
      text:
          'You can switch apps: the transfer continues and shows in a '
          'notification. Keep CrossDrop open on the other phone too.',
    ),
  };
}

/// One file: its preview, name and size, and a ring with the percentage,
/// a check when saved, or an error mark.
class FileProgressRow extends StatelessWidget {
  const FileProgressRow({super.key, required this.file});

  final TransferFileView file;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final percent = (file.fraction * 100).floor();
    final Widget trailing = switch (file.status) {
      FileTransferStatus.saved => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
        child: Icon(
          Icons.check_rounded,
          size: 18,
          color: c.onAccent,
          semanticLabel: 'done',
        ),
      ),
      FileTransferStatus.failed => Icon(
        Icons.error_outline_rounded,
        color: c.danger,
        semanticLabel: 'failed',
      ),
      FileTransferStatus.verifying => Text(
        'checking',
        style: CdType.small.copyWith(color: c.text2),
      ),
      _ => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$percent%',
            style: CdType.small.copyWith(
              fontWeight: FontWeight.w600,
              color: c.text,
            ),
          ),
          const SizedBox(width: 8),
          ProgressRing(value: file.fraction),
        ],
      ),
    };
    // One node for screen readers: "IMG_1.HEIC, 3.0 MB, 40%".
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            FileThumbnail(thumb: file.thumb, kind: file.kind, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CdType.bodyM.copyWith(color: c.text),
                  ),
                  Text(
                    formatSize(file.size),
                    style: CdType.small.copyWith(color: c.text2),
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
    final wide = CdButtonStyles.wide;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CdSpace.gutter,
          8,
          CdSpace.gutter,
          16,
        ),
        child: Row(
          children: [
            if (view.pausedByUser) ...[
              Expanded(
                child: FilledButton.icon(
                  style: wide,
                  onPressed: onResume,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Resume'),
                ),
              ),
              const SizedBox(width: 12),
            ] else if (canPause) ...[
              Expanded(
                child: FilledButton.icon(
                  style: CdButtonStyles.secondary(context).merge(wide),
                  onPressed: onPause,
                  icon: const Icon(Icons.pause_rounded),
                  label: const Text('Pause'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: OutlinedButton.icon(
                style: CdButtonStyles.danger(context).merge(wide),
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
