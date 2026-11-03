import 'dart:async';

import 'package:flutter/material.dart';

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
/// "Pairing code" and "Trust").
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
    final offer = widget.offer;
    final trusted = offer.trust.isTrusted;
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _answer(false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Incoming files'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _Sender(offer: offer),
                    if (offer.trust.lookalike case final l?) ...[
                      const SizedBox(height: 12),
                      WarningBox(
                        icon: Icons.gpp_maybe_outlined,
                        text:
                            'This is not the "${l.name}" you trusted. Its '
                            'security key is different. It may have been '
                            'reinstalled, or someone may be pretending to '
                            'be it.',
                      ),
                    ] else if (!trusted) ...[
                      const SizedBox(height: 12),
                      const WarningBox(
                        icon: Icons.info_outline,
                        text:
                            'First time from this device. Only accept files '
                            'from people you know.',
                      ),
                    ],
                    const SizedBox(height: 16),
                    _Files(offer: offer),
                    if (!trusted) ...[
                      const SizedBox(height: 16),
                      _PairingCode(code: offer.pairingCode),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _trust,
                        onChanged: (v) => setState(() => _trust = v ?? false),
                        title: const Text('Trust this device'),
                        subtitle: const Text(
                          'Skip the code check next time. You can remove '
                          'it in Settings.',
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Semantics(
                      liveRegion: _secondsLeft <= 10,
                      child: Text(
                        _secondsLeft > 0
                            ? 'This request expires in $_secondsLeft s.'
                            : 'This request has expired.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => _answer(false),
                      child: const Text('Decline'),
                    ),
                    FilledButton(
                      onPressed: () => _answer(true),
                      child: Text(trusted ? 'Accept' : 'Codes match, accept'),
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

class _Sender extends StatelessWidget {
  const _Sender({required this.offer});

  final IncomingOffer offer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platform = DevicePlatform.tryParse(offer.sender.platform);
    final trusted = offer.trust.isTrusted;
    return Row(
      children: [
        PlatformIcon(platform: platform, size: 48),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(offer.sender.name, style: theme.textTheme.headlineSmall),
              Text(
                '${platformLabel(platform)} · '
                '${trusted ? 'Trusted' : 'Not trusted'}',
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        if (trusted)
          Icon(
            Icons.verified_user,
            color: theme.colorScheme.primary,
            semanticLabel: 'Trusted device',
          ),
      ],
    );
  }
}

class _Files extends StatelessWidget {
  const _Files({required this.offer});

  final IncomingOffer offer;

  @override
  Widget build(BuildContext context) {
    final files = offer.files;
    final count = files.length;
    final theme = Theme.of(context);
    final more = count - IncomingRequestScreen.maxListed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'wants to send you $count ${count == 1 ? 'file' : 'files'} · '
          '${formatSize(offer.totalBytes)}',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final f in files.take(IncomingRequestScreen.maxListed))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(fileKindIcon(f.kind), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(formatSize(f.size)),
              ],
            ),
          ),
        if (more > 0) Text('and $more more'),
      ],
    );
  }
}

class _PairingCode extends StatelessWidget {
  const _PairingCode({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) => PairingCodeBox(
    code: code,
    caption: 'Check that the other phone shows the same code:',
    footer: 'If the codes are different, tap Decline.',
  );
}
