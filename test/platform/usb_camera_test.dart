import 'package:crossdrop/core/media/save_target.dart';
import 'package:crossdrop/platform/usb_camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseCameraPage', () {
    test('reads objects; -1 size and 0 time are unknown', () {
      final page = parseCameraPage({
        'objects': [
          {
            'handle': 7,
            'name': 'IMG_0001.HEIC',
            'folder': 3,
            'size': 2048,
            'takenMs': 1762160400000,
          },
          {'handle': 8, 'name': 'IMG_0002.MOV', 'size': -1, 'takenMs': 0},
        ],
        'done': false,
        'seen': 2,
      });
      expect(page.done, isFalse);
      expect(page.seen, 2);
      final a = page.objects[0];
      expect(a.handle, 7);
      expect(a.folder, 3);
      expect(a.size, 2048);
      expect(a.taken, DateTime.fromMillisecondsSinceEpoch(1762160400000));
      final b = page.objects[1];
      expect(b.folder, 0);
      expect(b.size, isNull);
      expect(b.taken, isNull);
    });
  });

  group('parseUsbCameraEvent', () {
    test('attached, detached, progress, unknown', () {
      final a = parseUsbCameraEvent({
        'type': 'attached',
        'id': '/dev/bus/usb/001/002',
        'name': 'iPhone',
      });
      expect(a, isA<UsbCameraAttached>());
      expect((a! as UsbCameraAttached).device.name, 'iPhone');
      expect(
        parseUsbCameraEvent({'type': 'detached', 'id': 'x'}),
        isA<UsbCameraDetached>(),
      );
      final p = parseUsbCameraEvent({
        'type': 'progress',
        'handle': 5,
        'bytes': 1 << 33,
      });
      expect((p! as UsbCopyProgress).bytes, 1 << 33);
      expect(parseUsbCameraEvent({'type': 'later'}), isNull);
    });
  });

  test('importFile sends only names, handles and sizes', () async {
    const channel = MethodChannel('test/usb_camera');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return {
            'uri': 'content://media/external/images/media/9',
            'collection': 'photos',
            'bytes': 2048,
          };
        });
    final cam = ChannelUsbCamera(channel: channel);
    final r = await cam.importFile(
      handle: 7,
      safeName: 'IMG_0001.HEIC',
      mime: 'image/heic',
      collection: SaveCollection.photos,
      expectedSize: 2048,
      taken: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    expect(r.collection, SaveCollection.photos);
    expect(r.bytes, 2048);
    expect(calls.single.method, 'importFile');
    expect(calls.single.arguments, {
      'handle': 7,
      'name': 'IMG_0001.HEIC',
      'mime': 'image/heic',
      'collection': 'photos',
      'expectedSize': 2048,
      'takenMs': 1000,
    });
  });
}
