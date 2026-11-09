import 'package:flutter/material.dart';

import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
import '../../core/storage/transfer_repository.dart';
import '../transfer/transfer_format.dart';
import '../transfer/transfer_view.dart';
import '../transfer/widgets.dart';

/// A status word and tone for a stored transfer: "Sent", "Unfinished"...
(String, BadgeTone) transferTag(TransferView v, {required bool sending}) =>
    switch (v.stage) {
      TransferStage.done when v.failedCount > 0 => (
        'Partly',
        BadgeTone.warning,
      ),
      TransferStage.done => (sending ? 'Sent' : 'Received', BadgeTone.trusted),
      TransferStage.failed => ('Failed', BadgeTone.danger),
      TransferStage.cancelled => ('Cancelled', BadgeTone.neutral),
      TransferStage.rejected => ('Declined', BadgeTone.neutral),
      TransferStage.paused => ('Unfinished', BadgeTone.warning),
      _ => ('In progress', BadgeTone.neutral),
    };

/// "12 photos to Alex's Pixel 8".
String transferTitle(StoredSession s) {
  final sending = s.direction == TransferDirection.send;
  final what = countKinds(s.files.map((f) => f.kind));
  final who = '${sending ? 'to' : 'from'} ${s.peer.name}';
  return what.isEmpty
      ? (sending ? 'To ${s.peer.name}' : 'From ${s.peer.name}')
      : '$what $who';
}

/// One transfer in a list (D-069): a direction tile, what and who, size
/// and time, and a status tag. Ended-without-files transfers are dimmed.
class TransferRow extends StatelessWidget {
  const TransferRow({super.key, required this.session, this.onTap});

  final StoredSession session;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final s = session;
    final sending = s.direction == TransferDirection.send;
    final v = TransferView.fromStored(s);
    final (tag, tone) = transferTag(v, sending: sending);
    final quiet =
        v.stage == TransferStage.cancelled || v.stage == TransferStage.rejected;
    final meta = [
      formatSize(s.totalBytes),
      platformLabel(v.peerPlatform),
      formatTime(s.createdAt.toLocal()),
    ].join(' · ');
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Opacity(
                  opacity: quiet ? 0.5 : 1,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c.surface3,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      sending
                          ? Icons.north_east_rounded
                          : Icons.south_west_rounded,
                      color: c.text,
                      semanticLabel: sending ? 'Sent' : 'Received',
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transferTitle(s),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: CdType.titleS.copyWith(
                          fontSize: 15,
                          color: c.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(meta, style: CdType.small.copyWith(color: c.text2)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge(label: tag, tone: tone),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
