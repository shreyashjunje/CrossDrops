import 'package:flutter/material.dart';

import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
import '../../core/security/device_identity.dart';

enum FlowMode {
  /// Before the first bytes: files stacked at the sender.
  waiting,

  /// Files glide from the sender to the receiver.
  flowing,

  /// Paused: files stopped on the track.
  frozen,

  /// Connection lost: the track is broken with a warning mark.
  broken,
}

/// The transfer moment (D-069): two phones and small file tiles moving
/// from one to the other. The sender is always on the left. Under reduced
/// motion the tiles stand still at even spacing. Decoration: the stage
/// chip under it says the same in words.
class FlowTrack extends StatefulWidget {
  const FlowTrack({
    super.key,
    required this.sending,
    required this.peerName,
    required this.peerPlatform,
    required this.mode,
  });

  final bool sending;
  final String peerName;
  final DevicePlatform? peerPlatform;
  final FlowMode mode;

  @override
  State<FlowTrack> createState() => _FlowTrackState();
}

class _FlowTrackState extends State<FlowTrack>
    with SingleTickerProviderStateMixin {
  late final _flow = AnimationController(
    vsync: this,
    duration: CdMotion.flowLoop,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(FlowTrack old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final on = widget.mode == FlowMode.flowing && !reduce;
    if (on && !_flow.isAnimating) {
      _flow.repeat();
    } else if (!on && _flow.isAnimating) {
      _flow.stop();
    }
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final me = DevicePlatform.current;
    final first = widget.peerName.split(' ').first.replaceAll("'s", '');
    final (leftPlatform, leftLabel, rightPlatform, rightLabel) = widget.sending
        ? (me, 'You', widget.peerPlatform, first)
        : (widget.peerPlatform, first, me, 'You');
    return ExcludeSemantics(
      child: SizedBox(
        height: 92,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Phone(platform: leftPlatform, label: leftLabel),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 22),
                child: LayoutBuilder(
                  builder: (context, box) => AnimatedBuilder(
                    animation: _flow,
                    builder: (_, _) => CustomPaint(
                      size: Size(box.maxWidth, 24),
                      painter: _TrackPainter(
                        mode: widget.mode,
                        t: _flow.value,
                        track: c.lineStrong,
                        tile: c.surface3,
                        edge: widget.mode == FlowMode.flowing
                            ? c.accent
                            : c.lineStrong,
                        warning: c.warning,
                        onWarning: c.onWarning,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _Phone(platform: rightPlatform, label: rightLabel),
          ],
        ),
      ),
    );
  }
}

class _Phone extends StatelessWidget {
  const _Phone({required this.platform, required this.label});

  final DevicePlatform? platform;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return SizedBox(
      width: 64,
      child: Column(
        children: [
          PhoneGlyph(
            platform: platform,
            size: 66,
            color: c.text,
            strokeWidth: 2.5,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: TextScaler.noScaling,
            style: CdType.overline.copyWith(letterSpacing: 0, color: c.text2),
          ),
        ],
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.mode,
    required this.t,
    required this.track,
    required this.tile,
    required this.edge,
    required this.warning,
    required this.onWarning,
  });

  final FlowMode mode;
  final double t;
  final Color track;
  final Color tile;
  final Color edge;
  final Color warning;
  final Color onWarning;

  static const _tile = 20.0;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final w = size.width;
    final line = Paint()
      ..color = track
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (mode == FlowMode.broken) {
      canvas.drawLine(Offset(4, y), Offset(w * 0.4, y), line);
      canvas.drawLine(Offset(w * 0.6, y), Offset(w - 4, y), line);
      final mid = Offset(w / 2, y);
      canvas.drawCircle(mid, 12, Paint()..color = warning);
      final mark = Paint()
        ..color = onWarning
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(mid.translate(0, -5), mid.translate(0, 1), mark);
      canvas.drawCircle(mid.translate(0, 5), 1.4, Paint()..color = onWarning);
    } else {
      canvas.drawLine(Offset(4, y), Offset(w - 4, y), line);
    }

    final travel = w - _tile - 8;
    final xs = switch (mode) {
      FlowMode.flowing => [for (var i = 0; i < 3; i++) ((t + i / 3) % 1)],
      FlowMode.frozen || FlowMode.broken => [0.15, 0.32],
      FlowMode.waiting => [0.0, 0.04, 0.08],
    };
    for (final (i, f) in xs.indexed) {
      final x = 4 + travel * f;
      final lift = mode == FlowMode.waiting ? -4.0 * i : 0.0;
      // Fade in at the start and out at the end of the trip.
      final fade = mode == FlowMode.flowing
          ? (f < 0.12 ? f / 0.12 : (f > 0.88 ? (1 - f) / 0.12 : 1.0))
          : 1.0;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y - _tile / 2 + lift, _tile, _tile),
        const Radius.circular(6),
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
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.t != t || old.mode != mode || old.edge != edge;
}
