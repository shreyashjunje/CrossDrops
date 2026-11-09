import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens.dart';
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
    final c = context.cd;
    if (devices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.cable_rounded, color: c.text2),
          title: const Text('Import from iPhone with a cable'),
          trailing: Icon(Icons.chevron_right_rounded, color: c.text3),
          onTap: onOpen,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface1,
          borderRadius: BorderRadius.circular(CdRadius.card),
          border: Border.all(color: c.accent, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(CdRadius.tile),
                  ),
                  child: Icon(Icons.cable_rounded, color: c.accentInk),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${devices.first.name} connected by cable',
                        style: CdType.titleS.copyWith(
                          fontSize: 15,
                          color: c.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Choose photos and videos and copy them to this '
                        'phone. No app needed on the iPhone.',
                        style: CdType.small.copyWith(color: c.text2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onOpen, child: const Text('Import photos')),
          ],
        ),
      ),
    );
  }
}
