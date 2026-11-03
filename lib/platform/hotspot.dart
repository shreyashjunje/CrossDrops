import 'dart:async';

import 'package:flutter/services.dart';

import '../core/log.dart';
import '../core/protocol/connect_payload.dart';

/// A local-only Wi-Fi hotspot started by CrossDrop on Android
/// (ARCHITECTURE.md, scenario 4; D-054).
abstract interface class HotspotService {
  /// Whether this phone can start a hotspot from the app.
  Future<HotspotSupport> support();

  /// Starts the hotspot and returns its name and password. Asks for the
  /// permission first if needed. Throws [HotspotException].
  Future<WifiCredentials> start();

  Future<void> stop();

  /// The user or the system stopped the hotspot.
  Stream<void> get stopped;
}

enum HotspotSupport {
  available,

  /// This platform cannot (iPhone: apps cannot create a hotspot).
  unsupported,
}

class HotspotException implements Exception {
  const HotspotException(this.code);

  /// One of [HotspotErrors].
  final String code;

  @override
  String toString() => 'HotspotException($code)';
}

abstract final class HotspotErrors {
  static const permission = 'permission';

  /// Android 10-12: location services are off.
  static const locationOff = 'location_off';

  /// The phone's own hotspot (tethering) is on.
  static const tetheringOn = 'tethering_on';
  static const noChannel = 'no_channel';

  /// A device policy forbids hotspots.
  static const disallowed = 'disallowed';

  /// An open or OWE network, which CrossDrop does not use.
  static const unsupportedSecurity = 'unsupported_security';
  static const busy = 'busy';
  static const failed = 'failed';
}

/// [HotspotService] over the `crossdrop/hotspot` channel
/// (android/.../HotspotChannel.kt).
class ChannelHotspotService implements HotspotService {
  ChannelHotspotService() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stopped') {
        logEvent('hotspot', 'stopped by the system or the user');
        _stopped.add(null);
      }
    });
  }

  static const _channel = MethodChannel('crossdrop/hotspot');
  final _stopped = StreamController<void>.broadcast();

  @override
  Future<HotspotSupport> support() async => HotspotSupport.available;

  @override
  Future<WifiCredentials> start() async {
    final Map<Object?, Object?>? raw;
    try {
      raw = await _channel.invokeMapMethod<Object?, Object?>('start');
    } on PlatformException catch (e) {
      logEvent('hotspot', 'start failed: ${e.code}');
      throw HotspotException(e.code);
    } on MissingPluginException {
      throw const HotspotException(HotspotErrors.failed);
    }
    final ssid = raw?['ssid'];
    final password = raw?['password'];
    final security = WifiSecurity.fromCode('${raw?['security']}');
    if (ssid is! String ||
        password is! String ||
        security == null ||
        !isValidSsid(ssid) ||
        !isValidWpaPassphrase(password)) {
      await stop();
      logEvent('hotspot', 'start gave an unusable network');
      throw const HotspotException(HotspotErrors.unsupportedSecurity);
    }
    logEvent('hotspot', 'started (${security.code})');
    return WifiCredentials(ssid: ssid, password: password, security: security);
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
      logEvent('hotspot', 'stopped');
    } on MissingPluginException {
      // Nothing to stop.
    }
  }

  @override
  Stream<void> get stopped => _stopped.stream;
}

/// iPhone: apps cannot create a hotspot.
class NoHotspot implements HotspotService {
  const NoHotspot();

  @override
  Future<HotspotSupport> support() async => HotspotSupport.unsupported;

  @override
  Future<WifiCredentials> start() async =>
      throw const HotspotException(HotspotErrors.failed);

  @override
  Future<void> stop() async {}

  @override
  Stream<void> get stopped => const Stream.empty();
}

/// Whether the iPhone can join a network from the app (D-055).
enum JoinCapability {
  /// The app has the Hotspot Configuration entitlement.
  inApp,

  /// No entitlement (free Apple ID builds, D-017): the user joins in
  /// Settings > Wi-Fi.
  manualOnly,
}

enum JoinOutcome {
  /// iOS saved the network and was asked to join. Not proof of a working
  /// connection: wait until the receiver answers.
  requested,

  /// Already on that network.
  alreadyJoined,

  /// The user tapped Cancel on the system prompt.
  userDenied,

  /// The entitlement is missing or iOS refused for an internal reason;
  /// fall back to joining in Settings.
  notAvailable,

  /// iOS refused the name or password.
  invalid,

  /// Anything else; worth one more try.
  failed,
}

/// Joins a Wi-Fi network from the app on iPhone (NEHotspotConfiguration).
abstract interface class HotspotJoiner {
  Future<JoinCapability> capability();

  Future<JoinOutcome> join(WifiCredentials wifi);

  /// Removes the network CrossDrop added, so iOS leaves it and does not
  /// keep it in its list.
  Future<void> forget(String ssid);
}

/// [HotspotJoiner] over the `crossdrop/hotspot_join` channel
/// (ios/Runner/HotspotJoinChannel.swift).
class ChannelHotspotJoiner implements HotspotJoiner {
  static const _channel = MethodChannel('crossdrop/hotspot_join');

  @override
  Future<JoinCapability> capability() async {
    try {
      final inApp = await _channel.invokeMethod<bool>('canJoin') ?? false;
      return inApp ? JoinCapability.inApp : JoinCapability.manualOnly;
    } on MissingPluginException {
      return JoinCapability.manualOnly;
    } on PlatformException {
      return JoinCapability.manualOnly;
    }
  }

  @override
  Future<JoinOutcome> join(WifiCredentials wifi) async {
    try {
      final answer = await _channel.invokeMethod<String>('join', {
        'ssid': wifi.ssid,
        'password': wifi.password,
      });
      final outcome = JoinOutcome.values.firstWhere(
        (o) => o.name == answer,
        orElse: () => JoinOutcome.failed,
      );
      logEvent('hotspot', 'join: ${outcome.name}');
      return outcome;
    } on MissingPluginException {
      return JoinOutcome.notAvailable;
    } on PlatformException catch (e) {
      logEvent('hotspot', 'join failed: ${e.code}');
      return JoinOutcome.failed;
    }
  }

  @override
  Future<void> forget(String ssid) async {
    try {
      await _channel.invokeMethod<void>('forget', {'ssid': ssid});
    } on MissingPluginException {
      // Nothing was added.
    } on PlatformException {
      // Already gone.
    }
  }
}
