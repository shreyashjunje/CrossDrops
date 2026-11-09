import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
import '../../core/security/device_identity.dart';

/// A phone as the radar shows it.
class RadarPeer {
  const RadarPeer({
    required this.id,
    required this.name,
    required this.platform,
    required this.hint,
    this.enabled = true,
  });

  final String id;
  final String name;
  final DevicePlatform? platform;

  /// "Same Wi-Fi", "Via iPhone hotspot", or why it cannot be used.
  final String hint;
  final bool enabled;
}

/// How many phones the radar places around the centre; more go in a list
/// under it.
const radarSlots = 6;

/// True when the radar should give way to a plain list: large system text
/// or a screen reader (D-069).
bool useRadarList(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
  return scale >= 1.6 || MediaQuery.accessibleNavigationOf(context);
}

/// Nearby phones as avatars around a pulsing centre (D-069). Tapping one
/// locks on: lime avatar, a ring that tightens, a beam from the centre,
/// the others dim. The pulse runs only while [searching] and nothing is
/// locked, and never under reduced motion.
class Radar extends StatefulWidget {
  const Radar({
    super.key,
    required this.peers,
    required this.searching,
    required this.onTap,
    this.lockedId,
  });

  final List<RadarPeer> peers;
  final bool searching;
  final String? lockedId;
  final void Function(RadarPeer peer) onTap;

  @override
  State<Radar> createState() => _RadarState();
}

class _RadarState extends State<Radar> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: CdMotion.radarPulse,
  );

  /// Clockwise from the right, chosen so labels never sit on the centre.
  static const _angles = [-50.0, 200.0, 20.0, 140.0, -130.0, 80.0];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(Radar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final on = widget.searching && widget.lockedId == null && !reduce;
    if (on && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!on && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Offset _slot(int i, double size) {
    final a = _angles[i] * math.pi / 180;
    final r = size * 0.34;
    return Offset(size / 2 + r * math.cos(a), size / 2 + r * math.sin(a));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return LayoutBuilder(
      builder: (context, box) {
        final size = math.min(box.maxWidth, 360.0);
        final shown = widget.peers.take(radarSlots).toList();
        final lockedIndex = shown.indexWhere((p) => p.id == widget.lockedId);
        return Center(
          child: SizedBox(
            width: size,
            // Room under the lowest slot for its name.
            height: size + 40,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  bottom: 40,
                  child: ExcludeSemantics(
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, _) => CustomPaint(
                        painter: _RadarPainter(
                          ring: c.line,
                          inner: c.surface1,
                          accent: c.accent,
                          pulse: _pulse.isAnimating ? _pulse.value : null,
                          beamTo: lockedIndex < 0
                              ? null
                              : _slot(lockedIndex, size),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: size / 2 - 36,
                  top: size / 2 - 36,
                  child: _You(colors: c),
                ),
                for (final (i, p) in shown.indexed)
                  Positioned(
                    left: (_slot(i, size).dx - 56).clamp(0, size - 112),
                    top: _slot(i, size).dy - 35,
                    width: 112,
                    child: _RadarDevice(
                      key: ValueKey(p.id),
                      peer: p,
                      locked: p.id == widget.lockedId,
                      dimmed:
                          widget.lockedId != null && p.id != widget.lockedId,
                      onTap: p.enabled && widget.lockedId == null
                          ? () => widget.onTap(p)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _You extends StatelessWidget {
  const _You({required this.colors});

  final CdColors colors;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: colors.surface2,
        shape: BoxShape.circle,
        border: Border.all(color: colors.lineStrong),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PhoneGlyph(
            platform: DevicePlatform.current,
            size: 22,
            color: colors.text,
          ),
          const SizedBox(height: 2),
          Text(
            'You',
            textScaler: TextScaler.noScaling,
            style: CdType.overline.copyWith(
              letterSpacing: 0,
              color: colors.text2,
            ),
          ),
        ],
      ),
    ),
  );
}

class _RadarDevice extends StatelessWidget {
  const _RadarDevice({
    super.key,
    required this.peer,
    required this.locked,
    required this.dimmed,
    required this.onTap,
  });

  final RadarPeer peer;
  final bool locked;
  final bool dimmed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final platform = switch (peer.platform) {
      DevicePlatform.ios => 'iPhone',
      DevicePlatform.android => 'Android',
      null => 'Unknown phone',
    };
    // Found: fades and scales in once.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduce ? 1 : 0, end: 1),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.8 + 0.2 * t, child: child),
      ),
      child: AnimatedOpacity(
        opacity: dimmed ? 0.35 : (peer.enabled ? 1 : 0.5),
        duration: reduce ? Duration.zero : CdMotion.slow,
        child: Semantics(
          container: true,
          button: true,
          enabled: onTap != null,
          label:
              '${peer.name}, $platform, ${peer.hint}'
              '${locked ? ', connecting' : ''}',
          hint: peer.enabled ? 'Double-tap to send' : null,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 70,
                  child: Center(
                    child: TweenAnimationBuilder<double>(
                      // The lock-on ring tightens from 1.4 to 1.
                      key: ValueKey(locked),
                      tween: Tween(begin: locked && !reduce ? 1.4 : 1, end: 1),
                      duration: reduce ? Duration.zero : CdMotion.slow,
                      curve: CdMotion.lockOn,
                      builder: (_, s, child) =>
                          Transform.scale(scale: s, child: child),
                      child: DeviceAvatar(
                        name: peer.name,
                        platform: peer.platform,
                        locked: locked,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  peer.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  textScaler: MediaQuery.textScalerOf(context)
                      .clamp(maxScaleFactor: 1.3),
                  style: CdType.titleS.copyWith(fontSize: 13, color: c.text),
                ),
                Text(
                  locked ? 'Connecting…' : peer.hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  textScaler: MediaQuery.textScalerOf(context)
                      .clamp(maxScaleFactor: 1.3),
                  style: CdType.small.copyWith(
                    fontSize: 12,
                    color: locked ? c.accentInk : c.text2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.ring,
    required this.inner,
    required this.accent,
    required this.pulse,
    required this.beamTo,
  });

  final Color ring;
  final Color inner;
  final Color accent;

  /// 0 to 1 while pulsing, null when still.
  final double? pulse;
  final Offset? beamTo;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final max = size.shortestSide / 2;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ring;
    canvas.drawCircle(center, max * 0.5, Paint()..color = inner);
    for (final f in [1.0, 0.75, 0.5]) {
      canvas.drawCircle(center, max * f - 0.5, line);
    }
    final t = pulse;
    if (t != null) {
      final eased = Curves.easeOut.transform(t);
      canvas.drawCircle(
        center,
        36 + (max - 36) * eased,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = accent.withValues(alpha: 0.6 * (1 - t)),
      );
    }
    final to = beamTo;
    if (to != null) {
      final beam = Paint()
        ..color = accent
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      final d = to - center;
      final len = d.distance;
      final dir = d / len;
      // Dashes from the edge of "You" to the edge of the avatar.
      for (var s = 40.0; s < len - 34; s += 12) {
        canvas.drawLine(center + dir * s, center + dir * (s + 2), beam);
      }
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.pulse != pulse ||
      old.beamTo != beamTo ||
      old.ring != ring ||
      old.accent != accent;
}
