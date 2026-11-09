import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
import '../../core/security/device_identity.dart';
import '../hotspot/hotspot_screens.dart';
import '../hotspot/numbered_steps.dart';

/// What [FindHelpScreen] asks the Nearby screen to do.
enum FindHelpResult { scanQr }

/// "Can't find the other phone?": the basics, then the QR code, then
/// hotspot mode, in the order of the connection flow (ARCHITECTURE.md,
/// "Connection flow"). Pops with [FindHelpResult.scanQr] to scan.
class FindHelpScreen extends ConsumerWidget {
  const FindHelpScreen({super.key, this.platform});

  /// This phone; defaults to the real platform. Set in tests.
  final DevicePlatform? platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = platform ?? DevicePlatform.current;
    final c = context.cd;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 10),
      child: Semantics(
        header: true,
        child: Text(text, style: CdType.h3.copyWith(color: c.text)),
      ),
    );
    Widget body(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: CdType.bodyM.copyWith(color: c.text2)),
    );
    return Scaffold(
      appBar: AppBar(title: const Text("Can't find the other phone?")),
      // Short page: built in full, so every step and button is reachable.
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          CdSpace.gutter,
          0,
          CdSpace.gutter,
          CdSpace.l,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading('1. Check both phones'),
            NumberedSteps(
              steps: [
                'CrossDrop is open on both phones, on its home screen or any '
                    'other screen.',
                'The other phone shows "Ready to receive" with Receiving on.',
                'Both phones are on the same Wi-Fi network.',
                if (me == DevicePlatform.ios)
                  'Local Network is allowed for CrossDrop on this iPhone '
                      '(Settings > Privacy & Security > Local Network). On an '
                      'iPhone receiving files, too.',
                'No VPN is on. A VPN can hide phones on the same Wi-Fi.',
              ],
            ),
            if (me == DevicePlatform.ios)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () =>
                      ref.read(localNetworkProvider).openSettings(),
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Open Settings'),
                ),
              ),
            heading('2. Use the QR code'),
            body(
              'Some routers hide phones from each other. The QR code connects '
              'directly.',
            ),
            const NumberedSteps(
              steps: [
                'On the other phone, tap "Show my QR code" on the CrossDrop '
                    'home screen.',
                'On this phone, tap Scan QR code and point the camera at it.',
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: CdButtonStyles.wide,
              onPressed: () => Navigator.of(context).pop(FindHelpResult.scanQr),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan QR code'),
            ),
            heading('3. Use hotspot mode'),
            body(
              'If the QR code does not connect either, the Wi-Fi blocks '
              'phone-to-phone traffic. That is common on guest, hotel, cafe '
              'and office networks. Or there is no Wi-Fi at all. Then one '
              'phone makes its own network.',
            ),
            OutlinedButton.icon(
              style: CdButtonStyles.wide,
              onPressed: () => pushScreen<void>(
                context,
                Routes.hotspot,
                HotspotModeScreen(platform: me),
              ),
              icon: const Icon(Icons.wifi_tethering_rounded),
              label: const Text('Hotspot mode'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
