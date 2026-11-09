import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/providers.dart';
import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
import '../../core/protocol/connect_payload.dart';

/// Scans the receiver's QR code. Pops with a [ConnectPayload].
///
/// The scanned text is never logged or shown (CLAUDE.md hard rule 7).
class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key, this.onTypeAddress});

  /// "Type the address instead": closes the scanner, then runs this.
  final VoidCallback? onTypeAddress;

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

  void _typeAddress() {
    final next = widget.onTypeAddress;
    Navigator.of(context).pop();
    next?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final message = _message;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR code')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => _CameraError(
                    error: error,
                    onOpenSettings: () =>
                        ref.read(localNetworkProvider).openSettings(),
                    onTypeAddress: widget.onTypeAddress == null
                        ? null
                        : _typeAddress,
                  ),
                ),
                IgnorePointer(
                  child: Center(
                    child: SizedBox.square(
                      dimension: 260,
                      child: CustomPaint(
                        painter: _FramePainter(
                          message == null ? c.accent : c.danger,
                        ),
                      ),
                    ),
                  ),
                ),
                if (message != null)
                  Positioned(
                    left: CdSpace.gutter,
                    right: CdSpace.gutter,
                    bottom: 16,
                    child: Semantics(
                      liveRegion: true,
                      child: NoticeCard(
                        tone: NoticeTone.danger,
                        icon: Icons.error_outline_rounded,
                        text: message,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                CdSpace.gutter,
                16,
                CdSpace.gutter,
                12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Point the camera at the code the other phone shows under '
                    '"Show my QR code".',
                    style: CdType.bodyL.copyWith(color: c.text),
                    textAlign: TextAlign.center,
                  ),
                  if (widget.onTypeAddress != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      style: CdButtonStyles.wide,
                      onPressed: _typeAddress,
                      child: const Text('Type the address instead'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Four rounded corners marking where the code goes.
class _FramePainter extends CustomPainter {
  _FramePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const arm = 40.0, r = 16.0;
    final w = size.width, h = size.height;
    void corner(Offset o, double sx, double sy) {
      final path = Path()
        ..moveTo(o.dx, o.dy + sy * arm)
        ..lineTo(o.dx, o.dy + sy * r)
        ..quadraticBezierTo(o.dx, o.dy, o.dx + sx * r, o.dy)
        ..lineTo(o.dx + sx * arm, o.dy);
      canvas.drawPath(path, p);
    }

    corner(Offset.zero, 1, 1);
    corner(Offset(w, 0), -1, 1);
    corner(Offset(0, h), 1, -1);
    corner(Offset(w, h), -1, -1);
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.color != color;
}

class _CameraError extends StatelessWidget {
  const _CameraError({
    required this.error,
    required this.onOpenSettings,
    this.onTypeAddress,
  });

  final MobileScannerException error;
  final VoidCallback onOpenSettings;
  final VoidCallback? onTypeAddress;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: c.bg,
      child: ListView(
        padding: const EdgeInsets.all(CdSpace.gutter),
        children: [
          const SizedBox(height: 24),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(CdRadius.card),
                border: Border.all(color: c.line),
              ),
              child: Icon(
                Icons.no_photography_outlined,
                size: 32,
                color: c.text2,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            denied
                ? 'CrossDrop needs the camera to scan'
                : 'The camera could not start',
            style: CdType.h2.copyWith(color: c.text),
          ),
          const SizedBox(height: 10),
          Text(
            denied
                ? 'CrossDrop needs the camera to scan the QR code. Allow '
                      'camera access in Settings, or type the address '
                      'instead.'
                : 'The camera could not start. Type the address instead.',
            style: CdType.bodyM.copyWith(color: c.text2),
          ),
          const SizedBox(height: 24),
          if (denied)
            FilledButton(
              style: CdButtonStyles.wide,
              onPressed: onOpenSettings,
              child: const Text('Open Settings'),
            ),
          if (onTypeAddress != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              style: CdButtonStyles.wide,
              onPressed: onTypeAddress,
              child: const Text('Type the address'),
            ),
          ],
        ],
      ),
    );
  }
}
