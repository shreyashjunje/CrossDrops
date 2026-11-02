import 'package:crossdrop/app/app.dart';
import 'package:crossdrop/app/providers.dart';
import 'package:crossdrop/core/security/secret_store.dart';
import 'package:crossdrop/core/storage/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home shows the device name, Receive and Send', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          secretStoreProvider.overrideWithValue(MemorySecretStore()),
        ],
        child: const CrossDropApp(),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text('Receive'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.textContaining('This phone: Android '), findsOneWidget);
  });
}
