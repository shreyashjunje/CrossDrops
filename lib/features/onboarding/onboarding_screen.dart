import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
import '../../core/security/device_identity.dart';
import 'onboarding_art.dart';

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
    // Reduced motion: no slide, straight to the next page (D-069).
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.jumpToPage(_page + 1);
      return;
    }
    _controller.nextPage(duration: CdMotion.base, curve: CdMotion.enter);
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
                  : TextButton(
                      onPressed: _finish,
                      style: TextButton.styleFrom(
                        foregroundColor: context.cd.text2,
                      ),
                      child: const Text('Skip'),
                    ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  for (final (i, p) in pages.indexed)
                    _Page(
                      page: p,
                      index: i,
                      count: pages.length,
                      platform: widget.platform ?? DevicePlatform.current,
                    ),
                ],
              ),
            ),
            _Dots(count: pages.length, current: _page),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CdSpace.gutter,
                16,
                CdSpace.gutter,
                16,
              ),
              child: FilledButton(
                onPressed: () => _next(pages.length),
                style: CdButtonStyles.wide,
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
  const _Page({
    required this.page,
    required this.index,
    required this.count,
    required this.platform,
  });

  final OnboardingPage page;
  final int index;
  final int count;
  final DevicePlatform platform;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    // Scrolls when the system text size is large.
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: CdSpace.gutter),
      children: [
        OnboardingArt(index: index, platform: platform),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          label: 'Page ${index + 1} of $count. ${page.title}',
          excludeSemantics: true,
          child: Text(page.title, style: CdType.h1.copyWith(color: c.text)),
        ),
        const SizedBox(height: 12),
        for (final (i, p) in page.body.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              p,
              style: (i == 0 ? CdType.bodyL : CdType.bodyM).copyWith(
                color: i == 0 ? c.text2 : c.text3,
              ),
            ),
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
    final c = context.cd;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // The page headers already say "Page 1 of 3".
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: reduce ? Duration.zero : CdMotion.base,
              curve: CdMotion.enter,
              margin: const EdgeInsets.all(3),
              width: i == current ? 24 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == current ? c.accent : c.lineStrong,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }
}
