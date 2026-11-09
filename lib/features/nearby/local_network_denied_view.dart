import 'package:flutter/material.dart';

import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
import '../hotspot/numbered_steps.dart';

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
    final c = context.cd;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CdSpace.gutter,
        24,
        CdSpace.gutter,
        24,
      ),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: c.dangerSoft,
              borderRadius: BorderRadius.circular(CdRadius.card),
              border: Border.all(color: c.dangerLine),
            ),
            child: Icon(Icons.wifi_off_rounded, size: 32, color: c.danger),
          ),
        ),
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text(
            'CrossDrop needs Local Network access',
            style: CdType.h2.copyWith(color: c.text),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'CrossDrop sends files straight to your other phone over this '
          'Wi-Fi, without the internet. iPhone only allows that when Local '
          'Network access is on. Without it, CrossDrop cannot find or '
          'connect to other phones, not even with a QR code.',
          style: CdType.bodyM.copyWith(color: c.text2),
        ),
        const SizedBox(height: 20),
        const NumberedSteps(
          steps: [
            'Tap Open Settings.',
            'Turn on Local Network.',
            'Come back here. CrossDrop looks again.',
          ],
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: CdButtonStyles.wide,
          onPressed: onOpenSettings,
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Open Settings'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          style: CdButtonStyles.wide,
          onPressed: onRetry,
          child: const Text('Try again'),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: onScanQr,
          child: const Text('Scan a QR code anyway'),
        ),
      ],
    );
  }
}
