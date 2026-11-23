import 'dart:async';

import 'package:flutter/services.dart';

import '../core/cable/cable_link.dart';

/// An iPhone plugged into this phone by USB cable.
class UsbCableDevice {
  const UsbCableDevice({required this.id, required this.name});

  /// The USB device path; valid until it is unplugged.
  final String id;

  /// The product name the device gives ("iPhone").
  final String name;
}

/// What [UsbCable.events] reports.
sealed class UsbCableEvent {
  const UsbCableEvent();
}

/// An iPhone was plugged in (or was there when the app started).
class UsbCableAttached extends UsbCableEvent {
  const UsbCableAttached(this.device);
  final UsbCableDevice device;
}

class UsbCableDetached extends UsbCableEvent {
  const UsbCableDetached(this.id);
  final String id;
}

/// The send-by-cable bridge (D-073) changed state: `starting`, `waiting`
/// (CrossDrop not answering on the iPhone yet), `connected` or `stopped`.
/// A stop has a [code] (`open_failed`, `no_usbmux`, `handshake`,
/// `unplugged`) unless it was asked for. While connected, [peer] is the
/// iPhone from its hello (D-074), once it has sent one.
class UsbCableState extends UsbCableEvent {
  const UsbCableState(this.state, [this.code, this.peer]);
  final String state;
  final String? code;
  final CablePeer? peer;

  bool get connected => state == 'connected';
}

/// Error codes of [UsbCable] calls ([PlatformException.code]).
abstract final class UsbCableErrors {
  /// The user did not allow access to the device.
  static const permissionDenied = 'permission_denied';

  /// Unplugged, or the device stopped answering.
  static const disconnected = 'disconnected';
}

/// Android: an iPhone on the USB cable (android/.../UsbCableChannel.kt).
/// Plug-in events, USB access, the send-by-cable bridge (D-073) and the
/// cable test. Only ports, states and the test report cross the channel;
/// file bytes stay in Kotlin (hard rule 2).
abstract interface class UsbCable {
  /// Attach, detach and bridge events. An attached event comes for each
  /// iPhone already plugged in when a listener starts.
  Stream<UsbCableEvent> get events;

  Future<List<UsbCableDevice>> devices();

  /// Cable test: whether this phone can reach apps on the plugged-in iPhone
  /// through Apple's USB multiplexing protocol, and [port] (CrossDrop's
  /// port on the iPhone) if given. A plain-text report, one step per line,
  /// with no names or file data. The bridge pauses meanwhile.
  Future<String> probeTunnel({int? port});

  /// Starts the send-by-cable bridge to the plugged-in iPhone, or gives the
  /// running one new ports: [port] is this phone's receive port (null while
  /// it does not receive), [ports] every port the bridge may join for the
  /// iPhone (receive and data lanes). [deviceId] and [name] go into the
  /// hello. Throws [PlatformException] ([UsbCableErrors]).
  Future<void> startCableBridge({
    required int? port,
    required List<int> ports,
    required String deviceId,
    required String name,
  });

  Future<void> stopCableBridge();

  /// Android sends (D-074): joins [port] on the iPhone to [listen] on this
  /// phone's 127.0.0.1. Throws [PlatformException] (`not_connected`,
  /// `refused`).
  Future<void> dialCable({required int listen, required int port});
}

/// [UsbCable] over `crossdrop/usb_cable`.
class ChannelUsbCable implements UsbCable {
  ChannelUsbCable({MethodChannel? channel, EventChannel? eventChannel})
    : _channel = channel ?? const MethodChannel('crossdrop/usb_cable'),
      _events =
          eventChannel ?? const EventChannel('crossdrop/usb_cable/events');

  final MethodChannel _channel;
  final EventChannel _events;

  @override
  late final Stream<UsbCableEvent> events = _events
      .receiveBroadcastStream()
      .map((raw) => parseUsbCableEvent(raw as Map<Object?, Object?>))
      .where((e) => e != null)
      .cast<UsbCableEvent>();

  @override
  Future<List<UsbCableDevice>> devices() async {
    final list = await _channel.invokeListMethod<Object?>('devices') ?? [];
    return [for (final m in list) _device(m! as Map<Object?, Object?>)];
  }

  @override
  Future<String> probeTunnel({int? port}) async =>
      await _channel.invokeMethod<String>('probe', {'port': port}) ?? '';

  @override
  Future<void> startCableBridge({
    required int? port,
    required List<int> ports,
    required String deviceId,
    required String name,
  }) => _channel.invokeMethod<void>('cableStart', {
    'port': port,
    'ports': ports,
    'id': deviceId,
    'name': name,
  });

  @override
  Future<void> stopCableBridge() => _channel.invokeMethod<void>('cableStop');

  @override
  Future<void> dialCable({required int listen, required int port}) => _channel
      .invokeMethod<void>('cableDial', {'listen': listen, 'port': port});
}

UsbCableDevice _device(Map<Object?, Object?> m) =>
    UsbCableDevice(id: m['id']! as String, name: m['name'] as String? ?? '');

CablePeer? _peer(Object? raw) {
  if (raw is! Map<Object?, Object?>) return null;
  final id = raw['id'];
  final name = raw['name'];
  if (id is! String || name is! String) return null;
  return CablePeer(
    port: (raw['port'] as num?)?.toInt(),
    deviceId: id,
    name: name,
  );
}

/// Parses one event; null for an unknown type.
UsbCableEvent? parseUsbCableEvent(Map<Object?, Object?> m) =>
    switch (m['type']) {
      'attached' => UsbCableAttached(_device(m)),
      'detached' => UsbCableDetached(m['id']! as String),
      'cable' => UsbCableState(
        m['state']! as String,
        m['code'] as String?,
        _peer(m['peer']),
      ),
      _ => null,
    };

/// iOS, desktop and tests: no cable.
class NoUsbCable implements UsbCable {
  const NoUsbCable();

  @override
  Stream<UsbCableEvent> get events => const Stream.empty();

  @override
  Future<List<UsbCableDevice>> devices() async => const [];

  @override
  Future<String> probeTunnel({int? port}) async => 'Cable test needs Android.';

  @override
  Future<void> startCableBridge({
    required int? port,
    required List<int> ports,
    required String deviceId,
    required String name,
  }) async {}

  @override
  Future<void> stopCableBridge() async {}

  @override
  Future<void> dialCable({required int listen, required int port}) async =>
      throw PlatformException(code: 'not_connected');
}
