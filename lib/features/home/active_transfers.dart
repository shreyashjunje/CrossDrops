import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
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
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'IN PROGRESS',
              style: CdType.overline.copyWith(color: context.cd.text2),
            ),
          ),
          const SizedBox(height: 8),
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
    final c = context.cd;
    final percent = fraction == null ? null : (fraction! * 100).floor();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: c.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CdRadius.button),
          side: BorderSide(color: c.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: CdType.titleS.copyWith(
                          fontSize: 15,
                          color: c.text,
                        ),
                      ),
                    ),
                    if (percent != null)
                      ExcludeSemantics(
                        child: Text(
                          '$percent%',
                          style: CdType.titleS.copyWith(
                            fontSize: 15,
                            color: c.text,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                fraction == null
                    ? LinearProgressIndicator(semanticsLabel: title)
                    : CdProgressBar(value: fraction!, semanticLabel: title),
                const SizedBox(height: 8),
                Text(
                  'Tap to see it',
                  style: CdType.small.copyWith(color: c.text2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
