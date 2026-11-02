import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';

import '../protocol/device_name.dart';
import '../storage/database.dart';

/// Values allowed for the `p` TXT key and `platform` fields.
enum DevicePlatform {
  ios,
  android;

  static DevicePlatform? tryParse(String value) {
    for (final p in values) {
      if (p.name == value) return p;
    }
    return null;
  }

  /// The platform this app runs on. Desktop builds (tools, tests) report
  /// android so they stay within the protocol's two values.
  static DevicePlatform get current =>
      Platform.isIOS ? DevicePlatform.ios : DevicePlatform.android;
}

/// The persistent part of this device's identity.
///
/// The certificate fingerprint is the real identity (ARCHITECTURE.md,
/// "Security model"); until Phase 4 the certificate is created at each
/// launch, so its fingerprint is not stored here.
class DeviceIdentity {
  const DeviceIdentity({required this.deviceId, required this.deviceName});

  /// Lowercase UUID v4.
  final String deviceId;
  final String deviceName;
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

bool isValidDeviceId(String id) => _uuidPattern.hasMatch(id);

/// A random UUID v4 from a secure random source.
String newDeviceId([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// "iPhone", or "Android" plus the first 4 characters of the id so two
/// Android phones can be told apart before the user renames them.
String defaultDeviceName(String deviceId, DevicePlatform platform) =>
    switch (platform) {
      DevicePlatform.ios => 'iPhone',
      DevicePlatform.android =>
        'Android ${deviceId.substring(0, 4).toUpperCase()}',
    };

/// Loads, creates and renames the identity row.
class IdentityRepository {
  IdentityRepository(this._db, {DevicePlatform? platform})
    : _platform = platform ?? DevicePlatform.current;

  final AppDatabase _db;
  final DevicePlatform _platform;

  /// Returns the stored identity, creating it on first launch.
  Future<DeviceIdentity> loadOrCreate() {
    return _db.transaction(() async {
      final row = await _db.select(_db.identity).getSingleOrNull();
      if (row != null) {
        return DeviceIdentity(
          deviceId: row.deviceId,
          deviceName: row.deviceName,
        );
      }
      final id = newDeviceId();
      final name = defaultDeviceName(id, _platform);
      await _db
          .into(_db.identity)
          .insert(IdentityCompanion.insert(deviceId: id, deviceName: name));
      return DeviceIdentity(deviceId: id, deviceName: name);
    });
  }

  /// Saves a new name. Throws [ArgumentError] if nothing is left after
  /// sanitizing.
  Future<DeviceIdentity> rename(String name) async {
    final clean = sanitizeDeviceName(name);
    if (clean.isEmpty) throw ArgumentError.value(name, 'name', 'empty');
    final current = await loadOrCreate();
    await _db
        .update(_db.identity)
        .write(IdentityCompanion(deviceName: Value(clean)));
    return DeviceIdentity(deviceId: current.deviceId, deviceName: clean);
  }
}
