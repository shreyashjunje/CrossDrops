import 'package:flutter/material.dart';

import '../tokens.dart';

enum BadgeTone { trusted, warning, danger, neutral }

/// A status pill: always an icon and a word, never color alone (D-069).
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
  });

  const StatusBadge.trusted({super.key, this.label = 'Trusted'})
    : tone = BadgeTone.trusted,
      icon = Icons.verified_user_outlined;

  const StatusBadge.firstTime({super.key, this.label = 'First time'})
    : tone = BadgeTone.warning,
      icon = Icons.warning_amber_rounded;

  final String label;
  final BadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final (bg, fg, border) = switch (tone) {
      BadgeTone.trusted => (c.accentSoft, c.accentInk, null),
      BadgeTone.warning => (c.warning, c.onWarning, null),
      BadgeTone.danger => (c.dangerSoft, c.danger, c.dangerLine),
      BadgeTone.neutral => (c.surface3, c.text, null),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: border == null ? null : Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(label, style: CdType.titleS.copyWith(color: fg)),
          ),
        ],
      ),
    );
  }
}

/// Neutral information next to a device, such as "Same Wi-Fi" or
/// "Hotspot": square-ish and outlined, so it never reads as a status.
class HintChip extends StatelessWidget {
  const HintChip({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CdRadius.chip),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: c.text2),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(label, style: CdType.small.copyWith(color: c.text2)),
          ),
        ],
      ),
    );
  }
}
