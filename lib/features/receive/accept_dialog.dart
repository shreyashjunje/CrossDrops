import 'package:flutter/material.dart';

import '../../core/security/peer_auth.dart';
import '../../core/server/receive_server.dart';
import '../transfer/transfer_format.dart';

/// What the user chose in the Accept prompt.
class AcceptDecision {
  const AcceptDecision({required this.accept, this.trust = false});

  final bool accept;

  /// Add the sender to the trusted devices.
  final bool trust;
}

/// The Accept prompt. Simple for now; the full design comes in Phase 6.
///
/// For an untrusted sender it shows the 6-digit pairing code, which the
/// other phone shows too, and offers "Trust this device". A sender that
/// uses a trusted device's name with another key gets a warning.
///
/// Pops with an [AcceptDecision].
class AcceptOfferDialog extends StatefulWidget {
  const AcceptOfferDialog({super.key, required this.offer});

  final IncomingOffer offer;

  @override
  State<AcceptOfferDialog> createState() => _AcceptOfferDialogState();
}

class _AcceptOfferDialogState extends State<AcceptOfferDialog> {
  static const int _maxListed = 5;
  bool _trust = false;

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final files = offer.files;
    final count = files.length;
    final theme = Theme.of(context);
    final trusted = offer.trust.isTrusted;
    final lookalike = offer.trust.lookalike;
    return AlertDialog(
      title: Text('${offer.sender.name} wants to send you'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lookalike != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                color: theme.colorScheme.errorContainer,
                child: Text(
                  'Warning: this is not the "${lookalike.name}" you trusted. '
                  'Its security key is different. It may have been '
                  'reinstalled, or someone may be pretending to be it.',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              '$count ${count == 1 ? 'file' : 'files'} · '
              '${formatMegabytes(offer.totalBytes)}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final f in files.take(_maxListed))
              Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (count > _maxListed) Text('and ${count - _maxListed} more'),
            if (!trusted) ...[
              const SizedBox(height: 16),
              const Text('Check that the other phone shows this code:'),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  formatPairingCode(offer.pairingCode),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'If the codes differ, tap Decline.',
                style: theme.textTheme.bodySmall,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _trust,
                onChanged: (v) => setState(() => _trust = v ?? false),
                title: const Text('Trust this device'),
                subtitle: const Text('Skip the code check next time'),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Only accept files from people you know. '
              'The request expires in 60 seconds.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const AcceptDecision(accept: false)),
          child: const Text('Decline'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context)
                  .pop(AcceptDecision(accept: true, trust: !trusted && _trust)),
          child: Text(trusted ? 'Accept' : 'Codes match, accept'),
        ),
      ],
    );
  }
}
