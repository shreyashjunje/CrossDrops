import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'onboarding_screen.dart';

/// Shows the introduction on first launch, then [child] (D-050).
class OnboardingGate extends ConsumerWidget {
  const OnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (ref.watch(onboardingDoneProvider)) {
        AsyncData(value: true) => child,
        AsyncData(value: false) => const OnboardingScreen(),
        // A database that cannot be read must not lock the user out.
        AsyncError() => child,
        _ => const Scaffold(),
      };
}
