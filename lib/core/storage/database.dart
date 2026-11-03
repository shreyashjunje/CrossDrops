import 'package:drift/drift.dart';

part 'database.g.dart';

/// This device's identity. Holds one row (`slot` = 1).
///
/// See ARCHITECTURE.md, "Data model". The private key never goes here; it
/// lives in the Keychain / Keystore-backed storage (`CredentialRepository`).
class Identity extends Table {
  IntColumn get slot => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
  TextColumn get deviceName => text()();

  /// PEM certificate; its SHA-256 is the device identity. Null until the
  /// first launch creates it.
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

  /// The peer's certificate fingerprint: who may continue a received
  /// session, and the pin when a sent session resumes. Null for sessions
  /// stored before Phase 4; those cannot resume.
  TextColumn get peerFingerprint => text().nullable()();

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

/// Devices the user chose to trust (ARCHITECTURE.md, "Pairing"). The
/// fingerprint is the key; the name and id are labels and are never used
/// to decide trust.
@DataClassName('TrustedDeviceRow')
class TrustedDevices extends Table {
  TextColumn get fingerprint => text()();

  /// Last device id seen with this fingerprint, to find it on the network.
  TextColumn get deviceId => text()();
  TextColumn get name => text()();
  TextColumn get platform => text()();

  /// Skip the Accept prompt for offers from this device.
  BoolColumn get autoAccept => boolean().withDefault(const Constant(false))();
  DateTimeColumn get firstSeen => dateTime()();
  DateTimeColumn get lastSeen => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {fingerprint};
}

/// App settings. Holds one row (`slot` = 1).
@DataClassName('SettingsRow')
class Settings extends Table {
  IntColumn get slot => integer().withDefault(const Constant(1))();

  /// The global "Receiving" switch (D-031).
  BoolColumn get receivingEnabled =>
      boolean().withDefault(const Constant(true))();

  /// iPhone to Android: convert HEIC photos to JPEG before sending (D-039).
  BoolColumn get convertHeicToJpeg =>
      boolean().withDefault(const Constant(false))();

  /// iPhone to Android: send a Live Photo's video next to its still.
  BoolColumn get sendLivePhotoVideo =>
      boolean().withDefault(const Constant(false))();

  /// The first-launch introduction was shown (D-050).
  BoolColumn get onboardingDone =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {slot};
}

@DriftDatabase(
  tables: [Identity, TransferSessions, SessionFiles, TrustedDevices, Settings],
)
class AppDatabase extends _$AppDatabase {
  /// The app passes `driftDatabase(name: 'crossdrop')` (see
  /// `databaseProvider`); tests and the dev CLI pass an in-memory database.
  /// No Flutter import here, so the core runs under plain `dart`.
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(transferSessions);
        await m.createTable(sessionFiles);
      }
      if (from < 3) {
        if (from >= 2) {
          await m.addColumn(transferSessions, transferSessions.peerFingerprint);
        }
        await m.createTable(trustedDevices);
        await m.createTable(settings);
      }
      if (from >= 3 && from < 4) {
        await m.addColumn(settings, settings.convertHeicToJpeg);
        await m.addColumn(settings, settings.sendLivePhotoVideo);
      }
      if (from >= 3 && from < 5) {
        await m.addColumn(settings, settings.onboardingDone);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
