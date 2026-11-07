import 'dart:async';

import 'package:crossdrop/core/usb_import/camera_roll.dart';
import 'package:crossdrop/core/usb_import/import_runner.dart';
import 'package:crossdrop/features/usb_import/usb_import_controller.dart';
import 'package:crossdrop/platform/usb_camera.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_usb_camera.dart';

List<CameraObject> roll() => [
  CameraObject(
    handle: 1,
    name: 'IMG_0001.HEIC',
    folder: 9,
    size: 100,
    taken: DateTime(2026, 11, 3, 10),
  ),
  CameraObject(
    handle: 2,
    name: 'IMG_0001.MOV',
    folder: 9,
    size: 50,
    taken: DateTime(2026, 11, 3, 10),
  ),
  CameraObject(
    handle: 3,
    name: 'IMG_0002.MOV',
    folder: 9,
    size: 300,
    taken: DateTime(2026, 11, 2, 10),
  ),
  CameraObject(
    handle: 4,
    name: 'IMG_0003.PNG',
    folder: 9,
    size: 20,
    taken: DateTime(2026, 11, 1, 10),
  ),
  CameraObject(handle: 5, name: 'IMG_0003.AAE', folder: 9, size: 1),
];

void main() {
  late FakeUsbCamera camera;
  late ProviderContainer container;
  late List<bool> screenOn;
  int? free;

  ProviderContainer make() {
    screenOn = [];
    final c = ProviderContainer(
      overrides: [
        usbCameraProvider.overrideWithValue(camera),
        usbFreeBytesProvider.overrideWithValue(() async => free),
        usbKeepScreenOnProvider.overrideWithValue((on) async {
          screenOn.add(on);
        }),
      ],
    );
    c.listen(usbImportControllerProvider, (_, _) {});
    return c;
  }

  UsbImportState state() => container.read(usbImportControllerProvider);
  UsbImportController ctl() =>
      container.read(usbImportControllerProvider.notifier);

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    free = null;
    camera = FakeUsbCamera(objects: roll());
  });

  tearDown(() => container.dispose());

  test('connects to the plugged-in iPhone and reads every page', () async {
    container = make();
    await settle();
    final s = state();
    expect(s.phase, UsbImportPhase.ready);
    expect(s.device?.name, 'iPhone');
    expect(s.seen, 5);
    // Live Photo, video, screenshot; the AAE is skipped.
    expect(s.roll.items, hasLength(3));
    expect(s.roll.skipped, 1);
  });

  test(
    'without an iPhone it waits, and connects when one is plugged in',
    () async {
      camera = FakeUsbCamera(attached: [], objects: roll());
      container = make();
      await settle();
      expect(state().phase, UsbImportPhase.noDevice);
      camera.plug(FakeUsbCamera.iphone);
      await settle();
      expect(state().phase, UsbImportPhase.ready);
    },
  );

  test('a locked iPhone is tried again every 2 s', () {
    fakeAsync((fa) {
      camera.openErrors.addAll([
        UsbCameraErrors.locked,
        UsbCameraErrors.locked,
      ]);
      container = make();
      fa.flushMicrotasks();
      expect(state().phase, UsbImportPhase.locked);
      fa.elapse(const Duration(seconds: 2));
      expect(state().phase, UsbImportPhase.locked);
      fa.elapse(const Duration(seconds: 2));
      expect(state().phase, UsbImportPhase.ready);
      expect(camera.opens, 3);
    });
  });

  test('busy and denied wait for Try again', () async {
    camera.openErrors.addAll([
      UsbCameraErrors.busy,
      UsbCameraErrors.permissionDenied,
    ]);
    container = make();
    await settle();
    expect(state().phase, UsbImportPhase.busy);
    await ctl().connect();
    expect(state().phase, UsbImportPhase.permissionDenied);
    await ctl().connect();
    await settle();
    expect(state().phase, UsbImportPhase.ready);
  });

  test('unplugging while choosing goes back to "connect"', () async {
    container = make();
    await settle();
    camera.unplug(FakeUsbCamera.iphone.id);
    await settle();
    expect(state().phase, UsbImportPhase.noDevice);
  });

  test('selection: one item, a whole day, filters', () async {
    container = make();
    await settle();
    final items = state().roll.items;
    ctl().toggle(items[0].key);
    expect(state().selected, {items[0].key});
    ctl().toggleAll(items);
    expect(state().selected, hasLength(3));
    ctl().toggleAll(items);
    expect(state().selected, isEmpty);
    ctl().setFilter(RollFilter.screenshots);
    expect(state().visible.single.primary.name, 'IMG_0003.PNG');
    ctl().selectNotImported();
    expect(state().selected, {state().visible.single.key});
  });

  test(
    'copies the selection, keeps the screen on, marks items copied',
    () async {
      container = make();
      await settle();
      ctl().toggleAll(state().roll.items);
      await ctl().startImport();
      final s = state();
      expect(s.phase, UsbImportPhase.done);
      // Newest first; the Live video is left out by default.
      expect(camera.copied, [1, 3, 4]);
      expect(s.summary!.copiedFiles, 3);
      expect(s.imported, hasLength(3));
      expect(s.selected, isEmpty);
      expect(screenOn, [true, false]);
      await ctl().backToPhotos();
      expect(state().phase, UsbImportPhase.ready);
    },
  );

  test('Live Photo videos are copied when asked', () async {
    container = make();
    await settle();
    ctl().setIncludeLiveVideo(true);
    ctl().toggle(state().roll.items.first.key);
    await ctl().startImport();
    expect(camera.copied, [1, 2]);
  });

  test('not enough space: nothing is copied and the grid says why', () async {
    free = 100;
    container = make();
    await settle();
    ctl().toggleAll(state().roll.items);
    await ctl().startImport();
    final s = state();
    expect(s.phase, UsbImportPhase.ready);
    expect(s.space, isNotNull);
    expect(camera.copied, isEmpty);
    expect(s.selected, hasLength(3));
  });

  test('Stop cancels the current file on the device and ends', () async {
    final gate = Completer<void>();
    camera.copyGates[1] = gate;
    container = make();
    await settle();
    ctl().toggleAll(state().roll.items);
    final run = ctl().startImport();
    await settle();
    expect(state().phase, UsbImportPhase.importing);
    ctl().cancelImport();
    expect(camera.cancels, 1);
    camera.copyErrors[1] = UsbCameraErrors.cancelled;
    gate.complete();
    await run;
    final s = state();
    expect(s.phase, UsbImportPhase.done);
    expect(s.summary!.stop, ImportStop.cancelled);
    expect(camera.copied, isEmpty);
  });

  test('progress events move the bar of the current file', () async {
    final gate = Completer<void>();
    camera.copyGates[3] = gate;
    container = make();
    await settle();
    ctl().toggle(state().roll.items[1].key); // the 300-byte video
    final run = ctl().startImport();
    await settle();
    camera.progress(3, 150);
    await settle();
    expect(state().progress!.bytesDone, 150);
    gate.complete();
    await run;
    expect(state().progress!.bytesDone, 300);
  });

  test('leaving the screen closes the device', () async {
    container = make();
    await settle();
    container.dispose();
    container = make(); // for tearDown
    expect(camera.closes, greaterThanOrEqualTo(1));
  });
}
