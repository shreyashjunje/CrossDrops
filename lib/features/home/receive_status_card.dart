import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../receive/receive_controller.dart';
import '../receive/receive_host.dart';

/// "Ready to receive" with this phone's name, the Receiving switch and the
/// QR link.
class ReceiveStatusCard extends ConsumerWidget {
  const ReceiveStatusCard({super.key, required this.onShowQr});

  final VoidCallback onShowQr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(receiveStateProvider);
    final name =
        state.deviceName ?? ref.watch(identityProvider).value?.deviceName;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, title, detail, ok) = _status(state, name);
    return Card(
      color: ok ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Announced by screen readers when it changes.
            Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 40,
                    color: ok ? scheme.onPrimaryContainer : scheme.onSurface,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: ok ? scheme.onPrimaryContainer : null,
                          ),
                        ),
                        if (name != null)
                          Text(
                            'as $name',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: ok ? scheme.onPrimaryContainer : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              style: TextStyle(
                color: state.error != null
                    ? scheme.error
                    : (ok ? scheme.onPrimaryContainer : null),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Receiving',
                style: TextStyle(color: ok ? scheme.onPrimaryContainer : null),
              ),
              value: !state.receivingOff,
              onChanged: (on) =>
                  ref.read(receiveControllerProvider.notifier).setReceiving(on),
            ),
            if (!state.receivingOff)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: onShowQr,
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Show my QR code'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static (IconData, String, String, bool) _status(
    ReceiveState s,
    String? name,
  ) {
    if (s.error != null) {
      return (Icons.error_outline, 'Cannot receive', s.error!, false);
    }
    if (s.receivingOff) {
      return (
        Icons.do_not_disturb_on_outlined,
        'Receiving is off',
        'Other phones cannot see this phone. Trusted devices can still '
            'finish a transfer that is running.',
        false,
      );
    }
    if (s.port == null) {
      return (
        Icons.hourglass_empty,
        'Starting…',
        'Getting ready to receive.',
        false,
      );
    }
    if (s.qrPayload == null) {
      return (
        Icons.wifi_off,
        'Not on Wi-Fi',
        'Join the same Wi-Fi as the other phone, or use a hotspot.',
        false,
      );
    }
    return (
      Icons.wifi_tethering,
      'Ready to receive',
      s.advertising
          ? 'Phones on the same Wi-Fi with CrossDrop open can see you. Keep '
                'CrossDrop open.'
          : (s.advertiseError ??
                'Becoming visible to nearby phones… The QR code works '
                    'already.'),
      true,
    );
  }
}
