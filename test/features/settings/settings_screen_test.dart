import 'package:crossdrop/app/providers.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:crossdrop/core/security/secret_store.dart';
import 'package:crossdrop/core/storage/database.dart';
import 'package:crossdrop/core/storage/settings_repository.dart';
import 'package:crossdrop/core/storage/trust_repository.dart';
import 'package:crossdrop/features/settings/settings_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppDatabase> pump(
  WidgetTester tester,
  DevicePlatform platform, {
  Future<void> Function(AppDatabase db)? seed,
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  // Before any widget queries: drift's lock is held by queries started in
  // the test's fake-async zone.
  if (seed != null) await tester.runAsync(() => seed(db));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(MemorySecretStore()),
      ],
      child: MaterialApp(home: SettingsScreen(platform: platform)),
    ),
  );
  await settle(tester);
  return db;
}

/// Lets the database deliver (real async), then draws, without waiting
/// for spinners to stop.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Unmounts, so drift's stream timers end inside the test.
Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('iPhone: name, receiving, HEIC and Live Photo options', (
    tester,
  ) async {
    final db = await pump(tester, DevicePlatform.ios);
    expect(find.text('Device name'), findsOneWidget);
    expect(
      find.text('Ready to receive when CrossDrop is open'),
      findsOneWidget,
    );
    expect(find.text('Convert HEIC to JPEG'), findsOneWidget);
    expect(find.text('Send Live Photo videos'), findsOneWidget);

    await tester.tap(find.text('Convert HEIC to JPEG'));
    await settle(tester);
    final settings = await tester.runAsync(
      () => SettingsRepository(db).formatSettings(),
    );
    expect(settings!.convertHeicToJpeg, isTrue);
    expect(settings.sendLivePhotoVideo, isFalse);
    await finish(tester);
  });

  testWidgets('Android: no photo format options', (tester) async {
    await pump(tester, DevicePlatform.android);
    expect(find.text('Convert HEIC to JPEG'), findsNothing);
    await finish(tester);
  });

  testWidgets('receiving off is saved', (tester) async {
    final db = await pump(tester, DevicePlatform.android);
    await tester.tap(find.text('Ready to receive when CrossDrop is open'));
    await settle(tester);
    expect(
      await tester.runAsync(() => SettingsRepository(db).receivingEnabled()),
      isFalse,
    );
    await finish(tester);
  });

  testWidgets('trusted devices: listed, and Forget removes one', (
    tester,
  ) async {
    await pump(
      tester,
      DevicePlatform.android,
      seed: (db) => TrustRepository(db).trust(
        fingerprint: 'ab' * 32,
        deviceId: 'id',
        name: "Yash's iPhone",
        platform: 'ios',
      ),
    );
    expect(find.text('1 device'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Trusted devices'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Trusted devices'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Trusted devices'));
    await settle(tester);
    expect(find.text("Yash's iPhone"), findsOneWidget);
    expect(find.text('Accept without asking'), findsOneWidget);
    await tester.tap(find.byTooltip("Forget Yash's iPhone"));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Forget'));
    await settle(tester);
    expect(find.textContaining('None yet'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('About shows the version and the security key', (tester) async {
    await pump(tester, DevicePlatform.android);
    await tester.scrollUntilVisible(
      find.text('About CrossDrop'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('About CrossDrop'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('About CrossDrop'));
    await settle(tester);
    expect(find.textContaining('Version '), findsOneWidget);
    expect(find.text('Private by design'), findsOneWidget);
    await finish(tester);
  });
}
