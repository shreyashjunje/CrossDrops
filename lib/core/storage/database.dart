import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// This device's identity. Holds one row (`slot` = 1).
///
/// See ARCHITECTURE.md, "Data model". The private key never goes here; it
/// will live in the Keychain / Keystore (Phase 4).
class Identity extends Table {
  IntColumn get slot => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
  TextColumn get deviceName => text()();

  /// PEM certificate. Null until the persistent identity lands in Phase 4.
  TextColumn get certificate => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {slot};
}

@DriftDatabase(tables: [Identity])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'crossdrop'));

  @override
  int get schemaVersion => 1;
}
