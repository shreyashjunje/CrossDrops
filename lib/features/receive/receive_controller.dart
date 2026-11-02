import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/app_dirs.dart';
import '../../app/providers.dart';
import '../../core/discovery/discovery_service.dart';
import '../../core/discovery/network_monitor.dart';
import '../../core/discovery/txt_record.dart';
import '../../core/engine/speed_meter.dart';
import '../../core/log.dart';
import '../../core/protocol/connect_payload.dart';
import '../../core/protocol/models.dart';
import '../../core/security/device_identity.dart';
import '../../core/security/ephemeral_identity.dart';
import '../../core/server/receive_server.dart';

class IncomingFile {
  const IncomingFile({
    required this.name,
    required this.size,
    this.receivedBytes = 0,
    this.bytesPerSecond = 0,
    this.savedPath,
    this.error,
  });

  final String name;
  final int size;
  final int receivedBytes;
  final double bytesPerSecond;
  final String? savedPath;
  final String? error;

  IncomingFile copyWith({
    int? receivedBytes,
    double? bytesPerSecond,
    String? savedPath,
    String? error,
  }) => IncomingFile(
    name: name,
    size: size,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
    savedPath: savedPath ?? this.savedPath,
    error: error ?? this.error,
  );
}

class ReceiveState {
  const ReceiveState({
    this.port,
    this.deviceName,
    this.addresses = const [],
    this.qrPayload,
    this.advertising = false,
    this.advertiseError,
    this.saveDir,
    this.files = const {},
    this.error,
  });

  /// Null while the server is starting.
  final int? port;
  final String? deviceName;

  /// Addresses other phones may reach (no mobile data or VPN).
  final List<LocalAddress> addresses;

  /// `crossdrop://connect?...` for the QR code; null without a reachable
  /// address. Never log it (CLAUDE.md hard rule 7).
  final String? qrPayload;
  final bool advertising;

  /// Discovery could not start; the QR code still works.
  final String? advertiseError;
  final String? saveDir;

  /// Keyed by "sessionId/fileId", newest last.
  final Map<String, IncomingFile> files;
  final String? error;

  ReceiveState copyWith({
    int? port,
    String? deviceName,
    List<LocalAddress>? addresses,
    String? Function()? qrPayload,
    bool? advertising,
    String? Function()? advertiseError,
    String? saveDir,
    Map<String, IncomingFile>? files,
    String? error,
  }) => ReceiveState(
    port: port ?? this.port,
    deviceName: deviceName ?? this.deviceName,
    addresses: addresses ?? this.addresses,
    qrPayload: qrPayload != null ? qrPayload() : this.qrPayload,
    advertising: advertising ?? this.advertising,
    advertiseError: advertiseError != null
        ? advertiseError()
        : this.advertiseError,
    saveDir: saveDir ?? this.saveDir,
    files: files ?? this.files,
    error: error ?? this.error,
  );
}

final receiveControllerProvider =
    NotifierProvider.autoDispose<ReceiveController, ReceiveState>(
      ReceiveController.new,
    );

/// Runs the receive server while the Receive screen is open, advertises it
/// on the local network and keeps the QR code current when the network
/// changes.
class ReceiveController extends Notifier<ReceiveState> {
  ReceiveServer? _server;
  StreamSubscription<ReceiveEvent>? _sub;
  Advertiser? _advertiser;
  NetworkMonitor? _monitor;
  StreamSubscription<List<LocalAddress>>? _networkSub;
  AppLifecycleListener? _lifecycle;
  ConnectPayload Function(LocalAddress)? _payloadFor;
  final Map<String, SpeedMeter> _meters = {};
  DateTime _lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  ReceiveState build() {
    ref.onDispose(_stop);
    unawaited(_start());
    return const ReceiveState();
  }

  Future<void> _start() async {
    try {
      final dirs = await AppDirs.resolve();
      final device = await ref.read(identityProvider.future);
      final identity = await EphemeralIdentity.generate();
      final server = await ReceiveServer.start(
        info: DeviceInfo(
          id: device.deviceId,
          name: device.deviceName,
          platform: DevicePlatform.current.name,
        ),
        securityContext: identity.serverContext(),
        tempDir: dirs.incomingTemp,
        saveDir: dirs.received,
      );
      if (!ref.mounted) {
        await server.close();
        return;
      }
      _server = server;
      _sub = server.events.listen(_onEvent);
      await WakelockPlus.enable();

      _payloadFor = (a) => ConnectPayload(
        ip: a.ip,
        port: server.port,
        fingerprint: identity.fingerprint,
        deviceId: device.deviceId,
        name: device.deviceName,
      );
      final monitor = _monitor = NetworkMonitor(
        connectivityEvents: ref.read(connectivityEventsProvider),
      );
      await monitor.start();
      if (!ref.mounted) return;
      _networkSub = monitor.changes.listen(_onNetworkChanged);
      _lifecycle = AppLifecycleListener(onResume: _onResume);
      state = state.copyWith(
        port: server.port,
        deviceName: device.deviceName,
        saveDir: dirs.received,
      );
      _showAddresses(monitor.current);

      final advertiser = _advertiser = Advertiser(
        ref.read(mdnsBackendProvider),
      );
      try {
        await advertiser.start(
          txt: TxtRecord.forDevice(
            identity: device,
            platform: DevicePlatform.current,
            fingerprint: identity.fingerprint,
          ),
          port: server.port,
        );
        if (ref.mounted) state = state.copyWith(advertising: true);
      } catch (e) {
        logEvent('discovery', 'advertising failed: ${e.runtimeType}');
        if (ref.mounted) {
          state = state.copyWith(
            advertiseError: () =>
                'Nearby discovery is not available. The QR code still works.',
          );
        }
      }
    } catch (e) {
      if (ref.mounted) state = state.copyWith(error: 'Could not start: $e');
    }
  }

  Future<void> _stop() async {
    _lifecycle?.dispose();
    await _networkSub?.cancel();
    await _monitor?.dispose();
    await _advertiser?.stop();
    await _sub?.cancel();
    await _server?.close();
    await WakelockPlus.disable();
  }

  void _showAddresses(List<LocalAddress> addresses) {
    final qr = pickQrAddress(addresses);
    state = state.copyWith(
      addresses: addresses,
      qrPayload: () => qr == null ? null : _payloadFor!(qr).toUri(),
    );
  }

  /// Wi-Fi or IP changed: register again so peers learn the new address,
  /// and redraw the QR code.
  Future<void> _onNetworkChanged(List<LocalAddress> addresses) async {
    if (!ref.mounted) return;
    _showAddresses(addresses);
    await _restartAdvertising();
  }

  /// iOS pauses the app when the screen locks; the network may have
  /// changed meanwhile.
  Future<void> _onResume() async {
    if (!ref.mounted) return;
    _showAddresses(reachableAddresses(await listLocalAddresses()));
    await _restartAdvertising();
  }

  Future<void> _restartAdvertising() async {
    try {
      await _advertiser?.restart();
    } catch (e) {
      logEvent('discovery', 'advertising restart failed: ${e.runtimeType}');
    }
  }

  void _onEvent(ReceiveEvent e) {
    final files = Map.of(state.files);
    switch (e) {
      case SessionStarted(:final sessionId, files: final offers):
        for (final f in offers) {
          files['$sessionId/${f.fileId}'] = IncomingFile(
            name: f.name,
            size: f.size,
          );
        }
      case FileProgress(:final sessionId, :final fileId, :final receivedBytes):
        final key = '$sessionId/$fileId';
        final meter = _meters.putIfAbsent(key, SpeedMeter.new)
          ..add(receivedBytes);
        final current = files[key];
        if (current == null) return;
        // Limit rebuilds to about 10 per second; later events carry the
        // newer count anyway.
        final now = DateTime.now();
        final last = receivedBytes == current.size;
        if (!last && now.difference(_lastUiUpdate).inMilliseconds < 100) {
          return;
        }
        _lastUiUpdate = now;
        files[key] = current.copyWith(
          receivedBytes: receivedBytes,
          bytesPerSecond: meter.bytesPerSecond,
        );
      case FileSaved(:final sessionId, :final fileId, :final savedPath):
        final key = '$sessionId/$fileId';
        final current = files[key];
        if (current == null) return;
        files[key] = current.copyWith(
          receivedBytes: current.size,
          savedPath: savedPath,
        );
      case FileFailed(:final sessionId, :final fileId, :final code):
        final key = '$sessionId/$fileId';
        final current = files[key];
        if (current == null) return;
        files[key] = current.copyWith(error: code, receivedBytes: 0);
    }
    state = state.copyWith(files: files);
  }
}
