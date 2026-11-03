import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/navigation.dart';
import '../../core/security/device_identity.dart';
import '../../platform/hotspot.dart';
import '../transfer/widgets.dart';
import 'numbered_steps.dart';

/// Starts a hotspot from the app (Android, Phase 7).
final hotspotServiceProvider = Provider<HotspotService>(
  (ref) => NoHotspot(isAndroid: Platform.isAndroid),
);

/// Offline mode: one phone makes a Wi-Fi network, the other joins it
/// (ARCHITECTURE.md, scenarios 4 and 5). The choices depend on which
/// phone this is.
class HotspotModeScreen extends StatelessWidget {
  const HotspotModeScreen({super.key, this.platform});

  /// This phone; defaults to the real platform. Set in tests.
  final DevicePlatform? platform;

  @override
  Widget build(BuildContext context) {
    final me = platform ?? DevicePlatform.current;
    final theme = Theme.of(context);
    void open(Widget screen) =>
        pushScreen<void>(context, Routes.hotspot, screen);
    return Scaffold(
      appBar: AppBar(title: const Text('Hotspot mode')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'No shared Wi-Fi, or a Wi-Fi that hides phones from each other? '
            'One phone makes its own Wi-Fi network and the other joins it. '
            'Files go straight between the phones and use no mobile data.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          if (me == DevicePlatform.android) ...[
            _Choice(
              icon: Icons.wifi_tethering,
              title: 'This phone makes the network',
              subtitle: 'Recommended. The iPhone joins it.',
              onTap: () => open(const AndroidHotspotScreen()),
            ),
            _Choice(
              icon: Icons.phone_iphone,
              title: "Join the iPhone's Personal Hotspot",
              subtitle: 'The iPhone owner turns it on in Settings.',
              onTap: () => open(const PersonalHotspotGuide()),
            ),
          ] else ...[
            _Choice(
              icon: Icons.phone_android,
              title: "Join the Android phone's network",
              subtitle: 'Recommended. Start it in CrossDrop on the Android.',
              onTap: () => open(const JoinAndroidHotspotScreen()),
            ),
            _Choice(
              icon: Icons.wifi_tethering,
              title: 'This iPhone makes the network',
              subtitle: 'Turn on Personal Hotspot; the Android joins it.',
              onTap: () => open(const PersonalHotspotGuide()),
            ),
          ],
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon, size: 32),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

/// Android: start a local-only hotspot and show one QR code with its name,
/// password and the connection (ARCHITECTURE.md, "QR code payload"). Until
/// Phase 7 it explains how to use the hotspot from Android settings.
class AndroidHotspotScreen extends ConsumerStatefulWidget {
  const AndroidHotspotScreen({super.key});

  @override
  ConsumerState<AndroidHotspotScreen> createState() =>
      _AndroidHotspotScreenState();
}

class _AndroidHotspotScreenState extends ConsumerState<AndroidHotspotScreen> {
  // Read once: ref may not be used in dispose.
  late final HotspotService _hotspot = ref.read(hotspotServiceProvider);
  late final Future<HotspotSupport> _support = _hotspot.support();
  HotspotInfo? _info;
  String? _error;
  bool _starting = false;

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final info = await _hotspot.start();
      if (mounted) setState(() => _info = info);
    } on HotspotException catch (e) {
      if (mounted) setState(() => _error = _message(e.code));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  static String _message(String code) => switch (code) {
    'permission' => 'CrossDrop needs the Nearby devices permission for this.',
    'tethering_on' =>
      'Turn off the phone\'s own hotspot (tethering) first, then try again.',
    'wifi_off' => 'Turn on Wi-Fi first, then try again.',
    _ => 'The hotspot could not start. Try again.',
  };

  @override
  void dispose() {
    if (_info != null) _hotspot.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Make a network')),
      body: FutureBuilder<HotspotSupport>(
        future: _support,
        builder: (context, snap) {
          final support = snap.data;
          if (support == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (support != HotspotSupport.available) {
            return const _ManualAndroidHotspot();
          }
          final info = _info;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (info == null) ...[
                const NumberedSteps(
                  steps: [
                    'Tap Start. This phone makes a Wi-Fi network just for '
                        'CrossDrop. It has no internet.',
                    'On the iPhone, open CrossDrop, tap Send, then Scan QR '
                        'code, and scan the code shown here.',
                    'The iPhone joins the network and connects.',
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _starting ? null : _start,
                  child: Text(_starting ? 'Starting…' : 'Start'),
                ),
              ] else
                _HotspotQr(info: info),
              if (_error != null) ...[
                const SizedBox(height: 16),
                WarningBox(icon: Icons.error_outline, text: _error!),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HotspotQr extends StatelessWidget {
  const _HotspotQr({required this.info});

  final HotspotInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'On the iPhone: CrossDrop > Send > Scan QR code.',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Center(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: QrImageView(
              data: info.qrPayload,
              size: 240,
              semanticsLabel: 'QR code to join this phone\'s network',
            ),
          ),
        ),
        const SizedBox(height: 16),
        SelectableText(
          'Network: ${info.ssid}\nPassword: ${info.password}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Keep this screen open until the transfer is done. The network '
          'stops when you leave it.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Until Phase 7: the hotspot from Android settings works the same way.
class _ManualAndroidHotspot extends StatelessWidget {
  const _ManualAndroidHotspot();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: const [
      WarningBox(
        icon: Icons.info_outline,
        text:
            'Starting the network from CrossDrop comes in the next update. '
            'Until then, use the hotspot in Android settings.',
      ),
      SizedBox(height: 16),
      NumberedSteps(
        steps: [
          'On this phone, open Settings and turn on Hotspot (it may be under '
              'Network & internet or Connections > Mobile Hotspot). Note its '
              'name and password.',
          'On the iPhone, open Settings > Wi-Fi and join that network.',
          'Open CrossDrop on both phones. They find each other as on any '
              'Wi-Fi. If not, use Show my QR code on the receiving phone and '
              'Scan QR code on the sending phone.',
          'Files go straight between the phones. Mobile data is not used '
              'for the transfer, but the iPhone may use this phone\'s data '
              'for other apps while joined.',
        ],
      ),
    ],
  );
}

/// iPhone: join the Android phone's CrossDrop network. Phase 7 joins it
/// from the QR code; until then, from Settings.
class JoinAndroidHotspotScreen extends StatelessWidget {
  const JoinAndroidHotspotScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Join the Android's network")),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        NumberedSteps(
          steps: [
            'On the Android phone, open CrossDrop > Send > Can\'t find the '
                'other phone? > Hotspot mode > This phone makes the network.',
            'It shows a network name and password. On this iPhone, open '
                'Settings > Wi-Fi and join that network. iOS may say "No '
                'Internet Connection": that is fine.',
            'Come back to CrossDrop. The phones find each other. If not, '
                'scan the receiving phone\'s QR code.',
          ],
        ),
      ],
    ),
  );
}

/// iPhone Personal Hotspot, turned on by the user; apps cannot (scenario
/// 5). The same steps on either phone.
class PersonalHotspotGuide extends StatelessWidget {
  const PersonalHotspotGuide({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('iPhone Personal Hotspot')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        NumberedSteps(
          steps: [
            'On the iPhone, open Settings > Personal Hotspot and turn on '
                'Allow Others to Join. Note the Wi-Fi password.',
            'Keep that Settings screen open until the Android phone has '
                'joined: iOS hides the network otherwise.',
            'On the Android phone, open Settings > Wi-Fi and join the '
                "network with the iPhone's name.",
            'Open CrossDrop on both phones. They find each other. If not, '
                'use Show my QR code on the receiving phone and Scan QR code '
                'on the sending phone.',
          ],
        ),
        SizedBox(height: 16),
        WarningBox(
          icon: Icons.info_outline,
          text:
              'The transfer itself uses no mobile data. If the Android phone '
              'warns that the network has no internet, choose to stay '
              'connected.',
        ),
      ],
    ),
  );
}
