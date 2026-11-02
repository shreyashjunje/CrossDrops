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

/// One transfer session, sent or received. The same session id can appear
/// once per direction.
@DataClassName('SessionRow')
class TransferSessions extends Table {
  @override
  String get tableName => 'sessions';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionId => text()();

  /// `send` or `receive`.
  TextColumn get direction => text()();
  TextColumn get peerDeviceId => text()();
  TextColumn get peerName => text()();
  TextColumn get peerPlatform => text()();

  /// Last known address of the receiver (send direction only).
  TextColumn get peerHost => text().nullable()();
  IntColumn get peerPort => integer().nullable()();

  /// A [SessionStatus] name.
  TextColumn get status => text()();

  /// Why it was rejected, cancelled or failed.
  TextColumn get reason => text().nullable()();
  IntColumn get totalBytes => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {sessionId, direction},
  ];
}

/// One file of a session, in manifest order.
@DataClassName('SessionFileRow')
class SessionFiles extends Table {
  @override
  String get tableName => 'session_files';

  IntColumn get sessionRowId => integer().references(
    TransferSessions,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get fileId => text()();
  IntColumn get position => integer()();

  /// As offered (receive) or picked (send). Local only; never logged.
  TextColumn get name => text()();
  IntColumn get size => integer()();
  TextColumn get mime => text().nullable()();
  TextColumn get kind => text()();
  DateTimeColumn get created => dateTime().nullable()();
  TextColumn get livePhotoGroup => text().nullable()();
  TextColumn get sha256 => text().nullable()();

  /// Receive: bytes known to be on disk (checkpoint). Send: bytes the
  /// receiver confirmed.
  IntColumn get transferredBytes => integer().withDefault(const Constant(0))();
  TextColumn get tempPath => text().nullable()();

  /// Send direction: the file being read.
  TextColumn get sourcePath => text().nullable()();
  TextColumn get finalLocation => text().nullable()();

  /// A [FileTransferStatus] name.
  TextColumn get status => text()();

  /// Hash checks that failed; the file fails for good after the second.
  IntColumn get hashAttempts => integer().withDefault(const Constant(0))();
  TextColumn get errorCode => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {sessionRowId, fileId};
}

@DriftDatabase(tables: [Identity, TransferSessions, SessionFiles])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'crossdrop'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(transferSessions);
        await m.createTable(sessionFiles);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
