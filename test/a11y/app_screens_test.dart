import 'package:crossdrop/app/providers.dart';
import 'package:crossdrop/app/theme.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:crossdrop/core/security/secret_store.dart';
import 'package:crossdrop/core/storage/database.dart';
import 'package:crossdrop/features/history/history_screen.dart';
import 'package:crossdrop/features/home/home_screen.dart';
import 'package:crossdrop/features/receive/receive_host.dart';
import 'package:crossdrop/features/send/send_screen.dart';
import 'package:crossdrop/features/settings/settings_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final screens = <String, Widget>{
  'Home': const HomeScreen(),
  'Send': const SendScreen(),
  'Settings': const SettingsScreen(platform: DevicePlatform.ios),
  'History': const HistoryScreen(),
};

void main() {
  for (final large in [false, true]) {
    for (final brightness in Brightness.values) {
      for (final MapEntry(key: name, value: screen) in screens.entries) {
        final variant =
            '${brightness.name}${large ? ', small phone, 2x text' : ''}';
        testWidgets('$name, $variant', (tester) async {
          if (large) {
            tester.view.physicalSize = const Size(320 * 3, 568 * 3);
            tester.view.devicePixelRatio = 3;
            addTearDown(tester.view.reset);
            tester.platformDispatcher.textScaleFactorTestValue = 2;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
          }
          final db = AppDatabase(NativeDatabase.memory());
          addTearDown(db.close);
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                databaseProvider.overrideWithValue(db),
                secretStoreProvider.overrideWithValue(MemorySecretStore()),
                receiveAllowedProvider.overrideWithValue(false),
              ],
              child: MaterialApp(theme: buildTheme(brightness), home: screen),
            ),
          );
          for (var i = 0; i < 5; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 200));
          }
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantics.dispose();
          // Unmount so drift's stream timers end inside the test.
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(seconds: 1));
        });
      }
    }
  }
}
