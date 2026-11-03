import 'package:flutter/material.dart';

import '../features/home/home_screen.dart';
import '../features/send/share_listener.dart';
import 'navigation.dart';
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
      home: const ShareListener(child: HomeScreen()),
    );
  }
}
