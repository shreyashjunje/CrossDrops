import 'package:flutter/material.dart';

import '../../core/security/device_identity.dart';

/// A phone outline that tells the platforms apart without brand logos:
/// a rounded body with a pill at the top for iPhone, a squarer body with
/// a punch-hole camera for Android (D-069). Callers put the word "iPhone"
/// or "Android" next to it; the glyph alone is decoration.
class PhoneGlyph extends StatelessWidget {
  const PhoneGlyph({
    super.key,
    required this.platform,
    this.size = 24,
    this.color,
    this.strokeWidth,
  });

  final DevicePlatform? platform;

  /// Height of the glyph box; the body is about half as wide.
  final double size;
  final Color? color;

  /// Defaults to 2 px at 24, scaled with [size].
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.white;
    if (platform == null) {
      return Icon(Icons.device_unknown_outlined, size: size, color: c);
    }
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _PhonePainter(
          ios: platform == DevicePlatform.ios,
          color: c,
          stroke: strokeWidth ?? size / 12,
        ),
      ),
    );
  }
}

class _PhonePainter extends CustomPainter {
  _PhonePainter({required this.ios, required this.color, required this.stroke});

  final bool ios;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.height / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final body = Rect.fromLTWH(6.5 * u, 2.5 * u, 11 * u, 19 * u);
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, Radius.circular((ios ? 3 : 1.5) * u)),
      paint,
    );
    if (ios) {
      // Dynamic Island.
      canvas.drawLine(
        Offset(10.5 * u, 5.5 * u),
        Offset(13.5 * u, 5.5 * u),
        paint,
      );
    } else {
      // Punch-hole camera and a home bar.
      canvas.drawCircle(
        Offset(12 * u, 5.8 * u),
        0.9 * u,
        Paint()..color = color,
      );
      canvas.drawLine(
        Offset(10 * u, 18.5 * u),
        Offset(14 * u, 18.5 * u),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PhonePainter old) =>
      old.ios != ios || old.color != color || old.stroke != stroke;
}
