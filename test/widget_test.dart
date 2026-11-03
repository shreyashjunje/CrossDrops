import 'package:crossdrop/app/app.dart';
import 'package:crossdrop/app/providers.dart';
import 'package:crossdrop/core/security/secret_store.dart';
import 'package:crossdrop/core/storage/database.dart';
import 'package:crossdrop/features/receive/receive_host.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home shows the receive status, the switch and Send', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          secretStoreProvider.overrideWithValue(MemorySecretStore()),
          // No real server in a widget test.
          receiveAllowedProvider.overrideWithValue(false),
        ],
        child: const CrossDropApp(),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Receiving'), findsOneWidget);
    expect(find.textContaining('as Android '), findsOneWidget);
  });
}
