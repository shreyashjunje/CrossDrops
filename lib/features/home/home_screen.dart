import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
import '../../core/storage/transfer_repository.dart';
import '../history/history_screen.dart';
import '../history/transfer_row.dart';
import '../receive/my_qr_screen.dart';
import '../receive/receive_host.dart';
import '../send/send_controller.dart';
import '../send/send_screen.dart';
import '../transfer/transfer_screen.dart';
import '../transfer/unfinished_transfers.dart';
import '../usb_import/usb_import_card.dart';
import '../usb_import/usb_import_screen.dart';
import 'active_transfers.dart';
import 'receive_status_card.dart';

/// The three newest transfers for Home. Re-read when a transfer ends.
final recentTransfersProvider = FutureProvider.autoDispose<List<StoredSession>>(
  (ref) => ref.watch(transferRepositoryProvider).recent(limit: 3),
);

/// "Ready to receive" with this phone's name and the Receiving switch, one
/// large Send action, what is running or unfinished, and the latest
/// transfers (D-069).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.onSeeAll});

  /// Opens the History tab. Null: no "See all" link.
  final VoidCallback? onSeeAll;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Unfinished transfers already resumed or discarded from Home.
  final _handled = <String>{};

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    // Creates the key pair and certificate on first launch, before the
    // user needs them (ARCHITECTURE.md, "Device identity").
    ref.watch(credentialsProvider);
    // A transfer that ends belongs in Recent.
    ref.listen(sendControllerProvider.select((s) => s.isRunning), (was, now) {
      if (was == true && !now) ref.invalidate(recentTransfersProvider);
    });
    ref.listen(
      receiveStateProvider.select(
        (s) => s.sessions.values.where((x) => x.isActive).length,
      ),
      (was, now) {
        if ((was ?? 0) > now) ref.invalidate(recentTransfersProvider);
      },
    );

    final unfinished = [
      for (final s
          in ref.watch(unfinishedTransfersProvider).value ??
              const <StoredSession>[])
        if (!_handled.contains(s.sessionId)) s,
    ];
    final recent = ref.watch(recentTransfersProvider).value;
    final anythingRunning =
        ref.watch(sendControllerProvider.select((s) => s.isRunning)) ||
        ref.watch(
          receiveStateProvider.select(
            (s) => s.sessions.values.any((x) => x.isActive),
          ),
        );

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            CdSpace.gutter,
            8,
            CdSpace.gutter,
            CdSpace.l,
          ),
          children: [
            const _Wordmark(),
            const SizedBox(height: 16),
            const ReceiveStatusCard(),
            const SizedBox(height: 16),
            _SendHero(
              onPressed: () =>
                  pushScreen<void>(context, Routes.send, const SendScreen()),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: CdButtonStyles.wide,
              onPressed: () =>
                  pushScreen<void>(context, Routes.myQr, const MyQrScreen()),
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('Show my QR code'),
            ),
            ActiveTransfers(
              onOpen: (id) => pushScreen<void>(
                context,
                Routes.transfer,
                TransferScreen(receiveSessionId: id),
              ),
            ),
            for (final s in unfinished) ...[
              const SizedBox(height: 12),
              UnfinishedCard(
                session: s,
                onDone: () => setState(() => _handled.add(s.sessionId)),
              ),
            ],
            UsbImportCard(
              onOpen: () => pushScreen<void>(
                context,
                Routes.usbImport,
                const UsbImportScreen(),
              ),
            ),
            if (recent != null && recent.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Recent',
                        style: CdType.h3.copyWith(color: c.text),
                      ),
                    ),
                  ),
                  if (widget.onSeeAll != null)
                    TextButton(
                      onPressed: widget.onSeeAll,
                      child: const Text('See all'),
                    ),
                ],
              ),
              for (final s in recent) ...[
                TransferRow(
                  session: s,
                  onTap: () => pushScreen<void>(
                    context,
                    Routes.history,
                    HistoryDetailScreen(session: s),
                  ),
                ),
                Divider(color: c.line),
              ],
            ] else if (recent != null && !anythingRunning && unfinished.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: EmptyState(
                  title: 'Nothing sent yet',
                  text:
                      'Tap Send, pick photos, then tap the other phone. '
                      'That’s it.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return Semantics(
      header: true,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.swap_horiz_rounded,
                  size: 20,
                  color: c.onAccent,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'CrossDrop',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CdType.h3.copyWith(color: c.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one loud thing on Home: a lime tile with "Send".
class _SendHero extends StatelessWidget {
  const _SendHero({required this.onPressed});

  final VoidCallback onPressed;

  /// Dark olive on lime: 10:1.
  static const _sub = Color(0xFF2C3410);

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return Semantics(
      button: true,
      label: 'Send photos, videos or files',
      excludeSemantics: true,
      child: Material(
        color: c.accent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CdRadius.dialog),
          side: BorderSide(color: c.accentPressed),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          highlightColor: c.accentPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 184),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 132,
                        height: 40,
                        child: CustomPaint(painter: _PhonesPainter(c.onAccent)),
                      ),
                      const Spacer(),
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: c.onAccent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.north_east_rounded, color: c.accent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text('Send', style: CdType.hero.copyWith(color: c.onAccent)),
                  const SizedBox(height: 2),
                  Text(
                    'Photos, videos or files',
                    style: CdType.titleS.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: _sub,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// iPhone · · · · Android, in the Send tile.
class _PhonesPainter extends CustomPainter {
  _PhonesPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromLTRBR(2, 4, 20, 36, const Radius.circular(5)),
      p,
    );
    canvas.drawLine(const Offset(8.5, 9), const Offset(13.5, 9), p);
    canvas.drawRRect(
      RRect.fromLTRBR(112, 4, 130, 36, const Radius.circular(2.5)),
      p,
    );
    canvas.drawCircle(const Offset(121, 9.5), 1.2, Paint()..color = color);
    final dot = Paint()
      ..color = color
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    for (var x = 30.0; x <= 102; x += 8) {
      canvas.drawLine(Offset(x, 20), Offset(x + 0.5, 20), dot);
    }
  }

  @override
  bool shouldRepaint(_PhonesPainter old) => old.color != color;
}
