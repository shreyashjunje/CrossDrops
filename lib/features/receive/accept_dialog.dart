import 'package:flutter/material.dart';

import '../../core/server/receive_server.dart';
import '../transfer/transfer_format.dart';

/// The Accept prompt. Simple for now; the full design comes in Phase 6.
///
/// Pops with true (Accept) or false (Decline).
class AcceptOfferDialog extends StatelessWidget {
  const AcceptOfferDialog({super.key, required this.offer});

  final IncomingOffer offer;

  static const int _maxListed = 5;

  @override
  Widget build(BuildContext context) {
    final files = offer.files;
    final count = files.length;
    return AlertDialog(
      title: Text('${offer.sender.name} wants to send you'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count ${count == 1 ? 'file' : 'files'} · '
            '${formatMegabytes(offer.totalBytes)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final f in files.take(_maxListed))
            Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (count > _maxListed) Text('and ${count - _maxListed} more'),
          const SizedBox(height: 8),
          Text(
            'Only accept files from people you know. '
            'The request expires in 60 seconds.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Decline'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Accept'),
        ),
      ],
    );
  }
}
