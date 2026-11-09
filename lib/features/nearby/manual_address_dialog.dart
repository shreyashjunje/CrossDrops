import 'package:flutter/material.dart';

import '../../app/tokens.dart';
import '../../core/protocol/connect_payload.dart';

/// Validates a typed IPv4 address: a dotted literal on a local network.
/// Returns an error message, or null when valid.
String? validateManualHost(String text) {
  final octets = parseIPv4(text.trim());
  if (octets == null) return 'Enter an address like 192.168.1.23';
  if (!isLocalIPv4(octets)) {
    return 'Use the local address shown under "Show my QR code"';
  }
  return null;
}

/// Validates a typed port. Returns an error message, or null when valid.
String? validateManualPort(String text) {
  final port = int.tryParse(text.trim());
  if (port == null || port < 1 || port > 65535 || text.trim() != '$port') {
    return 'Enter the port shown under "Show my QR code"';
  }
  return null;
}

/// Asks for the receiver's IP and port. Pops with `(host, port)`.
class ManualAddressDialog extends StatefulWidget {
  const ManualAddressDialog({super.key});

  @override
  State<ManualAddressDialog> createState() => _ManualAddressDialogState();
}

class _ManualAddressDialogState extends State<ManualAddressDialog> {
  final _form = GlobalKey<FormState>();
  final _host = TextEditingController();
  final _port = TextEditingController();

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.of(context)
        .pop((_host.text.trim(), int.parse(_port.text.trim())));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Type the address'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'On the other phone: Show my QR code \u203a No camera? Type '
              'the address. Copy the two numbers here.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _host,
              autofocus: true,
              style: CdType.h3,
              decoration: const InputDecoration(labelText: 'Address'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) => validateManualHost(v ?? ''),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _port,
              style: CdType.h3,
              decoration: const InputDecoration(labelText: 'Port'),
              keyboardType: TextInputType.number,
              validator: (v) => validateManualPort(v ?? ''),
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Connect')),
      ],
    );
  }
}
