import 'package:crossdrop/app/providers.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/storage/database.dart';
import 'package:crossdrop/core/storage/transfer_repository.dart';
import 'package:crossdrop/features/history/history_screen.dart';
import 'package:crossdrop/features/transfer/transfer_format.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('day headers', () {
    final now = DateTime(2026, 11, 3, 15);
    expect(formatDay(DateTime(2026, 11, 3, 1), now), 'Today');
    expect(formatDay(DateTime(2026, 11, 2, 23), now), 'Yesterday');
    expect(formatDay(DateTime(2026, 10, 30), now), '30 Oct 2026');
    expect(formatTime(DateTime(2026, 1, 1, 9, 5)), '09:05');
  });

  testWidgets('lists past transfers with direction, device, size, status', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = TransferRepository(db);
    await tester.runAsync(() async {
      StoredFile file(String id, FileTransferStatus st) => StoredFile(
        fileId: id,
        name: '$id.jpg',
        size: 2000000,
        kind: FileKind.photo,
        status: st,
      );
      final sent = await repo.createSession(
        sessionId: 'a',
        direction: TransferDirection.send,
        peer: const SenderInfo(id: 'i', name: "Yash's iPhone", platform: 'ios'),
        status: SessionStatus.offered,
        files: [file('f1', FileTransferStatus.saved)],
      );
      await repo.updateSession(sent, status: SessionStatus.done);
      final got = await repo.createSession(
        sessionId: 'b',
        direction: TransferDirection.receive,
        peer: const SenderInfo(id: 'j', name: 'Pixel 8', platform: 'android'),
        status: SessionStatus.offered,
        files: [
          file('f1', FileTransferStatus.failed),
          file('f2', FileTransferStatus.failed),
        ],
      );
      await repo.updateSession(
        got,
        status: SessionStatus.failed,
        reason: ErrorCodes.fileFailed,
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text("To Yash's iPhone"), findsOneWidget);
    expect(find.text('1 file · 2.0 MB · iPhone'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('From Pixel 8'), findsOneWidget);
    expect(find.text('2 files · 4.0 MB · Android phone'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    // One node per row: "Sent To Yash's iPhone ... Done".
    expect(
      find.bySemanticsLabel(RegExp(r"^Sent\s+To Yash's iPhone")),
      findsOneWidget,
    );
    semantics.dispose();

    await tester.tap(find.text('From Pixel 8'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing could be saved'), findsOneWidget);
  });

  testWidgets('empty history explains itself', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.textContaining('No transfers yet'), findsOneWidget);
  });
}
