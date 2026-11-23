import 'package:crossdrop/platform/usb_cable.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses attached, detached, cable and unknown events', () {
    final a = parseUsbCableEvent({
      'type': 'attached',
      'id': '/d/1',
      'name': 'iPhone',
    }) as UsbCableAttached;
    expect((a.device.id, a.device.name), ('/d/1', 'iPhone'));
    expect(
      (parseUsbCableEvent({
        'type': 'detached',
        'id': '/d/1',
      }) as UsbCableDetached).id,
      '/d/1',
    );
    final s = parseUsbCableEvent({
      'type': 'cable',
      'state': 'stopped',
      'code': 'unplugged',
    }) as UsbCableState;
    expect((s.state, s.code, s.connected), ('stopped', 'unplugged', false));
    expect(parseUsbCableEvent({'type': 'progress'}), isNull);
  });

  test('cableStart sends only ports, the id and the name', () async {
    const channel = MethodChannel('test/usb_cable');
    MethodCall? call;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
          call = c;
          return null;
        });
    await ChannelUsbCable(channel: channel).startCableBridge(
      port: 5000,
      ports: [5000, 5001],
      deviceId: 'id-1',
      name: 'Pixel',
    );
    expect(call?.method, 'cableStart');
    expect(call?.arguments, {
      'port': 5000,
      'ports': [5000, 5001],
      'id': 'id-1',
      'name': 'Pixel',
    });
  });
}
