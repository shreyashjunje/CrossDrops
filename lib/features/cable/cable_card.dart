import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens.dart';
import '../../platform/usb_cable.dart';
import '../receive/receive_host.dart';
import 'cable_controllers.dart';

/// Home screen card while an iPhone is plugged in (Android, D-073): whether
/// the phones can send to each other over the cable. Nothing otherwise.
class CableCard extends ConsumerWidget {
  const CableCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(cableReceiveAvailableProvider)) {
      return const SizedBox.shrink();
    }
    final devices = ref.watch(usbDevicesProvider).value ?? const [];
    if (devices.isEmpty) return const SizedBox.shrink();
    final c = context.cd;
    final cable = ref.watch(cableReceiveProvider);
    final receivingOff = ref.watch(
      receiveStateProvider.select((s) => s.receivingOff),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface1,
          borderRadius: BorderRadius.circular(CdRadius.card),
          border: Border.all(color: c.accent, width: 1.5),
        ),
        child: Row(
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
                    style: CdType.titleS.copyWith(fontSize: 15, color: c.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cableCardText(cable, receivingOff: receivingOff),
                    style: CdType.small.copyWith(color: c.text2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the cable can do right now.
String cableCardText(UsbCableState? cable, {required bool receivingOff}) {
  if (receivingOff) return 'Turn on Receiving to get files over this cable.';
  if (cable?.connected ?? false) {
    return 'Ready. On the iPhone, open CrossDrop, tap Send and choose this '
        'phone: "Connected by cable". No Wi-Fi needed.';
  }
  return switch (cable?.code) {
    UsbCableErrors.permissionDenied =>
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
