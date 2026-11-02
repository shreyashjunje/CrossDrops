import 'package:drift/drift.dart';

import 'database.dart';

/// The `settings` row.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  /// The global "Receiving" switch; on by default (D-031).
  Stream<bool> watchReceivingEnabled() => _db
      .select(_db.settings)
      .watchSingleOrNull()
      .map((row) => row?.receivingEnabled ?? true);

  Future<bool> receivingEnabled() => watchReceivingEnabled().first;

  Future<void> setReceivingEnabled(bool value) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(
          slot: const Value(1),
          receivingEnabled: Value(value),
        ),
      );
}
