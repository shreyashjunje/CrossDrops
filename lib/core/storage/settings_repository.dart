import 'package:drift/drift.dart';

import '../media/format_plan.dart';
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

  /// Format settings for sending photos (D-039); both off by default.
  Stream<FormatSettings> watchFormatSettings() => _db
      .select(_db.settings)
      .watchSingleOrNull()
      .map(
        (row) => FormatSettings(
          convertHeicToJpeg: row?.convertHeicToJpeg ?? false,
          sendLivePhotoVideo: row?.sendLivePhotoVideo ?? false,
        ),
      );

  Future<FormatSettings> formatSettings() => watchFormatSettings().first;

  Future<void> setConvertHeicToJpeg(bool value) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(
          slot: const Value(1),
          convertHeicToJpeg: Value(value),
        ),
      );

  Future<void> setSendLivePhotoVideo(bool value) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(
          slot: const Value(1),
          sendLivePhotoVideo: Value(value),
        ),
      );
}
