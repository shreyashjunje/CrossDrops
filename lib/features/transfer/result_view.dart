import 'package:flutter/material.dart';

import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
import '../../core/protocol/models.dart';
import '../../core/security/device_identity.dart';
import 'failure_messages.dart';
import 'file_thumbnail.dart';
import 'transfer_format.dart';
import 'transfer_view.dart';

/// A finished transfer (D-069). Done: a check that draws itself, what
/// arrived as thumbnails, where it was saved, Open. Failed (or partly):
/// "What happened" and "What to do" in plain words, with one button for
/// the next step (ARCHITECTURE.md, "Failure handling").
class ResultView extends StatelessWidget {
  const ResultView({
    super.key,
    required this.view,
    required this.platform,
    this.onOpen,
    this.onAction,
    this.onTrust,
    this.onClose,
  });

  final TransferView view;

  /// This phone's platform, for where files were saved.
  final DevicePlatform platform;
  final void Function(TransferFileView file)? onOpen;
  final void Function(NextAction action)? onAction;

  /// Sender: "Trust" the receiver after a send to an untrusted one.
  final VoidCallback? onTrust;
  final VoidCallback? onClose;

  /// Files listed by name; more are counted.
  static const maxListed = 100;

  /// Thumbnails in the grid; more are counted on the last tile.
  static const maxThumbs = 8;

  @override
  Widget build(BuildContext context) {
    final failure = describeOutcome(view);
    final arrived = [
      for (final f in view.files)
        if (f.status == FileTransferStatus.saved) f,
    ];
    final failed = [
      for (final f in view.files)
        if (f.status == FileTransferStatus.failed) f,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              CdSpace.gutter,
              16,
              CdSpace.gutter,
              CdSpace.l,
            ),
            children: [
              _Header(view: view, failure: failure),
              if (failure != null) ...[
                const SizedBox(height: 24),
                _FailureCard(failure: failure, onAction: onAction),
              ],
              if (onTrust != null) ...[
                const SizedBox(height: 20),
                _TrustCard(peerName: view.peerName, onTrust: onTrust!),
              ],
              if (arrived.isNotEmpty) ...[
                const SizedBox(height: 20),
                _ArrivedList(
                  files: arrived,
                  sending: view.sending,
                  platform: platform,
                  onOpen: onOpen,
                ),
              ],
              if (failed.isNotEmpty) ...[
                const SizedBox(height: 24),
                _FailedList(files: failed),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              CdSpace.gutter,
              8,
              CdSpace.gutter,
              16,
            ),
            child: FilledButton(
              // After a failure the next step is the lime button above.
              style: failure == null
                  ? CdButtonStyles.wide
                  : CdButtonStyles.secondary(context)
                        .merge(CdButtonStyles.wide),
              onPressed: onClose,
              child: const Text('Done'),
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.view, required this.failure});

  final TransferView view;
  final FailureMessage? failure;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final v = view;
    final n = v.savedCount;
    final files = '$n ${n == 1 ? 'file' : 'files'}';
    final title =
        failure?.title ?? (v.sending ? '$files sent' : '$files received');
    final savedBytes = v.files
        .where((f) => f.status == FileTransferStatus.saved)
        .fold(0, (sum, f) => sum + f.size);
    final quiet =
        v.stage == TransferStage.cancelled || v.stage == TransferStage.rejected;
    final partly = v.stage == TransferStage.done && v.failedCount > 0;
    return Semantics(
      liveRegion: true,
      child: Column(
        children: [
          if (failure == null)
            const _SuccessMark()
          else
            _FailureMark(
              tone: quiet
                  ? NoticeTone.neutral
                  : partly
                  ? NoticeTone.warning
                  : NoticeTone.danger,
              icon: quiet
                  ? Icons.block_rounded
                  : partly
                  ? Icons.rule_rounded
                  : Icons.error_outline_rounded,
            ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: CdType.h1.copyWith(color: c.text),
          ),
          const SizedBox(height: 4),
          Text(
            [
              v.sending ? 'to ${v.peerName}' : 'from ${v.peerName}',
              if (n > 0) formatSize(savedBytes),
            ].join(' · '),
            textAlign: TextAlign.center,
            style: CdType.bodyM.copyWith(color: c.text2),
          ),
          if (n > 0) ...[
            const SizedBox(height: 12),
            const StatusBadge(
              label: 'Original quality',
              tone: BadgeTone.trusted,
              icon: Icons.verified_user_outlined,
            ),
            const SizedBox(height: 8),
            Text(
              v.sending
                  ? 'The other phone checked every file with SHA-256. Each '
                        'one is identical to yours, byte for byte.'
                  : 'Every file was checked with SHA-256. Each one is '
                        'identical to the original, byte for byte.',
              textAlign: TextAlign.center,
              style: CdType.small.copyWith(color: c.text3),
            ),
          ],
        ],
      ),
    );
  }
}

/// A lime disc whose check draws itself, with one ring that fades out.
/// Shown once; still under reduced motion.
class _SuccessMark extends StatefulWidget {
  const _SuccessMark();

  @override
  State<_SuccessMark> createState() => _SuccessMarkState();
}

class _SuccessMarkState extends State<_SuccessMark>
    with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _anim.value = 1;
    } else if (_anim.value == 0 && !_anim.isAnimating) {
      _anim.forward();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 120,
        child: AnimatedBuilder(
          animation: _anim,
          builder: (_, _) {
            final t = _anim.value;
            // 0-300 ms: the disc pops; 150-450 ms: the check draws;
            // 200-900 ms: one ring fades out.
            final pop = Curves.easeOutBack.transform((t / 0.33).clamp(0, 1));
            final draw = Curves.easeInOut.transform(
              ((t - 0.17) / 0.33).clamp(0, 1),
            );
            final ring = ((t - 0.22) / 0.78).clamp(0.0, 1.0);
            return CustomPaint(
              painter: _CheckPainter(
                fill: c.accent,
                ink: c.onAccent,
                pop: pop,
                draw: draw,
                ring: ring,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({
    required this.fill,
    required this.ink,
    required this.pop,
    required this.draw,
    required this.ring,
  });

  final Color fill;
  final Color ink;
  final double pop;
  final double draw;
  final double ring;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const r = 48.0;
    if (ring > 0 && ring < 1) {
      canvas.drawCircle(
        center,
        r * (1 + 0.9 * ring),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = fill.withValues(alpha: 0.5 * (1 - ring)),
      );
    }
    canvas.drawCircle(center, r * (0.6 + 0.4 * pop), Paint()..color = fill);
    if (draw <= 0) return;
    // The check, from 24-px icon coordinates scaled to the disc.
    const s = 2.0;
    final a = center + const Offset((5 - 12) * s, (12.5 - 12) * s);
    final b = center + const Offset((9.5 - 12) * s, (17 - 12) * s);
    final e = center + const Offset((19 - 12) * s, (7.5 - 12) * s);
    final first = (b - a).distance, second = (e - b).distance;
    final len = (first + second) * draw;
    final path = Path()..moveTo(a.dx, a.dy);
    if (len <= first) {
      final p = a + (b - a) * (len / first);
      path.lineTo(p.dx, p.dy);
    } else {
      path.lineTo(b.dx, b.dy);
      final p = b + (e - b) * ((len - first) / second);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = ink,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.pop != pop || old.draw != draw || old.ring != ring;
}

class _FailureMark extends StatelessWidget {
  const _FailureMark({required this.tone, required this.icon});

  final NoticeTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final (bg, line, fg) = switch (tone) {
      NoticeTone.danger => (c.dangerSoft, c.dangerLine, c.danger),
      NoticeTone.warning => (c.warningSoft, c.warningLine, c.warningInk),
      _ => (c.surface2, c.line, c.text2),
    };
    return ExcludeSemantics(
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(CdRadius.card),
          border: Border.all(color: line),
        ),
        child: Icon(icon, size: 34, color: fg),
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.failure, this.onAction});

  final FailureMessage failure;
  final void Function(NextAction action)? onAction;

  static String? _label(NextAction a) => switch (a) {
    NextAction.resume => 'Resume',
    NextAction.sendAgain => 'Send again',
    NextAction.scanQr => 'Scan QR code',
    NextAction.findHelp => 'Other ways to connect',
    NextAction.none => null,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final label = _label(failure.action);
    Widget overline(String t) => Semantics(
      header: true,
      child: Text(t, style: CdType.overline.copyWith(color: c.text3)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        overline('What happened'),
        const SizedBox(height: 6),
        Text(failure.reason, style: CdType.bodyL.copyWith(color: c.text2)),
        const SizedBox(height: 18),
        overline('What to do'),
        const SizedBox(height: 6),
        Text(failure.next, style: CdType.bodyL.copyWith(color: c.text)),
        if (label != null && onAction != null) ...[
          const SizedBox(height: 20),
          FilledButton(
            style: CdButtonStyles.wide,
            onPressed: () => onAction!(failure.action),
            child: Text(label),
          ),
        ],
      ],
    );
  }
}

class _TrustCard extends StatelessWidget {
  const _TrustCard({required this.peerName, required this.onTrust});

  final String peerName;
  final VoidCallback onTrust;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: BorderRadius.circular(CdRadius.button),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user_outlined, color: c.text2),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Next time, sending to it skips the code check, and a '
                  'different phone using its name is reported.',
                  style: CdType.bodyM.copyWith(color: c.text2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onTrust, child: Text('Trust $peerName')),
        ],
      ),
    );
  }
}

/// What arrived as thumbnails, rising in one by one (40 ms apart, at most
/// eight), still under reduced motion.
class _ThumbGrid extends StatelessWidget {
  const _ThumbGrid({required this.files});

  final List<TransferFileView> files;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final shown = files.take(ResultView.maxThumbs).toList();
    final more = files.length - shown.length;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, box) {
          const gap = 6.0;
          final size = (box.maxWidth - gap * 3) / 4;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final (i, f) in shown.indexed)
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: reduce ? 1 : 0, end: 1),
                  duration: reduce
                      ? Duration.zero
                      : Duration(milliseconds: 250 + 40 * i),
                  curve: Curves.easeOutCubic,
                  builder: (_, t, child) => Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - t)),
                      child: child,
                    ),
                  ),
                  child: Stack(
                    children: [
                      FileThumbnail(thumb: f.thumb, kind: f.kind, size: size),
                      if (more > 0 && i == shown.length - 1)
                        Container(
                          width: size,
                          height: size,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xB30E1116),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '+${more + 1}',
                            style: CdType.h3.copyWith(
                              color: CdColors.dark.text,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ArrivedList extends StatelessWidget {
  const _ArrivedList({
    required this.files,
    required this.sending,
    required this.platform,
    this.onOpen,
  });

  final List<TransferFileView> files;
  final bool sending;
  final DevicePlatform platform;
  final void Function(TransferFileView file)? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final where = <String>{
      for (final f in files)
        if (f.savedTo case final to?)
          formatSavedTo(to, null, platform: platform),
    };
    final more = files.length - ResultView.maxListed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (where.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: c.surface1,
              borderRadius: BorderRadius.circular(CdRadius.button),
              border: Border.all(color: c.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.surface3,
                    borderRadius: BorderRadius.circular(CdRadius.tile),
                  ),
                  child: Icon(Icons.photo_library_outlined, color: c.text),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          'Where to find them',
                          style: CdType.small.copyWith(color: c.text2),
                        ),
                      ),
                      for (final w in where)
                        Text(
                          w,
                          style: CdType.titleS.copyWith(
                            fontSize: 15,
                            color: c.text,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        _ThumbGrid(files: files),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            sending ? 'SENT' : 'ARRIVED',
            style: CdType.overline.copyWith(color: c.text2),
          ),
        ),
        for (final f in files.take(ResultView.maxListed))
          _ArrivedRow(
            file: f,
            platform: platform,
            // Sent files are on the other phone.
            onOpen: sending ? null : onOpen,
          ),
        if (more > 0)
          Text('and $more more', style: CdType.small.copyWith(color: c.text2)),
      ],
    );
  }
}

/// A thumbnail with a small status mark on its corner.
class _MarkedThumb extends StatelessWidget {
  const _MarkedThumb({required this.file, required this.ok});

  final TransferFileView file;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        FileThumbnail(thumb: file.thumb, kind: file.kind, size: 48),
        Positioned(
          right: -4,
          bottom: -4,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: ok ? c.accent : c.danger,
              shape: BoxShape.circle,
              border: Border.all(color: c.bg, width: 2),
            ),
            child: Icon(
              ok ? Icons.check_rounded : Icons.close_rounded,
              size: 12,
              color: ok ? c.onAccent : c.onDanger,
              semanticLabel: ok ? 'saved' : 'not saved',
            ),
          ),
        ),
      ],
    );
  }
}

class _ArrivedRow extends StatelessWidget {
  const _ArrivedRow({required this.file, required this.platform, this.onOpen});

  final TransferFileView file;
  final DevicePlatform platform;
  final void Function(TransferFileView file)? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final fallback = file.saveFallback;
    final location = file.location;
    final canOpen = onOpen != null && location != null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _MarkedThumb(file: file, ok: true),
      title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: fallback == null || file.savedTo == null
          ? Text(
              '${formatSize(file.size)} · ${formatExactBytes(file.size)}\n'
              'Original quality, verified',
            )
          : Text(
              formatSavedTo(file.savedTo!, fallback, platform: platform),
              style: TextStyle(color: c.warningInk),
            ),
      isThreeLine: fallback == null || file.savedTo == null,
      trailing: canOpen
          ? TextButton(
              onPressed: () => onOpen!(file),
              child: Text(
                location.startsWith('photos:') ? 'Open Photos' : 'Open',
                semanticsLabel: location.startsWith('photos:')
                    ? 'Open Photos'
                    : 'Open ${file.name}',
              ),
            )
          : null,
    );
  }
}

class _FailedList extends StatelessWidget {
  const _FailedList({required this.files});

  final List<TransferFileView> files;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final more = files.length - ResultView.maxListed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Not saved',
            style: CdType.titleM.copyWith(color: c.text),
          ),
        ),
        for (final f in files.take(ResultView.maxListed))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _MarkedThumb(file: f, ok: false),
            title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(describeFileError(f.error)),
          ),
        if (more > 0)
          Text('and $more more', style: CdType.small.copyWith(color: c.text2)),
      ],
    );
  }
}
