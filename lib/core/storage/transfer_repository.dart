import 'package:drift/drift.dart';

import '../protocol/models.dart';
import 'database.dart';

enum TransferDirection { send, receive }

/// A file row, independent of drift so the engine and server stay simple.
class StoredFile {
  const StoredFile({
    required this.fileId,
    required this.name,
    required this.size,
    required this.kind,
    required this.status,
    this.mime,
    this.created,
    this.livePhotoGroup,
    this.sha256,
    this.transferredBytes = 0,
    this.tempPath,
    this.sourcePath,
    this.finalLocation,
    this.hashAttempts = 0,
    this.errorCode,
  });

  factory StoredFile.fromOffer(
    FileOffer f, {
    String? tempPath,
    String? sourcePath,
  }) => StoredFile(
    fileId: f.fileId,
    name: f.name,
    size: f.size,
    mime: f.mime,
    kind: f.kind,
    created: f.created,
    livePhotoGroup: f.livePhotoGroup,
    status: FileTransferStatus.pending,
    tempPath: tempPath,
    sourcePath: sourcePath,
  );

  final String fileId;
  final String name;
  final int size;
  final String? mime;
  final String kind;
  final DateTime? created;
  final String? livePhotoGroup;
  final String? sha256;
  final int transferredBytes;
  final String? tempPath;
  final String? sourcePath;
  final String? finalLocation;
  final FileTransferStatus status;
  final int hashAttempts;
  final String? errorCode;

  FileOffer toOffer() => FileOffer(
    fileId: fileId,
    name: name,
    size: size,
    mime: mime,
    kind: kind,
    created: created,
    livePhotoGroup: livePhotoGroup,
  );
}

class StoredSession {
  const StoredSession({
    required this.rowId,
    required this.sessionId,
    required this.direction,
    required this.peer,
    required this.status,
    required this.totalBytes,
    required this.createdAt,
    required this.updatedAt,
    required this.files,
    this.peerHost,
    this.peerPort,
    this.peerFingerprint,
    this.reason,
    this.finishedAt,
  });

  final int rowId;
  final String sessionId;
  final TransferDirection direction;
  final SenderInfo peer;
  final String? peerHost;
  final int? peerPort;

  /// Null for sessions stored before Phase 4.
  final String? peerFingerprint;
  final SessionStatus status;
  final String? reason;
  final int totalBytes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? finishedAt;

  /// In manifest order.
  final List<StoredFile> files;

  int get transferredBytes =>
      files.fold(0, (sum, f) => sum + f.transferredBytes);
}

/// Sessions and files in the database (ARCHITECTURE.md, "Data model").
class TransferRepository {
  TransferRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// Stores a new session with its files and returns its row id.
  Future<int> createSession({
    required String sessionId,
    required TransferDirection direction,
    required SenderInfo peer,
    required SessionStatus status,
    required List<StoredFile> files,
    String? peerHost,
    int? peerPort,
    String? peerFingerprint,
  }) {
    final now = _clock();
    return _db.transaction(() async {
      final rowId = await _db
          .into(_db.transferSessions)
          .insert(
            TransferSessionsCompanion.insert(
              sessionId: sessionId,
              direction: direction.name,
              peerDeviceId: peer.id,
              peerName: peer.name,
              peerPlatform: peer.platform,
              peerHost: Value(peerHost),
              peerPort: Value(peerPort),
              peerFingerprint: Value(peerFingerprint),
              status: status.name,
              totalBytes: files.fold(0, (sum, f) => sum + f.size),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _db.batch((b) {
        b.insertAll(_db.sessionFiles, [
          for (final (i, f) in files.indexed)
            SessionFilesCompanion.insert(
              sessionRowId: rowId,
              fileId: f.fileId,
              position: i,
              name: f.name,
              size: f.size,
              mime: Value(f.mime),
              kind: f.kind,
              created: Value(f.created),
              livePhotoGroup: Value(f.livePhotoGroup),
              status: f.status.name,
              transferredBytes: Value(f.transferredBytes),
              tempPath: Value(f.tempPath),
              sourcePath: Value(f.sourcePath),
            ),
        ]);
      });
      return rowId;
    });
  }

  Future<void> updateSession(
    int rowId, {
    SessionStatus? status,
    String? reason,
    String? peerHost,
    int? peerPort,
  }) async {
    final now = _clock();
    await (_db.update(
      _db.transferSessions,
    )..where((t) => t.id.equals(rowId))).write(
      TransferSessionsCompanion(
        status: Value.absentIfNull(status?.name),
        reason: Value.absentIfNull(reason),
        peerHost: Value.absentIfNull(peerHost),
        peerPort: Value.absentIfNull(peerPort),
        updatedAt: Value(now),
        finishedAt: status != null && status.isTerminal
            ? Value(now)
            : const Value.absent(),
      ),
    );
  }

  Future<void> updateFile(
    int rowId,
    String fileId, {
    int? transferredBytes,
    FileTransferStatus? status,
    int? hashAttempts,
    String? sha256,
    String? finalLocation,
    String? errorCode,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.sessionFiles)..where(
            (t) => t.sessionRowId.equals(rowId) & t.fileId.equals(fileId),
          ))
          .write(
            SessionFilesCompanion(
              transferredBytes: Value.absentIfNull(transferredBytes),
              status: Value.absentIfNull(status?.name),
              hashAttempts: Value.absentIfNull(hashAttempts),
              sha256: Value.absentIfNull(sha256),
              finalLocation: Value.absentIfNull(finalLocation),
              errorCode: Value.absentIfNull(errorCode),
            ),
          );
      // Keeps updatedAt fresh so the 24-hour cleanup sees activity.
      await (_db.update(_db.transferSessions)..where((t) => t.id.equals(rowId)))
          .write(TransferSessionsCompanion(updatedAt: Value(_clock())));
    });
  }

  Future<StoredSession?> find(
    String sessionId,
    TransferDirection direction,
  ) async {
    final row =
        await (_db.select(_db.transferSessions)..where(
              (t) =>
                  t.sessionId.equals(sessionId) &
                  t.direction.equals(direction.name),
            ))
            .getSingleOrNull();
    return row == null ? null : _load(row);
  }

  /// Sessions that may still move bytes: not done, rejected, cancelled or
  /// failed. Oldest first.
  Future<List<StoredSession>> unfinished([TransferDirection? direction]) async {
    final terminal = [
      for (final s in SessionStatus.values)
        if (s.isTerminal) s.name,
    ];
    final q = _db.select(_db.transferSessions)
      ..where((t) => t.status.isNotIn(terminal))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    if (direction != null) q.where((t) => t.direction.equals(direction.name));
    return [for (final row in await q.get()) await _load(row)];
  }

  /// The most recent sessions, newest first, for history.
  Future<List<StoredSession>> recent({int limit = 50}) async {
    final q = _db.select(_db.transferSessions)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);
    return [for (final row in await q.get()) await _load(row)];
  }

  Future<StoredSession> _load(SessionRow row) async {
    final files =
        await (_db.select(_db.sessionFiles)
              ..where((t) => t.sessionRowId.equals(row.id))
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get();
    return StoredSession(
      rowId: row.id,
      sessionId: row.sessionId,
      direction: TransferDirection.values.byName(row.direction),
      peer: SenderInfo(
        id: row.peerDeviceId,
        name: row.peerName,
        platform: row.peerPlatform,
      ),
      peerHost: row.peerHost,
      peerPort: row.peerPort,
      peerFingerprint: row.peerFingerprint,
      status: SessionStatus.tryParse(row.status) ?? SessionStatus.failed,
      reason: row.reason,
      totalBytes: row.totalBytes,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      finishedAt: row.finishedAt,
      files: [
        for (final f in files)
          StoredFile(
            fileId: f.fileId,
            name: f.name,
            size: f.size,
            mime: f.mime,
            kind: f.kind,
            created: f.created,
            livePhotoGroup: f.livePhotoGroup,
            sha256: f.sha256,
            transferredBytes: f.transferredBytes,
            tempPath: f.tempPath,
            sourcePath: f.sourcePath,
            finalLocation: f.finalLocation,
            status:
                FileTransferStatus.tryParse(f.status) ??
                FileTransferStatus.failed,
            hashAttempts: f.hashAttempts,
            errorCode: f.errorCode,
          ),
      ],
    );
  }
}
