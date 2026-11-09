import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../tokens.dart';

enum NoticeTone { neutral, accent, warning, danger }

/// A highlighted message: neutral information, a lime-ink hint, a warning
/// or a danger. Tone changes both fill and icon color, and the icon shape
/// carries the meaning too (D-069).
class NoticeCard extends StatelessWidget {
  const NoticeCard({
    super.key,
    required this.text,
    this.title,
    this.icon,
    this.tone = NoticeTone.neutral,
    this.action,
  });

  final String text;
  final String? title;
  final IconData? icon;
  final NoticeTone tone;

  /// A compact button under the text, such as "Select more".
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final (bg, border, iconColor) = switch (tone) {
      NoticeTone.neutral => (c.surface1, c.line, c.text2),
      NoticeTone.accent => (c.surface1, c.line, c.accentInk),
      NoticeTone.warning => (c.warningSoft, c.warningLine, c.warningInk),
      NoticeTone.danger => (c.dangerSoft, c.dangerLine, c.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(CdRadius.button),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: CdType.titleM.copyWith(color: c.text)),
                  const SizedBox(height: 4),
                ],
                Text(
                  text,
                  style: CdType.bodyM.copyWith(
                    color: title == null ? c.text : c.text2,
                  ),
                ),
                if (action != null) ...[const SizedBox(height: 8), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Title, one sentence and one action, with the two-phone drawing.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: SizedBox(
            width: 96,
            height: 64,
            child: CustomPaint(
              painter: TwoPhonesPainter(
                line: c.lineStrong,
                accent: c.accentInk,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: CdType.h3.copyWith(color: c.text),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: CdType.bodyM.copyWith(color: c.text2),
          ),
        ),
        if (actionLabel != null) ...[
          const SizedBox(height: 16),
          FilledButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    );
  }
}

/// Two phone outlines with a dotted lime arrow between them.
class TwoPhonesPainter extends CustomPainter {
  TwoPhonesPainter({required this.line, required this.accent});

  final Color line;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 96;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = line;
    canvas.drawRRect(
      RRect.fromLTRBR(8 * s, 6 * s, 34 * s, 52 * s, Radius.circular(6 * s)),
      p,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(62 * s, 6 * s, 88 * s, 52 * s, Radius.circular(4 * s)),
      p,
    );
    p.color = accent;
    for (var x = 40.0; x < 54; x += 6) {
      canvas.drawLine(Offset(x * s, 29 * s), Offset((x + 2) * s, 29 * s), p);
    }
    canvas.drawPath(
      Path()
        ..moveTo(52 * s, 25 * s)
        ..lineTo(56 * s, 29 * s)
        ..lineTo(52 * s, 33 * s),
      p,
    );
  }

  @override
  bool shouldRepaint(TwoPhonesPainter old) =>
      old.line != line || old.accent != accent;
}

/// Shown right before a system permission prompt, never at launch.
class PermissionCard extends StatelessWidget {
  const PermissionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String text;
  final String buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(CdRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: c.surface3,
                borderRadius: BorderRadius.circular(CdRadius.tile),
              ),
              child: Icon(icon, color: c.accentInk),
            ),
          ),
          const SizedBox(height: 12),
          Text(title, style: CdType.h3.copyWith(color: c.text)),
          const SizedBox(height: 6),
          Text(text, style: CdType.bodyM.copyWith(color: c.text2)),
          const SizedBox(height: 16),
          FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
        ],
      ),
    );
  }
}

/// A QR code, always dark on white with a quiet zone, even in dark mode,
/// so every camera reads it. The payload is never logged (hard rule 7).
class QrCard extends StatelessWidget {
  const QrCard({
    super.key,
    required this.data,
    required this.semanticLabel,
    this.size = 240,
    this.caption,
  });

  final String data;
  final String semanticLabel;
  final double size;
  final String? caption;

  static const _ink = Color(0xFF0E1116);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(CdRadius.dialog),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(
            data: data,
            size: size,
            padding: EdgeInsets.zero,
            backgroundColor: const Color(0xFFFFFFFF),
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: _ink,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: _ink,
            ),
            semanticsLabel: semanticLabel,
          ),
          if (caption != null) ...[
            const SizedBox(height: 12),
            Text(caption!, style: CdType.titleS.copyWith(color: _ink)),
          ],
        ],
      ),
    );
  }
}

/// Button looks the theme does not cover: secondary (filled grey) and
/// danger (soft red with a red label).
abstract final class CdButtonStyles {
  static ButtonStyle secondary(BuildContext context) {
    final c = context.cd;
    return FilledButton.styleFrom(
      backgroundColor: c.surface3,
      foregroundColor: c.text,
      disabledBackgroundColor: c.surface2,
      disabledForegroundColor: c.text3,
    );
  }

  static ButtonStyle danger(BuildContext context) {
    final c = context.cd;
    return OutlinedButton.styleFrom(
      backgroundColor: c.dangerSoft,
      foregroundColor: c.danger,
      side: BorderSide(color: c.dangerLine),
    );
  }

  /// Full width and 56 tall, for the one main action of a screen.
  static const ButtonStyle wide = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size.fromHeight(CdSpace.buttonHeight)),
  );
}
