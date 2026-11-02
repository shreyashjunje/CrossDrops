import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../transfer/transfer_format.dart';
import 'receive_controller.dart';

class ReceiveScreen extends ConsumerWidget {
  const ReceiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(receiveControllerProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Receive')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (state.error != null)
            Text(state.error!, style: TextStyle(color: theme.colorScheme.error))
          else if (state.port == null)
            const Text('Starting…')
          else ...[
            Text(
              'Ready to receive as ${state.deviceName}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              state.advertising
                  ? 'Phones on this Wi-Fi see you in their nearby list.'
                  : (state.advertiseError ?? 'Starting nearby discovery…'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (state.qrPayload != null) ...[
              Center(
                child: Container(
                  // White background so the code scans in dark mode too.
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    data: state.qrPayload!,
                    size: 220,
                    semanticsLabel: 'CrossDrop connection QR code',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Not in the list? On the other phone tap Send, then Scan QR '
                'code.',
                textAlign: TextAlign.center,
              ),
            ] else
              Text(
                'No Wi-Fi or hotspot address. Join the same Wi-Fi as the '
                'other phone, or use a hotspot.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            const SizedBox(height: 16),
            Text(
              'Or type this on the other phone:',
              style: theme.textTheme.bodySmall,
            ),
            for (final a in state.addresses)
              SelectableText(
                '${a.ip}  (${a.interfaceName})',
                style: theme.textTheme.titleMedium,
              ),
            SelectableText(
              'Port ${state.port}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Keep this screen open. Files are saved to:\n${state.saveDir}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const Divider(height: 32),
          for (final f in state.files.values.toList().reversed)
            _IncomingTile(file: f),
        ],
      ),
    );
  }
}

class _IncomingTile extends StatelessWidget {
  const _IncomingTile({required this.file});

  final IncomingFile file;

  @override
  Widget build(BuildContext context) {
    final fraction = file.size == 0 ? 1.0 : file.receivedBytes / file.size;
    final String status;
    if (file.error != null) {
      status = 'Failed: ${file.error}';
    } else if (file.savedPath != null) {
      status = 'Saved, SHA-256 verified';
    } else {
      status =
          '${formatMegabytes(file.receivedBytes)} of '
          '${formatMegabytes(file.size)} · ${formatSpeed(file.bytesPerSecond)}';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: fraction),
          const SizedBox(height: 4),
          Text(status),
        ],
      ),
    );
  }
}
