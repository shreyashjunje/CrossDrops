import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
            Text('Ready to receive', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final ip in state.addresses)
              SelectableText(ip, style: theme.textTheme.headlineSmall),
            if (state.addresses.isEmpty)
              const Text('No network address. Join a Wi-Fi or hotspot.'),
            const SizedBox(height: 4),
            SelectableText(
              'Port ${state.port}',
              style: theme.textTheme.headlineSmall,
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
