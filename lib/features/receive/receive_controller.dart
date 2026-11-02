import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/app_dirs.dart';
import '../../app/providers.dart';
import '../../core/engine/speed_meter.dart';
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
    this.addresses = const [],
    this.saveDir,
    this.files = const {},
    this.error,
  });

  /// Null while the server is starting.
  final int? port;
  final List<String> addresses;
  final String? saveDir;

  /// Keyed by "sessionId/fileId", newest last.
  final Map<String, IncomingFile> files;
  final String? error;

  ReceiveState copyWith({
    int? port,
    List<String>? addresses,
    String? saveDir,
    Map<String, IncomingFile>? files,
    String? error,
  }) => ReceiveState(
    port: port ?? this.port,
    addresses: addresses ?? this.addresses,
    saveDir: saveDir ?? this.saveDir,
    files: files ?? this.files,
    error: error ?? this.error,
  );
}

final receiveControllerProvider =
    NotifierProvider.autoDispose<ReceiveController, ReceiveState>(
      ReceiveController.new,
    );

/// Runs the receive server while the Receive screen is open.
class ReceiveController extends Notifier<ReceiveState> {
  ReceiveServer? _server;
  StreamSubscription<ReceiveEvent>? _sub;
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
      state = state.copyWith(
        port: server.port,
        addresses: await _localAddresses(),
        saveDir: dirs.received,
      );
    } catch (e) {
      if (ref.mounted) state = state.copyWith(error: 'Could not start: $e');
    }
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    await _server?.close();
    await WakelockPlus.disable();
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

  static Future<List<String>> _localAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    // Interface names help pick the Wi-Fi address (e.g. wlan0, en0) over
    // mobile data or VPN interfaces.
    return [
      for (final i in interfaces)
        for (final a in i.addresses) '${a.address}  (${i.name})',
    ];
  }
}
