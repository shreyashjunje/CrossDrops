import 'package:flutter/material.dart';

/// Shown on iOS when Local Network access is off for CrossDrop.
class LocalNetworkDeniedView extends StatelessWidget {
  const LocalNetworkDeniedView({
    super.key,
    required this.onOpenSettings,
    required this.onRetry,
    required this.onScanQr,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;
  final VoidCallback onScanQr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.wifi_off, size: 64, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(
          'CrossDrop needs Local Network access',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        const Text(
          'CrossDrop sends files straight to your other phone over this '
          'Wi-Fi, without the internet. iPhone only allows that when Local '
          'Network access is on. Without it, CrossDrop cannot find or '
          'connect to other phones, not even with a QR code.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Open Settings, then turn on Local Network. Come back here '
          'afterwards.',
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onOpenSettings,
          icon: const Icon(Icons.settings),
          label: const Text('Open Settings'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onScanQr,
          child: const Text('Scan a QR code anyway'),
        ),
      ],
    );
  }
}
