import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../core/bench/bench.dart';
import '../../core/protocol/connect_payload.dart';
import '../../core/security/device_identity.dart';
import '../../platform/hotspot.dart';
import '../bench/bench_screen.dart';
import '../nearby/qr_scan_screen.dart';
import '../receive/receive_controller.dart';
import '../receive/receive_host.dart';
import '../send/send_screen.dart';
import '../transfer/widgets.dart';
import 'hotspot_controller.dart';
import 'join_flow.dart';
import 'joined_hotspot.dart';
import 'numbered_steps.dart';
import 'personal_hotspot_guide.dart';

export 'hotspot_controller.dart' show hotspotServiceProvider;
export 'personal_hotspot_guide.dart' show PersonalHotspotGuide;

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
              onTap: () => open(PersonalHotspotGuide(platform: me)),
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
              onTap: () => open(PersonalHotspotGuide(platform: me)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Suggest hotspot mode when nothing was found nearby and a QR code or
/// typed address did not answer either: the Wi-Fi likely keeps phones
/// apart (ARCHITECTURE.md, scenario 3).
bool suggestHotspot({
  required bool searchedLong,
  required int peerCount,
  required bool addressUnreachable,
}) => searchedLong && peerCount == 0 && addressUnreachable;

/// The card shown when [suggestHotspot] is true.
class HotspotSuggestion extends StatelessWidget {
  const HotspotSuggestion({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "The phones can't reach each other on this Wi-Fi",
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Guest and public Wi-Fi (cafés, hotels, airports, many '
              'offices) often keeps phones apart, so they cannot see or '
              'reach each other. Hotspot mode makes a small network between '
              'the two phones. It needs no internet and the transfer uses no '
              'mobile data.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Use hotspot mode'),
              onPressed: onOpen,
            ),
          ],
        ),
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

/// Words for a hotspot that did not start, or stopped.
String hotspotErrorMessage(String? code) => switch (code) {
  HotspotErrors.permission =>
    'CrossDrop needs the Nearby devices permission (Location on Android 12 '
        'and older) to make the network. It does not use your location.',
  HotspotErrors.locationOff =>
    'Turn on Location in quick settings, then try again. Android 12 and '
        'older need it to make a network; CrossDrop does not use your '
        'location.',
  HotspotErrors.tetheringOn =>
    "Turn off the phone's own hotspot (tethering) first, then try again.",
  HotspotErrors.noChannel =>
    'No free Wi-Fi channel. Turn Wi-Fi off and on, then try again.',
  HotspotErrors.disallowed =>
    'This phone does not allow hotspots (a work profile or carrier '
        "setting). Use the phone's own hotspot or the iPhone's Personal "
        'Hotspot instead.',
  HotspotErrors.unsupportedSecurity =>
    'This phone made a network without a password, which CrossDrop does '
        'not use. Try again.',
  'no_address' => 'The network started but got no address. Try again.',
  'stopped' =>
    'The network was stopped (from quick settings or by Android). Start '
        'it again if you still need it.',
  _ => 'The network could not start. Try again.',
};

/// Android: start a local-only hotspot and show one QR code with its name,
/// password and the connection (ARCHITECTURE.md, "QR code payload"). The
/// hotspot lives as long as this screen (D-054).
class AndroidHotspotScreen extends ConsumerWidget {
  const AndroidHotspotScreen({super.key});

  Future<bool> _confirmLeave(BuildContext context) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop the network?'),
        content: const Text(
          'A transfer is running over this network. Leaving stops the '
          'network and pauses the transfer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Stop and leave'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hotspotControllerProvider);
    final controller = ref.read(hotspotControllerProvider.notifier);
    final busy = ref.watch(transfersActiveProvider) && state.isRunning;
    return PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave(context) && context.mounted) {
          await controller.stop();
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Make a network')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            switch (state.phase) {
              HotspotPhase.running => _HotspotRunning(state: state),
              HotspotPhase.starting => const Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Starting the network…'),
                  ],
                ),
              ),
              _ => _HotspotIdle(
                error: state.phase == HotspotPhase.failed ? state.error : null,
                onStart: controller.start,
                onOpenSettings: () =>
                    ref.read(localNetworkProvider).openSettings(),
              ),
            },
          ],
        ),
      ),
    );
  }
}

class _HotspotIdle extends StatelessWidget {
  const _HotspotIdle({
    required this.error,
    required this.onStart,
    required this.onOpenSettings,
  });

  final String? error;
  final VoidCallback onStart;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const NumberedSteps(
        steps: [
          'Tap Start. This phone makes a Wi-Fi network just for CrossDrop. '
              'It has no internet and uses no mobile data.',
          'On the iPhone, open CrossDrop > Send > Scan QR code (or Hotspot '
              "mode > Join the Android phone's network) and scan the code "
              'shown here.',
          'The iPhone joins the network and connects.',
        ],
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: onStart,
        child: Text(error == null ? 'Start' : 'Try again'),
      ),
      if (error != null) ...[
        const SizedBox(height: 16),
        WarningBox(icon: Icons.error_outline, text: hotspotErrorMessage(error)),
        if (error == HotspotErrors.permission)
          TextButton(
            onPressed: onOpenSettings,
            child: const Text('Open app settings'),
          ),
        const SizedBox(height: 8),
        const _ManualAndroidHotspot(),
      ],
    ],
  );
}

class _HotspotRunning extends ConsumerStatefulWidget {
  const _HotspotRunning({required this.state});

  final HotspotState state;

  @override
  ConsumerState<_HotspotRunning> createState() => _HotspotRunningState();
}

class _HotspotRunningState extends ConsumerState<_HotspotRunning> {
  bool _cameraQr = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wifi = widget.state.wifi!;
    final ip = widget.state.address!.ip;
    // Rebuild when the server starts, stops or moves to a new port.
    final port = ref.watch(receiveStateProvider.select((s) => s.port));
    final base = port == null
        ? null
        : ref.read(receiveControllerProvider.notifier).payloadFor(ip);
    final payload = base == null
        ? null
        : ConnectPayload(
            ip: base.ip,
            port: base.port,
            fingerprint: base.fingerprint,
            deviceId: base.deviceId,
            name: base.name,
            wifi: wifi,
          ).toUri();
    final showCamera = _cameraQr || payload == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.state.stopsAt case final at?)
          _StopCountdown(
            at: at,
            onKeepOn: ref.read(hotspotControllerProvider.notifier).keepOn,
          ),
        Text(
          showCamera
              ? 'On the iPhone: open the Camera app and point it at this code, '
                    'then tap Join. Then scan the CrossDrop code from CrossDrop.'
              : 'On the iPhone: CrossDrop > Send > Scan QR code.',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Center(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: QrImageView(
              data: showCamera ? wifiJoinQr(wifi) : payload,
              size: 240,
              semanticsLabel: showCamera
                  ? "Wi-Fi QR code for the iPhone's Camera app"
                  : "QR code to join this phone's network and connect",
            ),
          ),
        ),
        if (payload != null)
          TextButton(
            onPressed: () => setState(() => _cameraQr = !_cameraQr),
            child: Text(
              _cameraQr
                  ? 'Show the CrossDrop code'
                  : 'Show a code for the iPhone Camera',
            ),
          )
        else
          const WarningBox(
            icon: Icons.info_outline,
            text:
                'Receiving is off, so this phone can only send. Turn on '
                'Receiving on Home to receive from the iPhone.',
          ),
        const SizedBox(height: 8),
        SelectableText(
          'Network: ${wifi.ssid}\nPassword: ${wifi.password}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.send),
          label: const Text('Send files to the iPhone'),
          onPressed: () =>
              pushScreen<void>(context, Routes.send, const SendScreen()),
        ),
        if (benchBuild)
          // The network lives with this screen, so the benchmark opens on
          // top of it (D-058).
          TextButton(
            onPressed: () =>
                pushScreen<void>(context, Routes.settings, const BenchScreen()),
            child: const Text('Benchmark (test build)'),
          ),
        const SizedBox(height: 8),
        const Text(
          'Keep this screen open until you are done: the network stops when '
          'you leave it, and a minute after the last transfer.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _StopCountdown extends StatefulWidget {
  const _StopCountdown({required this.at, required this.onKeepOn});

  final DateTime at;
  final VoidCallback onKeepOn;

  @override
  State<_StopCountdown> createState() => _StopCountdownState();
}

class _StopCountdownState extends State<_StopCountdown> {
  late final Timer _tick = Timer.periodic(
    const Duration(seconds: 1),
    (_) => setState(() {}),
  );

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.at.difference(DateTime.now()).inSeconds.clamp(0, 999);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: Text('Transfer done. The network stops in $left s.'),
          trailing: TextButton(
            onPressed: widget.onKeepOn,
            child: const Text('Keep on'),
          ),
        ),
      ),
    );
  }
}

/// Fallback when the app cannot start a network: Android's own hotspot
/// works the same way, but shares mobile data.
class _ManualAndroidHotspot extends StatelessWidget {
  const _ManualAndroidHotspot();

  @override
  Widget build(BuildContext context) => const ExpansionTile(
    title: Text("Or use this phone's own hotspot"),
    childrenPadding: EdgeInsets.symmetric(horizontal: 16),
    children: [
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

/// iPhone: join the Android phone's CrossDrop network by scanning its QR
/// code (D-055).
class JoinAndroidHotspotScreen extends StatelessWidget {
  const JoinAndroidHotspotScreen({super.key});

  Future<void> _scan(BuildContext context) async {
    final payload = await Navigator.of(context).push<ConnectPayload>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (payload == null || !context.mounted) return;
    if (payload.wifi == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'That code has no network in it. On the Android, open Hotspot '
            'mode > This phone makes the network, and scan the code there.',
          ),
        ),
      );
      return;
    }
    await pushScreen<bool>(
      context,
      Routes.hotspot,
      JoinHotspotScreen(payload: payload),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Join the Android's network")),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const NumberedSteps(
          steps: [
            'On the Android phone, open CrossDrop > Send > Can\'t find the '
                'other phone? > Hotspot mode > This phone makes the network, '
                'and tap Start.',
            'Tap Scan QR code below and scan the code on the Android.',
            'Tap Join when the iPhone asks. If it does not ask, CrossDrop '
                'shows how to join in Settings.',
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan QR code'),
          onPressed: () => _scan(context),
        ),
      ],
    ),
  );
}

/// Joins the hotspot from a scanned code and waits until the receiver
/// answers. With [popWhenConnected] it pops `true` at that point (the
/// Nearby screen then connects); otherwise it offers Send and Receive.
class JoinHotspotScreen extends ConsumerStatefulWidget {
  const JoinHotspotScreen({
    super.key,
    required this.payload,
    this.popWhenConnected = false,
    this.flow,
  });

  final ConnectPayload payload;
  final bool popWhenConnected;

  /// Set in tests.
  final HotspotJoinFlow? flow;

  @override
  ConsumerState<JoinHotspotScreen> createState() => _JoinHotspotScreenState();
}

class _JoinHotspotScreenState extends ConsumerState<JoinHotspotScreen> {
  late final HotspotJoinFlow _flow =
      widget.flow ??
      HotspotJoinFlow(
        payload: widget.payload,
        joiner: ref.read(hotspotJoinerProvider),
      );

  @override
  void initState() {
    super.initState();
    _flow.status.addListener(_onStatus);
    unawaited(_flow.run());
  }

  void _onStatus() {
    if (_flow.status.value.step != JoinStep.connected) return;
    if (_flow.addedNetwork) {
      ref.read(joinedHotspotProvider.notifier).remember(_flow.wifi.ssid);
    }
    if (widget.popWhenConnected && mounted) Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _flow.status.removeListener(_onStatus);
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ssid = _flow.wifi.ssid;
    final name = widget.payload.name;
    return Scaffold(
      appBar: AppBar(title: Text("Join $name's network")),
      body: ValueListenableBuilder<JoinStatus>(
        valueListenable: _flow.status,
        builder: (context, status, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: switch (status.step) {
            JoinStep.checking => const [_Busy('Checking the connection…')],
            JoinStep.joining => [
              _Busy('Tap Join on the iPhone\'s message to join "$ssid".'),
            ],
            JoinStep.waiting => [
              _Busy(
                'Joining "$ssid"… The iPhone may say "No Internet '
                'Connection": that is fine.',
              ),
            ],
            JoinStep.manual => [_ManualJoin(wifi: _flow.wifi)],
            JoinStep.denied => [
              const WarningBox(
                icon: Icons.info_outline,
                text:
                    'The iPhone did not join, because Cancel was tapped. '
                    'CrossDrop needs to join the Android\'s network to send '
                    'files without Wi-Fi.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _flow.retry,
                child: const Text('Try again'),
              ),
              TextButton(
                onPressed: _flow.useManual,
                child: const Text('Join in Settings instead'),
              ),
            ],
            JoinStep.failed => [
              WarningBox(
                icon: Icons.error_outline,
                text: switch (status.error) {
                  'timeout' =>
                    'The iPhone joined, but the Android does not answer. '
                        'Check that its "Make a network" screen is still '
                        'open.',
                  'invalid' =>
                    'The iPhone refused this network\'s name or password. '
                        'Start the network again on the Android and scan '
                        'the new code.',
                  _ => 'The iPhone could not join the network.',
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _flow.retry,
                child: const Text('Try again'),
              ),
              TextButton(
                onPressed: _flow.useManual,
                child: const Text('Join in Settings instead'),
              ),
            ],
            JoinStep.connected => [
              ListTile(
                leading: const Icon(Icons.check_circle, size: 32),
                title: Text("Connected to $name's network"),
                subtitle: const Text(
                  'Keep CrossDrop open on both phones until you are done.',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.send),
                label: Text('Send files to $name'),
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: Routes.send),
                    builder: (_) => const SendScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'To receive instead: on the Android, tap Send files to the '
                'iPhone. This iPhone is ready to receive while CrossDrop is '
                'open.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          },
        ),
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(text, textAlign: TextAlign.center),
      ],
    ),
  );
}

/// Joining in Settings > Wi-Fi: builds without the Hotspot Configuration
/// capability (free Apple ID, D-017), or when iOS refuses in-app.
class _ManualJoin extends StatelessWidget {
  const _ManualJoin({required this.wifi});

  final WifiCredentials wifi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NumberedSteps(
          steps: [
            'Tap Copy password below.',
            'Open the Settings app > Wi-Fi and tap "${wifi.ssid}".',
            'Paste the password and tap Join. "No Internet Connection" is '
                'fine.',
            'Come back to CrossDrop. It goes on by itself.',
          ],
        ),
        const SizedBox(height: 8),
        SelectableText(
          'Network: ${wifi.ssid}\nPassword: ${wifi.password}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: const Icon(Icons.copy),
          label: const Text('Copy password'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: wifi.password));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Password copied')));
            }
          },
        ),
        const SizedBox(height: 16),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Waiting for the network…'),
          ],
        ),
      ],
    );
  }
}
