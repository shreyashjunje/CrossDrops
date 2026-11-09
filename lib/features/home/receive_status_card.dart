import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/tokens.dart';
import '../receive/receive_controller.dart';
import '../receive/receive_host.dart';

/// "Ready to receive" with this phone's name and the Receiving switch
/// (D-069). The dot pulses while other phones can find this one.
class ReceiveStatusCard extends ConsumerWidget {
  const ReceiveStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cd;
    final state = ref.watch(receiveStateProvider);
    final name =
        state.deviceName ?? ref.watch(identityProvider).value?.deviceName;
    final status = statusOf(state, name);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: BorderRadius.circular(CdRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusDot(
                color: switch (status.tone) {
                  ReceiveTone.ready => c.accent,
                  ReceiveTone.waiting => c.text3,
                  ReceiveTone.warning => c.warningInk,
                  ReceiveTone.error => c.danger,
                },
                pulsing: status.tone == ReceiveTone.ready,
              ),
              const SizedBox(width: 12),
              Expanded(
                // Announced by screen readers when it changes.
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    status.title,
                    style: CdType.titleM.copyWith(fontSize: 17, color: c.text),
                  ),
                ),
              ),
              // Its own control, so the card's text stays a separate node.
              Semantics(
                container: true,
                label: 'Receiving',
                child: Switch(
                  value: !state.receivingOff,
                  onChanged: (on) => ref
                      .read(receiveControllerProvider.notifier)
                      .setReceiving(on),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: status.lead),
                  if (status.showName && name != null)
                    TextSpan(
                      text: ' $name',
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              style: CdType.bodyM.copyWith(color: c.text2),
            ),
          ),
          if (status.detail != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                status.detail!,
                style: CdType.small.copyWith(
                  color: status.tone == ReceiveTone.error ? c.danger : c.text3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// What the card says for [s]. Public for tests.
  static ReceiveStatus statusOf(ReceiveState s, String? name) {
    if (s.error != null) {
      return ReceiveStatus._(
        ReceiveTone.error,
        'Cannot receive',
        s.error!,
        false,
        null,
      );
    }
    if (s.receivingOff) {
      return const ReceiveStatus._(
        ReceiveTone.waiting,
        'Receiving is off',
        'Other phones can’t see or send to',
        true,
        'Trusted devices can still finish a transfer that is running.',
      );
    }
    if (s.port == null) {
      return const ReceiveStatus._(
        ReceiveTone.waiting,
        'Starting…',
        'Getting ready to receive as',
        true,
        null,
      );
    }
    if (s.qrPayload == null) {
      return const ReceiveStatus._(
        ReceiveTone.warning,
        'Not on Wi-Fi',
        'Join the same Wi-Fi as the other phone, or use a hotspot.',
        false,
        null,
      );
    }
    return ReceiveStatus._(
      ReceiveTone.ready,
      'Ready to receive',
      'Phones on this Wi-Fi see you as',
      true,
      s.advertising
          ? null
          : (s.advertiseError ??
                'Becoming visible to nearby phones… The QR code works '
                    'already.'),
    );
  }
}

enum ReceiveTone { ready, waiting, warning, error }

class ReceiveStatus {
  const ReceiveStatus._(
    this.tone,
    this.title,
    this.lead,
    this.showName,
    this.detail,
  );

  final ReceiveTone tone;
  final String title;

  /// Sentence before the device name, or the whole sentence.
  final String lead;
  final bool showName;
  final String? detail;
}

/// A 12 px dot; a ring pulses out of it every 2.4 s while [pulsing],
/// unless the system asks for reduced motion.
class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.color, required this.pulsing});

  final Color color;
  final bool pulsing;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: CdMotion.radarPulse,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_StatusDot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.pulsing && !reduce) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
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

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: 12,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, _) => Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (_pulse.isAnimating)
              Transform.scale(
                scale: 1 + 1.6 * Curves.easeOut.transform(_pulse.value),
                child: Opacity(
                  opacity: 0.55 * (1 - _pulse.value),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color,
                    ),
                    child: const SizedBox.square(dimension: 12),
                  ),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
              ),
              child: const SizedBox.square(dimension: 12),
            ),
          ],
        ),
      ),
    ),
  );
}
