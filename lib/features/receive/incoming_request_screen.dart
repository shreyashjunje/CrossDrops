import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
import '../../core/security/device_identity.dart';
import '../../core/server/receive_server.dart';
import '../transfer/transfer_format.dart';
import '../transfer/widgets.dart';

/// What the user chose on the Incoming request screen.
class AcceptDecision {
  const AcceptDecision({required this.accept, this.trust = false});

  final bool accept;

  /// Add the sender to the trusted devices.
  final bool trust;
}

/// Someone wants to send files: who (name, platform, trusted or not), how
/// many files, how big, the first names, and for an untrusted sender the
/// 6-digit code to compare and "Trust this device" (ARCHITECTURE.md,
/// "Pairing code" and "Trust"). Layout per D-069: the sender as a person,
/// the code on the same screen, Decline and Accept at the bottom.
///
/// Pops with an [AcceptDecision]. Back declines.
class IncomingRequestScreen extends StatefulWidget {
  const IncomingRequestScreen({
    super.key,
    required this.offer,
    this.timeout = const Duration(seconds: 60),
  });

  final IncomingOffer offer;

  /// The server's accept timeout; the countdown starts when the screen
  /// opens, which is when the offer arrives.
  final Duration timeout;

  /// Names listed before "and N more".
  static const maxListed = 5;

  @override
  State<IncomingRequestScreen> createState() => _IncomingRequestScreenState();
}

class _IncomingRequestScreenState extends State<IncomingRequestScreen> {
  bool _trust = false;
  late int _secondsLeft = widget.timeout.inSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft > 0) setState(() => _secondsLeft--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _answer(bool accept) => Navigator.of(context).pop(
    AcceptDecision(
      accept: accept,
      trust: accept && !widget.offer.trust.isTrusted && _trust,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final offer = widget.offer;
    final trusted = offer.trust.isTrusted;
    final total = widget.timeout.inSeconds;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _answer(false);
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                // Built in full: the code and the trust switch must exist
                // for screen readers even before they are scrolled to.
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    CdSpace.gutter,
                    12,
                    CdSpace.gutter,
                    CdSpace.l,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TopRow(
                        secondsLeft: _secondsLeft,
                        fraction: total == 0 ? 0 : _secondsLeft / total,
                      ),
                      const SizedBox(height: 16),
                      _Sender(offer: offer),
                      if (offer.trust.lookalike case final l?) ...[
                        const SizedBox(height: 16),
                        NoticeCard(
                          tone: NoticeTone.danger,
                          icon: Icons.gpp_maybe_outlined,
                          text:
                              'This is not the "${l.name}" you trusted. Its '
                              'security key is different. It may have been '
                              'reinstalled, or someone may be pretending to '
                              'be it.',
                        ),
                      ] else if (!trusted) ...[
                        const SizedBox(height: 16),
                        const NoticeCard(
                          icon: Icons.info_outline_rounded,
                          text:
                              'First time from this device. Only accept files '
                              'from people you know.',
                        ),
                      ],
                      const SizedBox(height: 16),
                      _Files(offer: offer),
                      if (!trusted) ...[
                        const SizedBox(height: 24),
                        Semantics(
                          header: true,
                          child: Text(
                            'Check the code',
                            style: CdType.titleM.copyWith(
                              fontSize: 17,
                              color: c.text,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${offer.sender.name} should show the same six '
                          'numbers. Different? Tap Decline.',
                          style: CdType.bodyM.copyWith(color: c.text2),
                        ),
                        const SizedBox(height: 14),
                        CodeDisplay(code: offer.pairingCode),
                        const SizedBox(height: 12),
                        Divider(color: c.line),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _trust,
                          onChanged: (v) => setState(() => _trust = v),
                          secondary: Icon(
                            Icons.verified_user_outlined,
                            color: c.text2,
                          ),
                          title: const Text('Trust this device'),
                          subtitle: const Text(
                            'No code check next time. You can remove it in '
                            'Settings.',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CdSpace.gutter,
                  8,
                  CdSpace.gutter,
                  16,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: CdButtonStyles.secondary(context)
                            .merge(CdButtonStyles.wide),
                        onPressed: () => _answer(false),
                        child: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        style: CdButtonStyles.wide,
                        onPressed: () => _answer(true),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(
                          trusted ? 'Accept' : 'Codes match, accept',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "INCOMING" and the answer countdown.
class _TopRow extends StatelessWidget {
  const _TopRow({required this.secondsLeft, required this.fraction});

  final int secondsLeft;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.south_west_rounded, size: 18, color: c.text2),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'INCOMING',
                style: CdType.overline.copyWith(color: c.text2),
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProgressRing(value: fraction, size: 18, stroke: 2.5, paused: true),
            const SizedBox(width: 8),
            Flexible(
              child: Semantics(
                liveRegion: secondsLeft <= 10,
                child: Text(
                  secondsLeft > 0
                      ? 'Answer within $secondsLeft s'
                      : 'This request has expired.',
                  style: CdType.small.copyWith(
                    color: secondsLeft > 0 ? c.text2 : c.danger,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Sender extends StatelessWidget {
  const _Sender({required this.offer});

  final IncomingOffer offer;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final platform = DevicePlatform.tryParse(offer.sender.platform);
    final trust = offer.trust;
    return Column(
      children: [
        DeviceAvatar(name: offer.sender.name, platform: platform, size: 88),
        const SizedBox(height: 14),
        Text(
          offer.sender.name,
          textAlign: TextAlign.center,
          style: CdType.h1.copyWith(color: c.text),
        ),
        const SizedBox(height: 2),
        Text(
          platformLabel(platform),
          textAlign: TextAlign.center,
          style: CdType.bodyM.copyWith(color: c.text2),
        ),
        const SizedBox(height: 10),
        if (trust.isTrusted)
          const StatusBadge.trusted()
        else if (trust.lookalike != null)
          const StatusBadge(
            label: 'Not the phone you trusted',
            tone: BadgeTone.danger,
            icon: Icons.gpp_maybe_outlined,
          )
        else
          const StatusBadge.firstTime(label: 'First time from this phone'),
      ],
    );
  }
}

class _Files extends StatelessWidget {
  const _Files({required this.offer});

  final IncomingOffer offer;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final files = offer.files;
    final more = files.length - IncomingRequestScreen.maxListed;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: BorderRadius.circular(CdRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${countKinds(files.map((f) => f.kind))} · '
            '${formatSize(offer.totalBytes)}',
            style: CdType.titleM.copyWith(fontSize: 17, color: c.text),
          ),
          const SizedBox(height: 10),
          for (final f in files.take(IncomingRequestScreen.maxListed))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c.surface3,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(fileKindIcon(f.kind), size: 18, color: c.text2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      f.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CdType.bodyM.copyWith(color: c.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatSize(f.size),
                    style: CdType.small.copyWith(color: c.text2),
                  ),
                ],
              ),
            ),
          if (more > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'and $more more',
                style: CdType.small.copyWith(color: c.text2),
              ),
            ),
        ],
      ),
    );
  }
}
