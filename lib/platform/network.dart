import 'dart:async';

import 'package:flutter/services.dart';

import '../core/discovery/subnet.dart';
import '../core/log.dart';

/// The phone's Wi-Fi client connection, as Android reports it.
class WifiState {
  const WifiState({
    this.connected = false,
    this.validated = false,
    this.isDefault = false,
    this.bound = false,
    this.frequencyMhz,
    this.linkMbps,
  });

  factory WifiState.fromMap(Map<Object?, Object?> m) => WifiState(
    connected: m['connected'] == true,
    validated: m['validated'] == true,
    isDefault: m['isDefault'] == true,
    bound: m['bound'] == true,
    frequencyMhz: m['frequencyMhz'] is int ? m['frequencyMhz']! as int : null,
    linkMbps: m['linkMbps'] is int ? m['linkMbps']! as int : null,
  );

  final bool connected;

  /// Android checked that the network reaches the internet.
  final bool validated;

  /// New sockets use this network unless the process is bound.
  final bool isDefault;

  /// CrossDrop bound its process to this network (D-056).
  final bool bound;
  final int? frequencyMhz;
  final int? linkMbps;

  /// `2.4 GHz`, `5 GHz`, `6 GHz` or null.
  String? get band => switch (frequencyMhz) {
    null => null,
    final f when f < 3000 => '2.4 GHz',
    final f when f < 5925 => '5 GHz',
    _ => '6 GHz',
  };

  @override
  String toString() =>
      'WifiState(connected: $connected, validated: $validated, '
      'default: $isDefault, bound: $bound, band: $band, link: $linkMbps)';
}

/// Network details Dart cannot get by itself: address prefixes, the Wi-Fi
/// state and process binding. Behind an interface so the core stays
/// testable (CLAUDE.md hard rule 9).
abstract interface class NetworkPlatform {
  /// Every IPv4 address with its prefix length. Empty if unknown.
  Future<List<InterfaceAddress>> interfaces();

  /// Android only; null elsewhere.
  Future<WifiState?> wifiState();

  Stream<WifiState> get wifiChanges;

  /// Android: binds the process to the Wi-Fi network, or clears it.
  /// Returns false if that failed or is not supported.
  Future<bool> bindToWifi(bool on);
}

/// [NetworkPlatform] over the `crossdrop/network` channel
/// (android/.../NetworkChannel.kt, ios/Runner/AppDelegate.swift).
class ChannelNetworkPlatform implements NetworkPlatform {
  ChannelNetworkPlatform() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'wifiChanged' && call.arguments is Map) {
        _changes.add(
          WifiState.fromMap(call.arguments as Map<Object?, Object?>),
        );
      }
    });
  }

  static const _channel = MethodChannel('crossdrop/network');
  final _changes = StreamController<WifiState>.broadcast();

  @override
  Future<List<InterfaceAddress>> interfaces() async {
    try {
      final raw = await _channel.invokeListMethod<Object?>('interfaces');
      return [
        for (final e in raw ?? const <Object?>[])
          if (e is Map &&
              e['name'] is String &&
              e['ip'] is String &&
              e['prefix'] is int)
            InterfaceAddress(
              e['name'] as String,
              e['ip'] as String,
              e['prefix'] as int,
            ),
      ];
    } on MissingPluginException {
      return const [];
    } on PlatformException catch (e) {
      logEvent('network', 'interfaces failed: ${e.code}');
      return const [];
    }
  }

  @override
  Future<WifiState?> wifiState() async {
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>('wifiState');
      return raw == null ? null : WifiState.fromMap(raw);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Stream<WifiState> get wifiChanges => _changes.stream;

  @override
  Future<bool> bindToWifi(bool on) async {
    try {
      return await _channel.invokeMethod<bool>('bind', {'wifi': on}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
