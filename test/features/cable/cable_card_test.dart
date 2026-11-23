import 'package:crossdrop/core/cable/cable_link.dart';
import 'package:crossdrop/features/cable/cable_card.dart';
import 'package:crossdrop/features/cable/cable_controllers.dart';
import 'package:crossdrop/features/receive/receive_controller.dart';
import 'package:crossdrop/features/receive/receive_host.dart';
import 'package:crossdrop/platform/usb_cable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_usb_cable.dart';

void main() {
  Widget app(FakeUsbCable cable, {bool android = true}) => ProviderScope(
    overrides: [
      usbCableProvider.overrideWithValue(cable),
      cableBridgeAvailableProvider.overrideWithValue(android),
      // No receive server: the bridge stays off, the card still shows.
      receiveStateProvider.overrideWithValue(const ReceiveState()),
    ],
    child: const MaterialApp(home: Scaffold(body: CableCard())),
  );

  testWidgets('shows while an iPhone is plugged in, then says ready', (
    tester,
  ) async {
    final cable = FakeUsbCable();
    await tester.pumpWidget(app(cable));
    await tester.pumpAndSettle();
    expect(find.text('iPhone connected by cable'), findsOneWidget);
    expect(find.textContaining('Open CrossDrop on the iPhone'), findsOneWidget);

    cable.cableState('connected');
    await tester.pumpAndSettle();
    expect(find.textContaining('Connected by cable'), findsOneWidget);
  });

  testWidgets('nothing without an iPhone, or on an iPhone', (tester) async {
    await tester.pumpWidget(app(FakeUsbCable(attached: [])));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.cable_rounded), findsNothing);

    await tester.pumpWidget(app(FakeUsbCable(), android: false));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.cable_rounded), findsNothing);
  });

  test('texts for the bridge states', () {
    expect(
      cableCardText(const UsbCableState('connected'), receivingOff: true),
      contains('Turn on Receiving'),
    );
    const iphone = CablePeer(port: 1, deviceId: 'i', name: 'iPhone');
    expect(
      cableCardText(
        const UsbCableState('connected', null, iphone),
        receivingOff: false,
      ),
      contains('both ways'),
    );
    expect(
      cableCardText(
        const UsbCableState('connected', null, iphone),
        receivingOff: true,
      ),
      contains('Ready to send'),
    );
    expect(
      cableCardText(
        const UsbCableState('stopped', UsbCableErrors.permissionDenied),
        receivingOff: false,
      ),
      contains('USB access'),
    );
    expect(
      cableCardText(
        const UsbCableState('stopped', 'handshake'),
        receivingOff: false,
      ),
      contains('did not start'),
    );
  });
}
