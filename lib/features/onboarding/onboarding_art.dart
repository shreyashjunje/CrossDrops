import 'package:flutter/material.dart';

import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
import '../../core/security/device_identity.dart';

/// The picture above each onboarding page (D-069). Decoration only: the
/// page title and text say everything.
class OnboardingArt extends StatelessWidget {
  const OnboardingArt({super.key, required this.index, required this.platform});

  final int index;
  final DevicePlatform platform;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 240,
      // Never taller or wider than its box, whatever the fonts do.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: switch (index) {
          0 => const _TwoPhones(),
          1 when platform == DevicePlatform.ios => const _AllowPrompt(),
          1 => const _NoInternet(),
          _ => const _Ladder(),
        },
      ),
    ),
  );
}

/// Two phones with CrossDrop open; a file hops across three times.
class _TwoPhones extends StatefulWidget {
  const _TwoPhones();

  @override
  State<_TwoPhones> createState() => _TwoPhonesState();
}

class _TwoPhonesState extends State<_TwoPhones>
    with SingleTickerProviderStateMixin {
  late final _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _hop.value = 0.5;
    } else if (!_hop.isAnimating && _hop.value == 0) {
      // A few hops, then rest: a loop would distract while reading.
      _hop.repeat(count: 3);
    }
  }

  @override
  void dispose() {
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    // The glyph draws in a square; the phone body is the middle half.
    Widget phone(DevicePlatform p) => Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 100,
          height: 200,
          child: OverflowBox(
            maxWidth: 200,
            child: PhoneGlyph(
              platform: p,
              size: 200,
              color: c.text,
              strokeWidth: 3,
            ),
          ),
        ),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: c.accent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.swap_horiz_rounded, color: c.onAccent),
        ),
      ],
    );
    return SizedBox(
      width: 300,
      height: 200,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          phone(DevicePlatform.ios),
          Expanded(
            child: SizedBox(
              height: 24,
              child: AnimatedBuilder(
                animation: _hop,
                builder: (_, _) => CustomPaint(
                  painter: _HopPainter(
                    t: _hop.value,
                    line: c.lineStrong,
                    tile: c.surface3,
                    edge: c.accent,
                  ),
                ),
              ),
            ),
          ),
          phone(DevicePlatform.android),
        ],
      ),
    );
  }
}

class _HopPainter extends CustomPainter {
  _HopPainter({
    required this.t,
    required this.line,
    required this.tile,
    required this.edge,
  });

  final double t;
  final Color line;
  final Color tile;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = line
        ..strokeWidth = 2,
    );
    const s = 18.0;
    final x = (size.width - s) * Curves.easeInOut.transform(t);
    final fade = t < 0.15 ? t / 0.15 : (t > 0.85 ? (1 - t) / 0.15 : 1.0);
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y - s / 2, s, s),
      const Radius.circular(5),
    );
    canvas.drawRRect(r, Paint()..color = tile.withValues(alpha: fade));
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = edge.withValues(alpha: fade),
    );
  }

  @override
  bool shouldRepaint(_HopPainter old) => old.t != t;
}

/// A sketch of iPhone's Local Network question with Allow marked. It
/// explains the real prompt that follows; it is not that prompt.
class _AllowPrompt extends StatelessWidget {
  const _AllowPrompt();

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return SizedBox(
      width: 290,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: c.lineStrong),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Text(
                    '"CrossDrop" would like to find and connect to devices '
                    'on your local network.',
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: CdType.titleS.copyWith(fontSize: 15, color: c.text),
                  ),
                ),
                Container(height: 1, color: c.lineStrong),
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: Text(
                            "Don't Allow",
                            textScaler: TextScaler.noScaling,
                            style: CdType.bodyM.copyWith(color: c.text2),
                          ),
                        ),
                      ),
                      Container(width: 1, color: c.lineStrong),
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(
                              bottomRight: Radius.circular(19),
                            ),
                            border: Border.all(color: c.accent, width: 2),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Allow',
                            textScaler: TextScaler.noScaling,
                            style: CdType.titleS.copyWith(
                              fontSize: 15,
                              color: c.text,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tap this one',
                textScaler: TextScaler.noScaling,
                style: CdType.titleS.copyWith(color: c.accentInk),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_upward_rounded, size: 18, color: c.accentInk),
            ],
          ),
        ],
      ),
    );
  }
}

/// Android: Wi-Fi with no cloud in between.
class _NoInternet extends StatelessWidget {
  const _NoInternet();

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    Widget tile(IconData icon, {bool off = false}) => Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: off ? c.surface1 : c.accent,
        borderRadius: BorderRadius.circular(CdRadius.card),
        border: Border.all(color: off ? c.line : c.accentPressed),
      ),
      child: Icon(icon, size: 34, color: off ? c.text3 : c.onAccent),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        tile(Icons.wifi_rounded),
        const SizedBox(width: 24),
        tile(Icons.cloud_off_rounded, off: true),
      ],
    );
  }
}

/// The three ways to connect, in the order the app tries them.
class _Ladder extends StatelessWidget {
  const _Ladder();

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    Widget row(String n, String title, String sub, {bool first = false}) =>
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.surface1,
            borderRadius: BorderRadius.circular(CdRadius.button),
            border: Border.all(color: first ? c.lineStrong : c.line),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: first ? c.accent : c.surface3,
                  borderRadius: BorderRadius.circular(CdRadius.tile),
                ),
                child: Text(
                  n,
                  textScaler: TextScaler.noScaling,
                  style: CdType.h3.copyWith(color: first ? c.onAccent : c.text),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      textScaler: TextScaler.noScaling,
                      style: CdType.titleS.copyWith(
                        fontSize: 15,
                        color: c.text,
                      ),
                    ),
                    Text(
                      sub,
                      textScaler: TextScaler.noScaling,
                      style: CdType.small.copyWith(color: c.text2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    return SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row(
            '1',
            'Same Wi-Fi',
            'Phones find each other by themselves',
            first: true,
          ),
          row('2', 'Scan a QR code', 'When the Wi-Fi hides phones'),
          row('3', 'Hotspot mode', 'No shared Wi-Fi at all'),
        ],
      ),
    );
  }
}
