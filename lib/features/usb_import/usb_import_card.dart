import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens.dart';
import '../../platform/usb_camera.dart';
import '../cable/cable_controllers.dart';
import '../receive/receive_host.dart';
import 'usb_import_controller.dart';

/// Home screen entry for the cable (Android). While an iPhone is plugged
/// in it says whether the iPhone can send over the cable (D-073), with the
/// camera import (D-067) as the second choice; a quiet row otherwise.
class UsbImportCard extends ConsumerWidget {
  const UsbImportCard({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(usbImportAvailableProvider)) return const SizedBox.shrink();
    final devices = ref.watch(usbDevicesProvider).value ?? const [];
    final c = context.cd;
    final cable = ref.watch(cableReceiveProvider);
    final receivingOff = ref.watch(
      receiveStateProvider.select((s) => s.receivingOff),
    );
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
                        _cableText(cable, receivingOff: receivingOff),
                        style: CdType.small.copyWith(color: c.text2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onOpen,
              child: const Text('Import from camera roll'),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the cable can do right now (D-073).
String _cableText(UsbCableState? cable, {required bool receivingOff}) {
  if (receivingOff) return 'Turn on Receiving to get files over this cable.';
  if (cable?.connected ?? false) {
    return 'Ready. On the iPhone, open CrossDrop, tap Send and choose this '
        'phone: "Connected by cable". No Wi-Fi needed.';
  }
  return switch (cable?.code) {
    'permission_denied' =>
      'Allow CrossDrop to use the iPhone (USB access) to receive by cable. '
          'Unplug it and plug it in again to be asked again.',
    'no_usbmux' || 'handshake' || 'open_failed' =>
      'The cable link did not start. Unlock the iPhone, unplug it and plug '
          'it in again.',
    _ =>
      'Open CrossDrop on the iPhone to send photos, videos and files over '
          'this cable. No Wi-Fi needed.',
  };
}
