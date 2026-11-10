import 'dart:async';

import 'package:crossdrop/core/usb_import/camera_roll.dart';
import 'package:crossdrop/features/usb_import/usb_import_card.dart';
import 'package:crossdrop/features/usb_import/usb_import_controller.dart';
import 'package:crossdrop/features/usb_import/usb_import_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_usb_camera.dart';

void main() {
  Widget app(FakeUsbCamera camera, Widget child, {bool available = true}) =>
      ProviderScope(
        overrides: [
          usbCameraProvider.overrideWithValue(camera),
          usbImportAvailableProvider.overrideWithValue(available),
          usbFreeBytesProvider.overrideWithValue(() async => null),
          usbKeepScreenOnProvider.overrideWithValue((_) async {}),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      );

  final objects = [
    CameraObject(
      handle: 1,
      name: 'IMG_0001.HEIC',
      folder: 9,
      size: 2000000,
      taken: DateTime(2026, 11, 3, 10),
    ),
    CameraObject(
      handle: 2,
      name: 'IMG_0002.MOV',
      folder: 9,
      size: 5000000,
      taken: DateTime(2026, 11, 2, 10),
    ),
  ];

  testWidgets('shows the iPhone as a gallery and copies what is chosen', (
    tester,
  ) async {
    final camera = FakeUsbCamera(objects: objects);
    await tester.pumpWidget(app(camera, const UsbImportScreen()));
    await tester.pumpAndSettle();

    expect(find.text('From iPhone'), findsOneWidget);
    expect(find.textContaining('3 Nov 2026'), findsOneWidget);
    expect(find.textContaining('2 Nov 2026'), findsOneWidget);
    expect(find.text('Tap photos to choose them'), findsOneWidget);
    final copy = find.widgetWithText(FilledButton, 'Copy to this phone');
    expect(tester.widget<FilledButton>(copy).onPressed, isNull);

    await tester.tap(find.byIcon(Icons.videocam));
    await tester.pump();
    expect(find.textContaining('1 selected'), findsOneWidget);
    expect(find.textContaining('5.0 MB'), findsOneWidget);

    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(camera.copied, [2]);
    expect(find.textContaining('Copied 1 file'), findsOneWidget);

    await tester.tap(find.text('Back to photos'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('copied')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('^Photo.*copied')), findsNothing);
  });

  testWidgets('while copying, shows the items and ticks the finished ones', (
    tester,
  ) async {
    final camera = FakeUsbCamera(objects: objects);
    final gate = Completer<void>();
    camera.copyGates[2] = gate;
    await tester.pumpWidget(app(camera, const UsbImportScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.image_outlined));
    await tester.tap(find.byIcon(Icons.videocam));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Copy to this phone'));
    await tester.pump();
    await tester.pump();

    // The photo (newest) is done; the video is being copied.
    expect(camera.copied, [1]);
    expect(find.text('Copying 2 of 2'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    // Big preview of the video, plus both items in the strip.
    expect(find.byIcon(Icons.videocam_outlined), findsNWidgets(2));
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('Copied 2 files'), findsOneWidget);
  });

  testWidgets('without an iPhone it explains how to connect', (tester) async {
    await tester.pumpWidget(
      app(FakeUsbCamera(attached: []), const UsbImportScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Connect the iPhone with a cable'), findsOneWidget);
    expect(find.textContaining('Keep Originals'), findsOneWidget);
  });

  group('home card', () {
    testWidgets('stands out while an iPhone is plugged in', (tester) async {
      await tester.pumpWidget(
        app(FakeUsbCamera(), UsbImportCard(onOpen: () {})),
      );
      await tester.pumpAndSettle();
      expect(find.text('iPhone connected by cable'), findsOneWidget);
      expect(find.text('Import photos'), findsOneWidget);
    });

    testWidgets('a quiet row without one', (tester) async {
      await tester.pumpWidget(
        app(FakeUsbCamera(attached: []), UsbImportCard(onOpen: () {})),
      );
      await tester.pumpAndSettle();
      expect(find.text('Import from iPhone with a cable'), findsOneWidget);
    });

    testWidgets('hidden where cable import is not offered (iPhone)', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(FakeUsbCamera(), UsbImportCard(onOpen: () {}), available: false),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNothing);
      expect(find.byType(Card), findsNothing);
    });
  });
}
