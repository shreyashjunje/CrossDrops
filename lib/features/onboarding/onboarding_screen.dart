import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/security/device_identity.dart';

/// One page of the introduction.
class OnboardingPage {
  const OnboardingPage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final List<String> body;
}

/// The three pages: both phones need the app open, why Local Network
/// access is needed, and what to do when phones do not find each other
/// (docs/features/onboarding.md).
List<OnboardingPage> onboardingPages(DevicePlatform platform) => [
  const OnboardingPage(
    icon: Icons.compare_arrows,
    title: 'Open CrossDrop on both phones',
    body: [
      'CrossDrop sends photos, videos and files straight between an '
          'iPhone and an Android phone, in original quality.',
      'Both phones need CrossDrop open, close to each other, until the '
          'files have arrived. Nothing goes through the internet.',
    ],
  ),
  switch (platform) {
    DevicePlatform.ios => const OnboardingPage(
      icon: Icons.wifi_find,
      title: 'Allow Local Network',
      body: [
        'To find the other phone on your Wi-Fi, iPhone asks whether '
            'CrossDrop may use the local network. When it asks, tap Allow.',
        'CrossDrop only talks to phones near you. If you tap Don\'t Allow, '
            'phones cannot find this iPhone; you can change it later in '
            'Settings > Privacy & Security > Local Network.',
      ],
    ),
    DevicePlatform.android => const OnboardingPage(
      icon: Icons.wifi_find,
      title: 'Same Wi-Fi, no internet needed',
      body: [
        'CrossDrop finds the other phone on your Wi-Fi or hotspot, and '
            'sends files straight to it. It never uploads them anywhere.',
        'Android asks for other permissions only when they are needed: '
            'photos when you pick them, the camera when you scan a code, '
            'notifications when a transfer starts.',
      ],
    ),
  },
  const OnboardingPage(
    icon: Icons.travel_explore,
    title: "If the phones don't find each other",
    body: [
      '1. Check that both phones are on the same Wi-Fi with CrossDrop open.',
      '2. Use the QR code: on the receiving phone tap "Show my QR code", on '
          'the sending phone tap Scan QR code.',
      '3. No Wi-Fi, or a Wi-Fi that blocks phones (hotels, cafes)? Use '
          'hotspot mode. It is under Send > "Can\'t find the other phone?".',
    ],
  ),
];

/// The first-launch introduction. Done marks it shown, which also lets
/// receiving start, so the iOS Local Network prompt follows the page that
/// explains it (D-050). With [replay], it only closes.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.replay = false, this.platform});

  final bool replay;

  /// This phone; defaults to the real platform. Set in tests.
  final DevicePlatform? platform;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (widget.replay) {
      Navigator.of(context).pop();
      return;
    }
    await ref.read(settingsRepositoryProvider).setOnboardingDone(true);
  }

  void _next(int count) {
    if (_page == count - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = onboardingPages(widget.platform ?? DevicePlatform.current);
    final last = _page == pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: last
                  ? const SizedBox(height: 48)
                  : TextButton(onPressed: _finish, child: const Text('Skip')),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  for (final (i, p) in pages.indexed)
                    _Page(page: p, index: i, count: pages.length),
                ],
              ),
            ),
            _Dots(count: pages.length, current: _page),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: () => _next(pages.length),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: Text(
                  last ? (widget.replay ? 'Close' : 'Get started') : 'Next',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.page, required this.index, required this.count});

  final OnboardingPage page;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrolls when the system text size is large.
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      children: [
        Icon(page.icon, size: 96, color: theme.colorScheme.primary),
        const SizedBox(height: 24),
        Semantics(
          header: true,
          label: 'Page ${index + 1} of $count. ${page.title}',
          excludeSemantics: true,
          child: Text(
            page.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 16),
        for (final p in page.body)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(p, style: theme.textTheme.bodyLarge),
          ),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The page headers already say "Page 1 of 3".
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              margin: const EdgeInsets.all(4),
              width: i == current ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == current ? scheme.primary : scheme.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}
