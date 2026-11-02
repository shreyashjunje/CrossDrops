import 'package:drift/drift.dart';

import '../security/fingerprint.dart';
import 'database.dart';

/// A device the user chose to trust. Identity is [fingerprint] only.
class TrustedDevice {
  const TrustedDevice({
    required this.fingerprint,
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.autoAccept,
    required this.firstSeen,
    required this.lastSeen,
  });

  final String fingerprint;
  final String deviceId;
  final String name;
  final String platform;
  final bool autoAccept;
  final DateTime firstSeen;
  final DateTime lastSeen;

  static TrustedDevice _from(TrustedDeviceRow r) => TrustedDevice(
    fingerprint: r.fingerprint,
    deviceId: r.deviceId,
    name: r.name,
    platform: r.platform,
    autoAccept: r.autoAccept,
    firstSeen: r.firstSeen,
    lastSeen: r.lastSeen,
  );
}

/// What this phone knows about a peer's fingerprint.
class PeerTrust {
  const PeerTrust({this.trusted, this.lookalike});

  static const unknown = PeerTrust();

  /// The trust record for this exact fingerprint, if any.
  final TrustedDevice? trusted;

  /// Set only when [trusted] is null: a trusted device with the same name
  /// or device id but a different fingerprint. Shown as a warning: it can
  /// be a reinstall, or someone pretending to be that device.
  final TrustedDevice? lookalike;

  bool get isTrusted => trusted != null;
}

/// The `trusted_devices` table (ARCHITECTURE.md, "Data model").
class TrustRepository {
  TrustRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  Future<TrustedDevice?> find(String fingerprint) async {
    final row = await (_db.select(
      _db.trustedDevices,
    )..where((t) => t.fingerprint.equals(fingerprint))).getSingleOrNull();
    return row == null ? null : TrustedDevice._from(row);
  }

  /// Most recently seen first.
  Stream<List<TrustedDevice>> watchAll() =>
      (_db.select(_db.trustedDevices)
            ..orderBy([(t) => OrderingTerm.desc(t.lastSeen)]))
          .watch()
          .map((rows) => rows.map(TrustedDevice._from).toList());

  Future<List<TrustedDevice>> all() => watchAll().first;

  /// Trust is decided by [fingerprint] alone. [deviceId] and [name] are
  /// only used to spot a lookalike of a trusted device.
  Future<PeerTrust> check({
    required String fingerprint,
    String? deviceId,
    String? name,
  }) async {
    final exact = await find(fingerprint);
    if (exact != null) return PeerTrust(trusted: exact);
    final wanted = name == null ? null : _normalize(name);
    for (final d in await all()) {
      if (fingerprintsEqual(d.fingerprint, fingerprint)) continue;
      final sameId = deviceId != null && d.deviceId == deviceId;
      final sameName =
          wanted != null && wanted.isNotEmpty && _normalize(d.name) == wanted;
      if (sameId || sameName) return PeerTrust(lookalike: d);
    }
    return PeerTrust.unknown;
  }

  /// Trusts [fingerprint], or refreshes its labels if it is already
  /// trusted. Keeps [TrustedDevice.autoAccept] and first-seen time.
  Future<TrustedDevice> trust({
    required String fingerprint,
    required String deviceId,
    required String name,
    required String platform,
  }) async {
    if (!isValidFingerprint(fingerprint)) {
      throw ArgumentError.value(fingerprint, 'fingerprint');
    }
    final now = _clock();
    await _db
        .into(_db.trustedDevices)
        .insert(
          TrustedDevicesCompanion.insert(
            fingerprint: fingerprint,
            deviceId: deviceId,
            name: name,
            platform: platform,
            firstSeen: now,
            lastSeen: now,
          ),
          onConflict: DoUpdate(
            (_) => TrustedDevicesCompanion(
              deviceId: Value(deviceId),
              name: Value(name),
              platform: Value(platform),
              lastSeen: Value(now),
            ),
          ),
        );
    return (await find(fingerprint))!;
  }

  /// Records that the trusted device was just seen under these labels. Does
  /// nothing for a fingerprint that is not trusted.
  Future<void> touch(String fingerprint, {String? deviceId, String? name}) =>
      (_db.update(
        _db.trustedDevices,
      )..where((t) => t.fingerprint.equals(fingerprint))).write(
        TrustedDevicesCompanion(
          lastSeen: Value(_clock()),
          deviceId: Value.absentIfNull(deviceId),
          name: Value.absentIfNull(name),
        ),
      );

  Future<void> setAutoAccept(String fingerprint, bool value) =>
      (_db.update(_db.trustedDevices)
            ..where((t) => t.fingerprint.equals(fingerprint)))
          .write(TrustedDevicesCompanion(autoAccept: Value(value)));

  Future<void> remove(String fingerprint) => (_db.delete(
    _db.trustedDevices,
  )..where((t) => t.fingerprint.equals(fingerprint))).go();

  static String _normalize(String name) => name.trim().toLowerCase();
}
