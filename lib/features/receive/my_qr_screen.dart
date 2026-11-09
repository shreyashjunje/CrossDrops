import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/keep_alive.dart';
import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
import '../../core/security/device_identity.dart';
import '../hotspot/hotspot_screens.dart';
import 'receive_controller.dart';
import 'receive_host.dart';

/// This phone's QR code, for a sender whose nearby list does not show it
/// (ARCHITECTURE.md, "QR code payload"). The screen stays on while it is
/// open, so the code stays scannable. Dark on white in both themes
/// (D-069). The payload is never logged (hard rule 7).
class MyQrScreen extends ConsumerStatefulWidget {
  const MyQrScreen({super.key});

  @override
  ConsumerState<MyQrScreen> createState() => _MyQrScreenState();
}

class _MyQrScreenState extends ConsumerState<MyQrScreen> {
  final Object _screenKey = Object();

  // Read once: ref may not be used in dispose.
  late final KeepAliveCoordinator _keepAlive = ref.read(keepAliveProvider);

  @override
  void initState() {
    super.initState();
    _keepAlive.holdScreen(_screenKey);
  }

  @override
  void dispose() {
    _keepAlive.releaseScreen(_screenKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final state = ref.watch(receiveStateProvider);
    final payload = state.qrPayload;
    final name = state.deviceName ?? 'this phone';
    final Widget body;
    if (state.receivingOff) {
      body = _Blocked(
        icon: Icons.qr_code_2_rounded,
        title: 'Receiving is off',
        text:
            'Turn it on to show a code. Other phones cannot connect while '
            'it is off.',
        button: 'Turn on Receiving',
        onPressed: () =>
            ref.read(receiveControllerProvider.notifier).setReceiving(true),
      );
    } else if (state.port == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (payload == null) {
      body = _Blocked(
        icon: Icons.wifi_off_rounded,
        title: 'Not on Wi-Fi',
        text:
            'This phone is not on Wi-Fi or a hotspot. Join the same network '
            'as the other phone, then come back. No Wi-Fi around? Use '
            'hotspot mode.',
        button: 'Use hotspot mode',
        onPressed: () => pushScreen<void>(
          context,
          Routes.hotspot,
          const HotspotModeScreen(),
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(
          CdSpace.gutter,
          8,
          CdSpace.gutter,
          CdSpace.l,
        ),
        children: [
          Row(
            children: [
              DeviceAvatar(
                name: name,
                platform: DevicePlatform.current,
                size: 40,
                showBadge: false,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.deviceName ?? '',
                      style: CdType.titleM.copyWith(color: c.text),
                    ),
                    Text(
                      'Ready to receive',
                      style: CdType.small.copyWith(color: c.text2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: QrCard(
              data: payload,
              size: 240,
              semanticLabel: 'QR code to connect to $name',
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'On the other phone, open CrossDrop, tap Send, then Scan QR code.',
            style: CdType.bodyL.copyWith(color: c.text),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'The screen stays on while this is open.',
            style: CdType.small.copyWith(color: c.text3),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Theme(
            // No divider lines around the expansion.
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: const Text('No camera? Type the address'),
              childrenPadding: const EdgeInsets.only(bottom: 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: c.surface1,
                    borderRadius: BorderRadius.circular(CdRadius.card),
                    border: Border.all(color: c.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Address',
                        style: CdType.small.copyWith(color: c.text2),
                      ),
                      for (final a in state.addresses)
                        SelectableText(
                          '${a.ip}  (${a.interfaceName})',
                          style: CdType.h2.copyWith(
                            color: c.text,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        'Port',
                        style: CdType.small.copyWith(color: c.text2),
                      ),
                      SelectableText(
                        '${state.port}',
                        style: CdType.h2.copyWith(
                          color: c.text,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'On the other phone: Send, then Type the address instead. '
                  'The address changes each time CrossDrop restarts.',
                  style: CdType.small.copyWith(color: c.text2),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('My QR code')),
      body: body,
    );
  }
}

/// No code to show: why, and the one fix.
class _Blocked extends StatelessWidget {
  const _Blocked({
    required this.icon,
    required this.title,
    required this.text,
    required this.button,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String text;
  final String button;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CdSpace.gutter,
        32,
        CdSpace.gutter,
        24,
      ),
      children: [
        Container(
          height: 260,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CdRadius.sheet),
            border: Border.all(color: c.lineStrong, width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: c.text3),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: CdType.h3.copyWith(color: c.text),
              ),
              const SizedBox(height: 8),
              Text(
                text,
                textAlign: TextAlign.center,
                style: CdType.bodyM.copyWith(color: c.text2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          style: CdButtonStyles.wide,
          onPressed: onPressed,
          child: Text(button),
        ),
      ],
    );
  }
}
