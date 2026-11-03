import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../core/discovery/network_monitor.dart';
import '../../core/discovery/peer_list.dart';
import '../../core/discovery/subnet.dart';
import '../../core/security/device_identity.dart';
import '../nearby/nearby_controller.dart';
import '../receive/my_qr_screen.dart';
import '../send/send_screen.dart';
import '../transfer/widgets.dart';
import 'numbered_steps.dart';

/// What this phone sees of an iPhone Personal Hotspot.
enum PersonalHotspotLink {
  /// Nothing yet.
  none,

  /// iPhone: Personal Hotspot is on and a device has joined (iOS adds a
  /// `bridge` interface at 172.20.10.1).
  sharing,

  /// Android: joined a network in the iPhone hotspot range.
  joined,
}

PersonalHotspotLink personalHotspotLink(
  DevicePlatform me,
  List<InterfaceAddress> mine,
) {
  for (final a in mine) {
    if (!looksLikeIphoneHotspot(a.ip)) continue;
    if (me == DevicePlatform.ios && a.name.startsWith('bridge')) {
      return PersonalHotspotLink.sharing;
    }
    if (me == DevicePlatform.android && a.name.startsWith('wlan')) {
      return PersonalHotspotLink.joined;
    }
  }
  return PersonalHotspotLink.none;
}

/// Nearby phones on the same network as this one.
List<Peer> peersOnSameNetwork(
  List<InterfaceAddress> mine,
  Iterable<Peer> peers,
) => [
  for (final p in peers)
    if (addressSharingSubnet(mine, p.host) != null) p,
];

/// Addresses with a prefix, from `dart:io` when the platform cannot say:
/// /28 in the iPhone hotspot range, else /24, the usual home network.
List<InterfaceAddress> withAssumedPrefix(List<LocalAddress> all) => [
  for (final a in all)
    InterfaceAddress(
      a.interfaceName,
      a.ip,
      looksLikeIphoneHotspot(a.ip) ? 28 : 24,
    ),
];

/// iPhone Personal Hotspot, turned on by the user; apps cannot (scenario
/// 5). Three steps, the same on both phones, with a live check of what
/// this phone sees.
class PersonalHotspotGuide extends ConsumerStatefulWidget {
  const PersonalHotspotGuide({super.key, this.platform});

  /// This phone; defaults to the real platform. Set in tests.
  final DevicePlatform? platform;

  @override
  ConsumerState<PersonalHotspotGuide> createState() =>
      _PersonalHotspotGuideState();
}

class _PersonalHotspotGuideState extends ConsumerState<PersonalHotspotGuide> {
  static const _poll = Duration(seconds: 2);

  int _page = 0;
  List<InterfaceAddress> _mine = const [];
  Timer? _timer;

  DevicePlatform get _me => widget.platform ?? DevicePlatform.current;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(_poll, (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    var mine = await ref.read(networkPlatformProvider).interfaces();
    if (mine.isEmpty) mine = withAssumedPrefix(await listLocalAddresses());
    if (mounted) setState(() => _mine = mine);
  }

  static const _titles = [
    'Turn on Personal Hotspot',
    'Join it from the Android',
    'Check and continue',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = personalHotspotLink(_me, _mine);
    return Scaffold(
      appBar: AppBar(title: const Text('iPhone Personal Hotspot')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Step ${_page + 1} of 3: ${_titles[_page]}',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          _LinkStatus(me: _me, link: link),
          const SizedBox(height: 8),
          switch (_page) {
            0 => const NumberedSteps(
              steps: [
                'On the iPhone, open Settings > Personal Hotspot and turn on '
                    'Allow Others to Join. Note the Wi-Fi password.',
                'Keep that Settings screen open until the Android phone has '
                    'joined: iOS hides the network otherwise.',
                'If the Android cannot see the network, turn on Maximize '
                    'Compatibility on the same screen (slower, but older '
                    'phones see it).',
              ],
            ),
            1 => const NumberedSteps(
              steps: [
                "On the Android phone, open Settings > Wi-Fi and tap the "
                    "network with the iPhone's name.",
                'Type the password from the iPhone and connect.',
                'If Android says the network has no internet, choose to stay '
                    'connected. CrossDrop sends over it anyway.',
              ],
            ),
            _ => _CheckPage(mine: _mine),
          },
          const SizedBox(height: 16),
          Row(
            children: [
              if (_page > 0)
                TextButton(
                  onPressed: () => setState(() => _page--),
                  child: const Text('Back'),
                ),
              const Spacer(),
              if (_page < 2)
                FilledButton(
                  onPressed: () => setState(() => _page++),
                  child: const Text('Next'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const WarningBox(
            icon: Icons.info_outline,
            text:
                'The transfer itself uses no mobile data. Other apps on the '
                "Android may use the iPhone's data while it is joined.",
          ),
        ],
      ),
    );
  }
}

class _LinkStatus extends StatelessWidget {
  const _LinkStatus({required this.me, required this.link});

  final DevicePlatform me;
  final PersonalHotspotLink link;

  @override
  Widget build(BuildContext context) {
    final (ok, text) = switch ((me, link)) {
      (_, PersonalHotspotLink.sharing) => (
        true,
        'Personal Hotspot is on and a phone has joined.',
      ),
      (_, PersonalHotspotLink.joined) => (
        true,
        "This phone is on an iPhone's Personal Hotspot.",
      ),
      (DevicePlatform.ios, _) => (
        false,
        'No phone has joined this iPhone yet.',
      ),
      _ => (false, "This phone is not on an iPhone's hotspot yet."),
    };
    return Semantics(
      liveRegion: true,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(ok ? Icons.check_circle : Icons.hourglass_empty),
        title: Text(text),
      ),
    );
  }
}

/// Step 3: find the other phone on this network, then send or receive.
class _CheckPage extends ConsumerWidget {
  const _CheckPage({required this.mine});

  final List<InterfaceAddress> mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peers = ref.watch(
      nearbyControllerProvider.select((s) => s.peers.values),
    );
    final same = peersOnSameNetwork(mine, peers);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (same.isEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('Looking for the other phone on this network…'),
            subtitle: Text(
              'Open CrossDrop on the other phone too. If it does not show '
              'up, use the QR code.',
            ),
          )
        else
          for (final p in same)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle),
              title: Text('${p.name} is on the same network'),
            ),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: const Icon(Icons.send),
          label: const Text('Send files'),
          onPressed: () =>
              pushScreen<void>(context, Routes.send, const SendScreen()),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.qr_code),
          label: const Text('Show my QR code to receive'),
          onPressed: () =>
              pushScreen<void>(context, Routes.myQr, const MyQrScreen()),
        ),
      ],
    );
  }
}
