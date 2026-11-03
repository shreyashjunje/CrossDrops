import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../receive/receive_host.dart';
import '../send/send_controller.dart';
import '../transfer/transfer_view.dart';

/// Transfers in progress, newest first; tap one to see its progress.
class ActiveTransfers extends ConsumerWidget {
  const ActiveTransfers({super.key, this.onOpen});

  /// Opens a transfer: null = the send, else a received session id.
  final void Function(String? sessionId)? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final send = ref.watch(sendControllerProvider);
    final sessions = ref.watch(receiveStateProvider.select((s) => s.sessions));
    final sending = send.isRunning
        ? TransferView.fromSend(
            send.snapshot,
            peerName: send.receiverName ?? '',
          )
        : null;
    final receiving = [
      for (final s in sessions.values.toList().reversed)
        if (s.isActive) (s.sessionId, TransferView.fromIncoming(s)),
    ];
    if (sending == null && receiving.isEmpty && !send.isPreparing) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('In progress', style: Theme.of(context).textTheme.titleMedium),
          if (send.isPreparing && sending == null)
            _Tile(
              title: 'Preparing files to send',
              fraction: send.preparing?.fraction,
              onTap: onOpen == null ? null : () => onOpen!(null),
            ),
          if (sending != null)
            _Tile(
              title: 'Sending to ${sending.peerName}',
              fraction: sending.fraction,
              onTap: onOpen == null ? null : () => onOpen!(null),
            ),
          for (final (id, v) in receiving)
            _Tile(
              title: 'Receiving from ${v.peerName}',
              fraction: v.fraction,
              onTap: onOpen == null ? null : () => onOpen!(id),
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.title, required this.fraction, this.onTap});

  final String title;
  final double? fraction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final percent = fraction == null ? null : (fraction! * 100).floor();
    return Card(
      child: ListTile(
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(
            value: fraction,
            semanticsLabel: title,
            semanticsValue: percent == null ? null : '$percent%',
          ),
        ),
        trailing: percent == null ? null : Text('$percent%'),
        onTap: onTap,
      ),
    );
  }
}
