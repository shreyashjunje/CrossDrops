import 'package:flutter/material.dart';

import '../receive/receive_screen.dart';
import '../send/send_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget screen) =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => screen));

    return Scaffold(
      appBar: AppBar(title: const Text('CrossDrop (Phase 1 PoC)')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton(
              onPressed: () => open(const ReceiveScreen()),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Receive'),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => open(const SendScreen()),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Send'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
