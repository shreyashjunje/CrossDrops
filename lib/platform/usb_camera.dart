import 'dart:async';

import 'package:flutter/services.dart';

import '../core/media/save_target.dart';
import '../core/usb_import/camera_roll.dart';

/// A phone connected by cable that shows its photos as a camera (PTP).
class UsbCameraDevice {
  const UsbCameraDevice({required this.id, required this.name});

  /// The USB device path; valid until it is unplugged.
  final String id;

  /// The product name the device gives ("iPhone").
  final String name;
}

/// What [UsbCamera.events] reports.
sealed class UsbCameraEvent {
  const UsbCameraEvent();
}

/// A device was plugged in (or was there when the app started).
class UsbCameraAttached extends UsbCameraEvent {
  const UsbCameraAttached(this.device);
  final UsbCameraDevice device;
}

class UsbCameraDetached extends UsbCameraEvent {
  const UsbCameraDetached(this.id);
  final String id;
}

/// Bytes of the file being copied that are on disk so far.
class UsbCopyProgress extends UsbCameraEvent {
  const UsbCopyProgress(this.handle, this.bytes);
  final int handle;
  final int bytes;
}

/// Error codes of [UsbCamera] calls ([PlatformException.code]).
abstract final class UsbCameraErrors {
  /// The user did not allow access to the device.
  static const permissionDenied = 'permission_denied';

  /// Another app (often Files) holds the device's camera interface.
  static const busy = 'busy';

  /// The device shows no storage: an iPhone that is locked, or where
  /// "Trust This Computer" was not answered yet.
  static const locked = 'locked';

  /// Unplugged, or the device stopped answering.
  static const disconnected = 'disconnected';

  /// The device sent a different number of bytes than it declared. The
  /// partial item was deleted.
  static const sizeMismatch = 'size_mismatch';

  /// [UsbCamera.cancelCurrent] stopped the copy. The partial item was
  /// deleted.
  static const cancelled = 'cancelled';

  static const noSpace = 'no_space';
  static const io = 'io';
}

/// One page of the device's file list.
class CameraPage {
  const CameraPage({
    required this.objects,
    required this.done,
    required this.seen,
  });

  final List<CameraObject> objects;

  /// True when the whole list has been read.
  final bool done;

  /// Files read so far, folders not counted.
  final int seen;
}

/// A copied file in the gallery.
class ImportedFile {
  const ImportedFile({
    required this.uri,
    required this.collection,
    required this.bytes,
  });

  /// The MediaStore item.
  final String uri;

  /// Where it went: the gallery, or Downloads when the gallery refused the
  /// format.
  final SaveCollection collection;
  final int bytes;
}

/// Android: reads photos from a phone connected by cable (D-067), through
/// android.mtp.MtpDevice (android/.../UsbCameraChannel.kt).
///
/// Only paths, handles and URIs cross the channel; thumbnails go to
/// cache files and copies straight into MediaStore (hard rule 2).
abstract interface class UsbCamera {
  /// Attach and detach events, and copy progress. An attached event comes
  /// for each device already plugged in when a listener starts.
  Stream<UsbCameraEvent> get events;

  Future<List<UsbCameraDevice>> devices();

  /// Asks for USB access if needed, then opens the device. Throws
  /// [PlatformException] with a [UsbCameraErrors] code.
  Future<void> open(String id);

  /// The next page of up to [max] files. Starts over after [open].
  Future<CameraPage> nextPage({int max = 500});

  /// A JPEG preview in a cache file, or null if the device has none.
  Future<String?> thumbnail(int handle);

  /// Copies one file into a pending MediaStore item in [collection], checks
  /// its size against [expectedSize] (when known) and publishes it.
  Future<ImportedFile> importFile({
    required int handle,
    required String safeName,
    required String mime,
    required SaveCollection collection,
    required int? expectedSize,
    DateTime? taken,
  });

  /// Stops the copy in progress within about one 1 MB part.
  Future<void> cancelCurrent();

  /// Closes the device and deletes the thumbnail cache.
  Future<void> close();
}

/// [UsbCamera] over `crossdrop/usb_camera`.
class ChannelUsbCamera implements UsbCamera {
  ChannelUsbCamera({MethodChannel? channel, EventChannel? eventChannel})
    : _channel = channel ?? const MethodChannel('crossdrop/usb_camera'),
      _events =
          eventChannel ?? const EventChannel('crossdrop/usb_camera/events');

  final MethodChannel _channel;
  final EventChannel _events;

  @override
  late final Stream<UsbCameraEvent> events = _events
      .receiveBroadcastStream()
      .map((raw) => parseUsbCameraEvent(raw as Map<Object?, Object?>))
      .where((e) => e != null)
      .cast<UsbCameraEvent>();

  @override
  Future<List<UsbCameraDevice>> devices() async {
    final list = await _channel.invokeListMethod<Object?>('devices') ?? [];
    return [for (final m in list) _device(m! as Map<Object?, Object?>)];
  }

  @override
  Future<void> open(String id) =>
      _channel.invokeMethod<void>('open', {'id': id});

  @override
  Future<CameraPage> nextPage({int max = 500}) async {
    final m = (await _channel.invokeMapMethod<String, Object?>('nextPage', {
      'max': max,
    }))!;
    return parseCameraPage(m);
  }

  @override
  Future<String?> thumbnail(int handle) =>
      _channel.invokeMethod<String>('thumbnail', {'handle': handle});

  @override
  Future<ImportedFile> importFile({
    required int handle,
    required String safeName,
    required String mime,
    required SaveCollection collection,
    required int? expectedSize,
    DateTime? taken,
  }) async {
    final m = (await _channel.invokeMapMethod<String, Object?>('importFile', {
      'handle': handle,
      'name': safeName,
      'mime': mime,
      'collection': collection.name,
      'expectedSize': expectedSize,
      'takenMs': taken?.millisecondsSinceEpoch,
    }))!;
    return ImportedFile(
      uri: m['uri']! as String,
      collection: SaveCollection.values.byName(m['collection']! as String),
      bytes: (m['bytes']! as num).toInt(),
    );
  }

  @override
  Future<void> cancelCurrent() => _channel.invokeMethod<void>('cancelCurrent');

  @override
  Future<void> close() => _channel.invokeMethod<void>('close');
}

UsbCameraDevice _device(Map<Object?, Object?> m) =>
    UsbCameraDevice(id: m['id']! as String, name: m['name'] as String? ?? '');

/// Parses one event; null for an unknown type.
UsbCameraEvent? parseUsbCameraEvent(Map<Object?, Object?> m) =>
    switch (m['type']) {
      'attached' => UsbCameraAttached(_device(m)),
      'detached' => UsbCameraDetached(m['id']! as String),
      'progress' => UsbCopyProgress(
        (m['handle']! as num).toInt(),
        (m['bytes']! as num).toInt(),
      ),
      _ => null,
    };

/// Parses a `nextPage` answer. Sizes of -1 are unknown; times of 0 or less
/// are missing.
CameraPage parseCameraPage(Map<String, Object?> m) {
  final raw = m['objects'] as List<Object?>? ?? const [];
  return CameraPage(
    objects: [
      for (final o in raw.cast<Map<Object?, Object?>>())
        CameraObject(
          handle: (o['handle']! as num).toInt(),
          name: o['name']! as String,
          folder: (o['folder'] as num?)?.toInt() ?? 0,
          size: switch ((o['size'] as num?)?.toInt()) {
            final s? when s >= 0 => s,
            _ => null,
          },
          taken: switch ((o['takenMs'] as num?)?.toInt()) {
            final t? when t > 0 => DateTime.fromMillisecondsSinceEpoch(t),
            _ => null,
          },
        ),
    ],
    done: m['done'] as bool? ?? true,
    seen: (m['seen'] as num?)?.toInt() ?? raw.length,
  );
}

/// Desktop, iOS and tests: no devices.
class NoUsbCamera implements UsbCamera {
  const NoUsbCamera();

  @override
  Stream<UsbCameraEvent> get events => const Stream.empty();

  @override
  Future<List<UsbCameraDevice>> devices() async => const [];

  @override
  Future<void> open(String id) async =>
      throw PlatformException(code: UsbCameraErrors.disconnected);

  @override
  Future<CameraPage> nextPage({int max = 500}) async =>
      const CameraPage(objects: [], done: true, seen: 0);

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
  }) async => throw PlatformException(code: UsbCameraErrors.disconnected);

  @override
  Future<void> cancelCurrent() async {}

  @override
  Future<void> close() async {}
}
