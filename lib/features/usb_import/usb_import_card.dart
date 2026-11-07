import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'usb_import_controller.dart';

/// Home screen entry for the cable import (Android, D-067). Stands out
/// while an iPhone is plugged in; a quiet row otherwise.
class UsbImportCard extends ConsumerWidget {
  const UsbImportCard({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(usbImportAvailableProvider)) return const SizedBox.shrink();
    final devices = ref.watch(usbDevicesProvider).value ?? const [];
    final theme = Theme.of(context);
    if (devices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: ListTile(
          leading: const Icon(Icons.cable),
          title: const Text('Import from iPhone with a cable'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onOpen,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.cable,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${devices.first.name} connected by cable',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Choose photos and videos and copy them to this phone.',
                style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onOpen,
                child: const Text('Import photos'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
