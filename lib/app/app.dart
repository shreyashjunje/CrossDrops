import 'package:flutter/material.dart';

import '../features/onboarding/onboarding_gate.dart';
import '../features/receive/receive_host.dart';
import '../features/send/share_listener.dart';
import 'navigation.dart';
import 'network_binding.dart';
import 'root_shell.dart';
import 'theme.dart';

class CrossDropApp extends StatelessWidget {
  const CrossDropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CrossDrop',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      navigatorObservers: [topRouteObserver],
      // Above the navigator, so receiving runs on every screen (D-046),
      // and Android stays on a Wi-Fi without internet (D-056).
      builder: (_, navigator) =>
          NetworkBindingHost(child: ReceiveHost(child: navigator!)),
      home: const ShareListener(child: OnboardingGate(child: RootShell())),
    );
  }
}
