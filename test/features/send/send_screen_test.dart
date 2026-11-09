import 'package:crossdrop/app/theme.dart';
import 'package:crossdrop/core/media/format_plan.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/features/send/send_controller.dart';
import 'package:crossdrop/features/send/send_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const SendScreen(),
        ),
      ),
    );
    return container;
  }

  testWidgets('nothing picked: the two sources, no Send button', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    expect(find.text('What do you want to send?'), findsOneWidget);
    expect(find.text('Photos & videos'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.textContaining('Send '), findsNothing);
    semantics.dispose();
  });

  testWidgets('picked: summary, grid, remove, and one Send', (tester) async {
    final semantics = tester.ensureSemantics();
    final container = await pump(tester);
    container.read(sendControllerProvider.notifier).addMedia(const [
      LibraryAsset(id: 'a', kind: FileKind.photo, originalName: 'IMG_1.HEIC'),
      LibraryAsset(id: 'b', kind: FileKind.video, originalName: 'IMG_2.MOV'),
    ]);
    await tester.pump();
    expect(find.text('1 photo, 1 video'), findsOneWidget);
    expect(find.text('Original quality'), findsOneWidget);
    expect(find.text('Send 2 items'), findsOneWidget);
    expect(
      find.text('The full size is shown when sending starts.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Add more'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove IMG_1.HEIC'));
    await tester.pump();
    expect(find.text('Send 1 item'), findsOneWidget);
    expect(find.text('1 video'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(find.text('What do you want to send?'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the Add tile offers photos or files', (tester) async {
    final semantics = tester.ensureSemantics();
    final container = await pump(tester);
    container.read(sendControllerProvider.notifier).addMedia(const [
      LibraryAsset(id: 'a', kind: FileKind.photo, originalName: 'IMG_1.HEIC'),
    ]);
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Add more'));
    await tester.pumpAndSettle();
    expect(find.text('Add more'), findsOneWidget);
    expect(find.text('Photos & videos'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    semantics.dispose();
  });
}
