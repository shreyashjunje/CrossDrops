import 'package:crossdrop/core/discovery/network_monitor.dart';
import 'package:crossdrop/core/discovery/peer_list.dart';
import 'package:crossdrop/core/discovery/subnet.dart';
import 'package:crossdrop/core/protocol/connect_payload.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:crossdrop/features/hotspot/hotspot_controller.dart';
import 'package:crossdrop/features/hotspot/hotspot_screens.dart';
import 'package:crossdrop/features/hotspot/join_flow.dart';
import 'package:crossdrop/features/hotspot/joined_hotspot.dart';
import 'package:crossdrop/features/hotspot/personal_hotspot_guide.dart';
import 'package:crossdrop/features/receive/receive_host.dart';
import 'package:crossdrop/platform/hotspot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'join_flow_test.dart' show FakeJoiner;

const _wifi = WifiCredentials(ssid: 'AndroidShare_1', password: 'secret123');

class FakeHotspot implements HotspotService {
  FakeHotspot({this.failWith});
  final String? failWith;
  int stops = 0;
  List<LocalAddress> addresses = const [];

  @override
  Future<HotspotSupport> support() async => HotspotSupport.available;

  @override
  Future<WifiCredentials> start() async {
    if (failWith != null) throw HotspotException(failWith!);
    addresses = const [LocalAddress('192.168.49.1', 'swlan0')];
    return _wifi;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Stream<void> get stopped => const Stream.empty();
}

Future<void> pump(
  WidgetTester tester,
  Widget screen, {
  FakeHotspot? hotspot,
  HotspotJoiner? joiner,
}) {
  final h = hotspot ?? FakeHotspot();
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        hotspotServiceProvider.overrideWithValue(h),
        localAddressesProvider.overrideWithValue(() async => h.addresses),
        transfersActiveProvider.overrideWith((ref) => false),
        // No receive server: the hotspot screen shows the Camera code.
        receiveAllowedProvider.overrideWithValue(false),
        if (joiner != null) hotspotJoinerProvider.overrideWithValue(joiner),
      ],
      child: MaterialApp(home: screen),
    ),
  );
}

void main() {
  testWidgets('Android: make a network, or join the iPhone', (tester) async {
    await pump(
      tester,
      const HotspotModeScreen(platform: DevicePlatform.android),
    );
    expect(find.text('This phone makes the network'), findsOneWidget);
    expect(find.text("Join the iPhone's Personal Hotspot"), findsOneWidget);
  });

  testWidgets('iPhone: join the Android, or Personal Hotspot', (tester) async {
    await pump(tester, const HotspotModeScreen(platform: DevicePlatform.ios));
    expect(find.text("Join the Android phone's network"), findsOneWidget);
    await tester.tap(find.text('This iPhone makes the network'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Allow Others to Join'), findsOneWidget);
    expect(find.textContaining('Step 1 of 3'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Step 2 of 3'), findsOneWidget);
  });

  testWidgets('Start shows the network; leaving stops it', (tester) async {
    final hotspot = FakeHotspot();
    await pump(tester, const AndroidHotspotScreen(), hotspot: hotspot);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Network: AndroidShare_1'), findsOneWidget);
    // No receive server in this test: the Camera code is shown.
    expect(find.textContaining('Camera app'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(hotspot.stops, 1);
  });

  testWidgets('tethering on: says why and offers the manual way', (
    tester,
  ) async {
    await pump(
      tester,
      const AndroidHotspotScreen(),
      hotspot: FakeHotspot(failWith: HotspotErrors.tetheringOn),
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.textContaining('tethering'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text("Or use this phone's own hotspot"), findsOneWidget);
  });

  testWidgets('permission refused: offers app settings', (tester) async {
    await pump(
      tester,
      const AndroidHotspotScreen(),
      hotspot: FakeHotspot(failWith: HotspotErrors.permission),
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('Open app settings'), findsOneWidget);
  });

  group('join screen (iPhone)', () {
    const payload = ConnectPayload(
      ip: '192.168.49.1',
      port: 40000,
      fingerprint:
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      deviceId: '3f2a9c1b-0d4e-4f5a-8b6c-7d8e9f0a1b2c',
      name: 'Pixel',
      wifi: _wifi,
    );

    HotspotJoinFlow flow(HotspotJoiner joiner, bool Function() answers) =>
        HotspotJoinFlow(
          payload: payload,
          joiner: joiner,
          reachable: (_, _, _) async => answers(),
          poll: const Duration(milliseconds: 10),
          manualPoll: const Duration(milliseconds: 10),
          waitTimeout: const Duration(milliseconds: 100),
        );

    testWidgets('manual join: name, password and Copy', (tester) async {
      var answers = false;
      final joiner = FakeJoiner(capable: false);
      await pump(
        tester,
        JoinHotspotScreen(payload: payload, flow: flow(joiner, () => answers)),
        joiner: joiner,
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Copy password'), findsOneWidget);
      expect(find.textContaining('Password: secret123'), findsOneWidget);
      answers = true;
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text("Connected to Pixel's network"), findsOneWidget);
      expect(find.text('Send files to Pixel'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Cancel on the prompt offers both ways on', (tester) async {
      final joiner = FakeJoiner(outcomes: [JoinOutcome.userDenied]);
      await pump(
        tester,
        JoinHotspotScreen(payload: payload, flow: flow(joiner, () => false)),
        joiner: joiner,
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Join in Settings instead'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('joined from the app: remembered for removal', (tester) async {
      final joiner = FakeJoiner();
      var answers = false;
      final f = flow(joiner, () => answers);
      await pump(
        tester,
        JoinHotspotScreen(payload: payload, flow: f),
        joiner: joiner,
      );
      await tester.pump(const Duration(milliseconds: 20));
      answers = true;
      await tester.pump(const Duration(milliseconds: 50));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(JoinHotspotScreen)),
      );
      expect(container.read(joinedHotspotProvider), 'AndroidShare_1');
      await container.read(joinedHotspotProvider.notifier).forget();
      expect(joiner.forgotten, ['AndroidShare_1']);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Personal Hotspot check', () {
    test('iPhone sharing: a bridge interface in 172.20.10.0/28', () {
      expect(
        personalHotspotLink(DevicePlatform.ios, const [
          InterfaceAddress('en0', '192.168.1.5', 24),
          InterfaceAddress('bridge100', '172.20.10.1', 28),
        ]),
        PersonalHotspotLink.sharing,
      );
      expect(
        personalHotspotLink(DevicePlatform.ios, const [
          InterfaceAddress('en0', '192.168.1.5', 24),
        ]),
        PersonalHotspotLink.none,
      );
    });

    test('Android joined: Wi-Fi in the iPhone range', () {
      expect(
        personalHotspotLink(DevicePlatform.android, const [
          InterfaceAddress('wlan0', '172.20.10.3', 28),
        ]),
        PersonalHotspotLink.joined,
      );
      expect(
        personalHotspotLink(DevicePlatform.android, const [
          InterfaceAddress('rmnet0', '172.20.10.3', 28),
        ]),
        PersonalHotspotLink.none,
      );
    });

    test('peers on the same network', () {
      Peer peer(String name, String host) => Peer(
        deviceId: name,
        name: name,
        platform: DevicePlatform.ios,
        host: host,
        port: 1,
        fingerprintHint: null,
        version: 1,
      );
      final same = peersOnSameNetwork(
        const [InterfaceAddress('wlan0', '172.20.10.3', 28)],
        [peer('iPhone', '172.20.10.1'), peer('Laptop', '192.168.1.9')],
      );
      expect(same.map((p) => p.name), ['iPhone']);
    });

    test('assumed prefixes when the platform cannot say', () {
      expect(
        withAssumedPrefix(const [
          LocalAddress('172.20.10.2', 'en0'),
          LocalAddress('192.168.1.4', 'en0'),
        ]).map((a) => a.prefix),
        [28, 24],
      );
    });
  });

  group('hotspot suggestion', () {
    test('only when discovery and an address both failed', () {
      expect(
        suggestHotspot(
          searchedLong: true,
          peerCount: 0,
          addressUnreachable: true,
        ),
        isTrue,
      );
      expect(
        suggestHotspot(
          searchedLong: true,
          peerCount: 0,
          addressUnreachable: false,
        ),
        isFalse,
      );
      expect(
        suggestHotspot(
          searchedLong: false,
          peerCount: 0,
          addressUnreachable: true,
        ),
        isFalse,
      );
      expect(
        suggestHotspot(
          searchedLong: true,
          peerCount: 1,
          addressUnreachable: true,
        ),
        isFalse,
      );
    });

    testWidgets('explains guest Wi-Fi and opens hotspot mode', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: HotspotSuggestion(onOpen: () => opened++)),
        ),
      );
      expect(find.textContaining('Guest and public Wi-Fi'), findsOneWidget);
      await tester.tap(find.text('Use hotspot mode'));
      expect(opened, 1);
    });
  });

  test('error messages never fall back to an empty string', () {
    for (final code in [
      HotspotErrors.permission,
      HotspotErrors.locationOff,
      HotspotErrors.tetheringOn,
      HotspotErrors.noChannel,
      HotspotErrors.disallowed,
      HotspotErrors.unsupportedSecurity,
      HotspotErrors.busy,
      'no_address',
      'stopped',
      null,
    ]) {
      expect(hotspotErrorMessage(code), isNotEmpty);
    }
  });
}
