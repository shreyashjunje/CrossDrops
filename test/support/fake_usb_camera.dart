import 'dart:async';

import 'package:crossdrop/core/media/save_target.dart';
import 'package:crossdrop/core/usb_import/camera_roll.dart';
import 'package:crossdrop/platform/usb_camera.dart';
import 'package:flutter/services.dart';

/// An iPhone on a cable, in memory.
class FakeUsbCamera implements UsbCamera {
  FakeUsbCamera({
    List<UsbCameraDevice>? attached,
    List<CameraObject>? objects,
    this.pageSize = 2,
  }) : attached = attached ?? [iphone],
       objects = objects ?? [];

  static const iphone = UsbCameraDevice(
    id: '/dev/bus/usb/001/002',
    name: 'iPhone',
  );

  final List<UsbCameraDevice> attached;
  final List<CameraObject> objects;
  final int pageSize;
  final _events = StreamController<UsbCameraEvent>.broadcast();

  /// Codes `open` throws, one per call, before it succeeds.
  final List<String> openErrors = [];

  /// Handles whose copy fails with the code given.
  final Map<int, String> copyErrors = {};

  /// Completes a copy only when the test says so (handle -> gate).
  final Map<int, Completer<void>> copyGates = {};

  final List<int> copied = [];
  int opens = 0;
  int closes = 0;
  int cancels = 0;
  int _cursor = 0;

  void plug(UsbCameraDevice d) {
    attached.add(d);
    _events.add(UsbCameraAttached(d));
  }

  void unplug(String id) {
    attached.removeWhere((d) => d.id == id);
    _events.add(UsbCameraDetached(id));
  }

  void progress(int handle, int bytes) =>
      _events.add(UsbCopyProgress(handle, bytes));

  @override
  Stream<UsbCameraEvent> get events => _events.stream;

  @override
  Future<List<UsbCameraDevice>> devices() async => List.of(attached);

  @override
  Future<void> open(String id) async {
    opens++;
    if (openErrors.isNotEmpty) {
      throw PlatformException(code: openErrors.removeAt(0));
    }
    if (!attached.any((d) => d.id == id)) {
      throw PlatformException(code: UsbCameraErrors.disconnected);
    }
    _cursor = 0;
  }

  @override
  Future<CameraPage> nextPage({int max = 500}) async {
    final n = max < pageSize ? max : pageSize;
    final end = (_cursor + n).clamp(0, objects.length);
    final page = objects.sublist(_cursor, end);
    _cursor = end;
    return CameraPage(
      objects: page,
      done: _cursor >= objects.length,
      seen: _cursor,
    );
  }

  @override
  Future<String?> thumbnail(int handle) async => null;

  @override
  Future<ImportedFile> importFile({
    required int handle,
    required String safeName,
    required String mime,
    required SaveCollection collection,
    required int? expectedSize,
    DateTime? taken,
  }) async {
    final gate = copyGates[handle];
    if (gate != null) await gate.future;
    final error = copyErrors[handle];
    if (error != null) throw PlatformException(code: error);
    copied.add(handle);
    return ImportedFile(
      uri: 'content://media/external/images/media/$handle',
      collection: collection,
      bytes: expectedSize ?? 0,
    );
  }

  @override
  Future<void> cancelCurrent() async => cancels++;

  @override
  Future<void> close() async => closes++;
}
