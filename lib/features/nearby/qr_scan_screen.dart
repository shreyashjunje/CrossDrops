import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/providers.dart';
import '../../core/protocol/connect_payload.dart';

/// Scans the receiver's QR code. Pops with a [ConnectPayload].
///
/// The scanned text is never logged or shown (CLAUDE.md hard rule 7).
class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  String? _message;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final raw = code.rawValue;
      if (raw == null) continue;
      try {
        final payload = ConnectPayload.parse(raw);
        _done = true;
        Navigator.of(context).pop(payload);
        return;
      } on ConnectPayloadException catch (e) {
        setState(
          () => _message = switch (e.error) {
            ConnectPayloadError.notCrossDrop =>
              'This is not a CrossDrop code. On the other phone, tap '
                  '"Show my QR code" and scan that.',
            ConnectPayloadError.unsupportedVersion =>
              'The other phone has a newer CrossDrop. Update CrossDrop on '
                  'this phone.',
            ConnectPayloadError.invalid =>
              'This CrossDrop code is damaged or not for this network.',
          },
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR code')),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => _CameraError(
                error: error,
                onOpenSettings: () =>
                    ref.read(localNetworkProvider).openSettings(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _message ??
                  'Point the camera at the code the other phone shows under '
                      '"Show my QR code".',
              style: _message == null
                  ? null
                  : TextStyle(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error, required this.onOpenSettings});

  final MobileScannerException error;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, size: 48),
            const SizedBox(height: 16),
            Text(
              denied
                  ? 'CrossDrop needs the camera to scan the QR code. Allow '
                        'camera access in Settings, or type the address '
                        'instead.'
                  : 'The camera could not start. Type the address instead.',
              textAlign: TextAlign.center,
            ),
            if (denied) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onOpenSettings,
                child: const Text('Open Settings'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
