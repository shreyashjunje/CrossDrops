import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens.dart';
import 'usb_import_controller.dart';

/// Cable test (Android): checks whether this phone can reach the CrossDrop
/// app on a plugged-in iPhone over the cable, before Android-to-iPhone by
/// cable is built. Shows the native report for the owner to paste back.
class CableProbeScreen extends ConsumerStatefulWidget {
  const CableProbeScreen({super.key});

  @override
  ConsumerState<CableProbeScreen> createState() => _CableProbeScreenState();
}

class _CableProbeScreenState extends ConsumerState<CableProbeScreen> {
  final _port = TextEditingController();
  bool _running = false;
  String? _report;

  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _report = null;
    });
    final port = int.tryParse(_port.text.trim());
    String report;
    try {
      report = await ref
          .read(usbCameraProvider)
          .probeTunnel(
            port: port != null && port > 0 && port < 65536 ? port : null,
          );
    } on PlatformException catch (e) {
      report = 'FAIL: ${e.code}';
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _report = report;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Cable test')),
      body: ListView(
        padding: const EdgeInsets.all(CdSpace.gutter),
        children: [
          Text(
            '1. Plug the iPhone into this phone and unlock it.\n'
            '2. On the iPhone, open CrossDrop > My QR code and type the port '
            'it shows below.\n'
            '3. Tap Run test. If the iPhone asks to trust this device, tap '
            'Trust, then run the test again.',
            style: CdType.bodyM.copyWith(color: c.text2),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: "iPhone's CrossDrop port (optional)",
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _running ? null : _run,
            child: Text(_running ? 'Testing...' : 'Run test'),
          ),
          if (report != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.surface1,
                borderRadius: BorderRadius.circular(CdRadius.button),
                border: Border.all(color: c.line),
              ),
              child: SelectableText(
                report,
                style: CdType.small.copyWith(
                  fontFamily: 'monospace',
                  color: c.text,
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: report)),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy report'),
            ),
          ],
        ],
      ),
    );
  }
}
