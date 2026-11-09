import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// The total bar: 10 px, track in surface3, fill in the accent ink, grey
/// while paused. Animates width over 200 ms and never jumps back (D-069).
class CdProgressBar extends StatelessWidget {
  const CdProgressBar({
    super.key,
    required this.value,
    this.paused = false,
    this.semanticLabel,
  });

  /// 0 to 1.
  final double value;
  final bool paused;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final v = value.clamp(0.0, 1.0);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      label: semanticLabel,
      value: '${(v * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          height: 10,
          child: ColoredBox(
            color: c.surface3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AnimatedFractionallySizedBox(
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                widthFactor: v,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: paused ? c.text3 : c.accentInk,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A ring for one file or a compact total. Decoration: the row around it
/// says the percentage.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 28,
    this.stroke = 3.5,
    this.paused = false,
  });

  final double value;
  final double size;
  final double stroke;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(
            value: value.clamp(0.0, 1.0),
            stroke: stroke,
            track: c.surface3,
            fill: paused ? c.text3 : c.accentInk,
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.stroke,
    required this.track,
    required this.fill,
  });

  final double value;
  final double stroke;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(r, 0, 2 * math.pi, false, base);
    if (value <= 0) return;
    canvas.drawArc(
      r,
      -math.pi / 2,
      2 * math.pi * value,
      false,
      base
        ..color = fill
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.fill != fill || old.track != track;
}
