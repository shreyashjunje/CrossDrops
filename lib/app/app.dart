import 'package:flutter/material.dart';

import '../features/home/home_screen.dart';

class CrossDropApp extends StatelessWidget {
  const CrossDropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CrossDrop',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const HomeScreen(),
    );
  }
}
