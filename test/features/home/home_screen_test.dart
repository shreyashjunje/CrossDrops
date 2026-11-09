import 'package:crossdrop/app/app.dart';
import 'package:crossdrop/app/providers.dart';
import 'package:crossdrop/core/security/secret_store.dart';
import 'package:crossdrop/core/storage/database.dart';
import 'package:crossdrop/core/storage/settings_repository.dart';
import 'package:crossdrop/features/home/receive_status_card.dart';
import 'package:crossdrop/features/receive/receive_controller.dart';
import 'package:crossdrop/features/receive/receive_host.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('receive status', () {
    test('ready names the phone and pulses', () {
      final s = ReceiveStatusCard.statusOf(
        const ReceiveState(port: 1, qrPayload: 'q', advertising: true),
        'Sam',
      );
      expect(s.title, 'Ready to receive');
      expect(s.lead, 'Phones on this Wi-Fi see you as');
      expect(s.showName, isTrue);
      expect(s.tone, ReceiveTone.ready);
      expect(s.detail, isNull);
    });

    test('ready but not yet advertised says the QR already works', () {
      final s = ReceiveStatusCard.statusOf(
        const ReceiveState(port: 1, qrPayload: 'q'),
        'Sam',
      );
      expect(s.detail, contains('QR code works'));
    });

    test('off is plain about the consequence', () {
      final s = ReceiveStatusCard.statusOf(
        const ReceiveState(receivingOff: true),
        'Sam',
      );
      expect(s.title, 'Receiving is off');
      expect(s.tone, ReceiveTone.waiting);
    });

    test('no Wi-Fi is a warning with the fix', () {
      final s = ReceiveStatusCard.statusOf(const ReceiveState(port: 1), 'Sam');
      expect(s.title, 'Not on Wi-Fi');
      expect(s.tone, ReceiveTone.warning);
      expect(s.showName, isFalse);
    });

    test('an error wins', () {
      final s = ReceiveStatusCard.statusOf(
        const ReceiveState(error: 'Port in use', receivingOff: true),
        'Sam',
      );
      expect(s.title, 'Cannot receive');
      expect(s.tone, ReceiveTone.error);
    });
  });

  testWidgets('tabs switch, and Back returns to Home', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() => SettingsRepository(db).setOnboardingDone(true));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          secretStoreProvider.overrideWithValue(MemorySecretStore()),
          receiveAllowedProvider.overrideWithValue(false),
        ],
        child: const CrossDropApp(),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    await settle();
    expect(find.text('Send'), findsOneWidget);
    // A new phone: nothing sent yet.
    expect(find.text('Nothing sent yet'), findsOneWidget);

    await tester.tap(find.text('History'));
    await settle();
    expect(find.text('Send'), findsNothing);
    expect(find.text('No transfers yet'), findsOneWidget);

    // System Back on a tab other than Home goes to Home, not out of the app.
    await tester.binding.handlePopRoute();
    await settle();
    expect(find.text('Send'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(seconds: 1));
  });
}
