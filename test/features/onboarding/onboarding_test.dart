import 'package:crossdrop/app/app.dart';
import 'package:crossdrop/app/providers.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:crossdrop/core/security/secret_store.dart';
import 'package:crossdrop/core/storage/database.dart';
import 'package:crossdrop/core/storage/settings_repository.dart';
import 'package:crossdrop/features/onboarding/onboarding_screen.dart';
import 'package:crossdrop/features/receive/receive_host.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lets the database deliver, then draws (no pumpAndSettle: spinners).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }
}

Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump(const Duration(seconds: 1));
}

Future<AppDatabase> launch(WidgetTester tester, {bool done = false}) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  if (done) {
    await tester.runAsync(() => SettingsRepository(db).setOnboardingDone(true));
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(MemorySecretStore()),
        // The gate's own logic is tested below; no real server here.
        receiveAllowedProvider.overrideWithValue(false),
      ],
      child: const CrossDropApp(),
    ),
  );
  await settle(tester);
  return db;
}

void main() {
  test('three pages; the second explains Local Network on iPhone', () {
    final ios = onboardingPages(DevicePlatform.ios);
    expect(ios, hasLength(3));
    expect(ios[0].title, 'Open CrossDrop on both phones');
    expect(ios[1].title, 'Allow Local Network');
    expect(ios[1].body.join(), contains('tap Allow'));
    expect(ios[2].body.join(), contains('hotspot mode'));
    final android = onboardingPages(DevicePlatform.android);
    expect(android[1].title, isNot(contains('Local Network')));
  });

  testWidgets('first launch: introduction, then Home', (tester) async {
    final db = await launch(tester);
    expect(find.text('Open CrossDrop on both phones'), findsOneWidget);
    expect(find.text('Send'), findsNothing);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text("If the phones don't find each other"), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
    await tester.tap(find.text('Get started'));
    await settle(tester);

    expect(find.text('Send'), findsOneWidget);
    expect(
      await tester.runAsync(
        () => SettingsRepository(db).watchOnboardingDone().first,
      ),
      isTrue,
    );
    await finish(tester);
  });

  testWidgets('Skip goes straight to Home', (tester) async {
    await launch(tester);
    await tester.tap(find.text('Skip'));
    await settle(tester);
    expect(find.text('Send'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('later launches skip the introduction', (tester) async {
    await launch(tester, done: true);
    expect(find.text('Open CrossDrop on both phones'), findsNothing);
    expect(find.text('Send'), findsOneWidget);
    await finish(tester);
  });

  test('receiving waits for the introduction (D-050)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(receiveAllowedProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(onboardingDoneProvider.future);
    expect(container.read(receiveAllowedProvider), isFalse);
    await SettingsRepository(db).setOnboardingDone(true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(receiveAllowedProvider), isTrue);
  });

  testWidgets('large text, small phone, dark: pages scroll, no overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320 * 3, 568 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const OnboardingScreen(platform: DevicePlatform.ios),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Next'), findsOneWidget);
  });
}
