import 'package:flutter/material.dart';

import '../../core/media/prepare.dart';
import 'widgets.dart';

/// Items the preparation left out, and why (ARCHITECTURE.md, "iCloud-only
/// originals" and "Picked item gone before sending").
class SkippedNotice extends StatelessWidget {
  const SkippedNotice(this.skipped, {super.key});

  final List<SkippedItem> skipped;

  static String why(SkipReason r) => switch (r) {
    SkipReason.icloud =>
      'only in iCloud and could not be downloaded. Check the internet '
          'connection, or open it in Photos first',
    SkipReason.notFound =>
      'no longer in your library, or not shared with CrossDrop',
    SkipReason.noSpace => 'not enough free space on this phone to prepare it',
    SkipReason.unreadable => 'could not be read',
  };

  @override
  Widget build(BuildContext context) {
    final n = skipped.length;
    final lines = [
      n == 1 ? '1 item is not sent:' : '$n items are not sent:',
      for (final s in skipped.take(5)) '• ${s.label}: ${why(s.reason)}.',
      if (n > 5) '…and ${n - 5} more.',
    ];
    return WarningBox(icon: Icons.warning_amber, text: lines.join('\n'));
  }
}
