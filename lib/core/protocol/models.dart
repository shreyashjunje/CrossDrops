/// Protocol message models. See docs/ARCHITECTURE.md, "Protocol spec".
///
/// The URL paths stay under `/v1`; this number is the wire version that
/// `GET /v1/info`, the TXT record and the QR code carry.
library;

/// The newest protocol version this app speaks. 2: the auth commitment
/// covers both fingerprints (D-061).
const int protocolVersion = 2;

/// Every protocol version this app speaks, oldest first. Below the first
/// entry is the minimum supported version (ARCHITECTURE.md, "Threats").
/// Version 1 is refused: its pairing code could be steered by a man in
/// the middle (D-061).
const List<int> supportedVersions = [2];

/// The highest version in both [supportedVersions] and [theirs], or null if
/// there is none ("Update CrossDrop on the other phone").
int? negotiateVersion(Iterable<int> theirs) {
  int? best;
  for (final v in theirs) {
    if (supportedVersions.contains(v) && (best == null || v > best)) best = v;
  }
  return best;
}

/// Most files one offer may list. Bounds the memory and database rows a
/// single offer can cost the receiver.
const int maxFilesPerOffer = 10000;

/// Longest file name accepted in an offer, in UTF-16 code units, before
/// sanitizing. Longer names are refused rather than silently cut.
const int maxOfferedNameLength = 1024;

/// Largest file an offer may declare: 1 TiB, more than any phone holds.
/// With [maxFilesPerOffer] it keeps every sum of declared sizes far below
/// 2^63, so totals and the free-space check cannot wrap around.
const int maxFileBytes = 1 << 40;

/// Largest total an offer may declare: 4 TiB.
const int maxOfferBytes = 4 << 40;

/// Allowed characters for ids that end up in URL paths and temp file names.
final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

bool isValidId(String id) => _idPattern.hasMatch(id);

/// What a file is, so the receiver knows where to save it.
abstract final class FileKind {
  static const photo = 'photo';
  static const video = 'video';
  static const file = 'file';

  static const all = {photo, video, file};
}

class FormatError implements Exception {
  FormatError(this.message);
  final String message;
  @override
  String toString() => 'FormatError: $message';
}

class FileOffer {
  const FileOffer({
    required this.fileId,
    required this.name,
    required this.size,
    this.mime,
    this.kind = FileKind.file,
    this.created,
    this.livePhotoGroup,
  });

  final String fileId;

  /// As sent by the peer. Sanitize before using it on disk.
  final String name;
  final int size;
  final String? mime;

  /// One of [FileKind]. Unknown kinds from newer peers read as `file`.
  final String kind;
  final DateTime? created;

  /// Files with the same value form one Live Photo (still plus video).
  final String? livePhotoGroup;

  Map<String, Object?> toJson() => {
    'fileId': fileId,
    'name': name,
    'size': size,
    if (mime != null) 'mime': mime,
    'kind': kind,
    if (created != null) 'created': created!.toUtc().toIso8601String(),
    'livePhotoGroup': livePhotoGroup,
  };

  factory FileOffer.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw FormatError('file is not an object');
    }
    final fileId = json['fileId'];
    final name = json['name'];
    final size = json['size'];
    final mime = json['mime'];
    final kind = json['kind'];
    final created = json['created'];
    final group = json['livePhotoGroup'];
    if (fileId is! String || !isValidId(fileId)) {
      throw FormatError('invalid fileId');
    }
    if (name is! String || name.isEmpty || name.length > maxOfferedNameLength) {
      throw FormatError('invalid name');
    }
    if (size is! int || size < 0 || size > maxFileBytes) {
      throw FormatError('invalid size');
    }
    if (mime != null && (mime is! String || mime.length > 255)) {
      throw FormatError('invalid mime');
    }
    if (kind != null && kind is! String) throw FormatError('invalid kind');
    if (created != null && created is! String) {
      throw FormatError('invalid created');
    }
    if (group != null && (group is! String || !isValidId(group))) {
      throw FormatError('invalid livePhotoGroup');
    }
    return FileOffer(
      fileId: fileId,
      name: name,
      size: size,
      mime: mime as String?,
      kind: FileKind.all.contains(kind) ? kind! as String : FileKind.file,
      // A date we can't read is metadata, not a reason to refuse the file.
      created: created == null ? null : DateTime.tryParse(created as String),
      livePhotoGroup: group as String?,
    );
  }
}

class SenderInfo {
  const SenderInfo({
    required this.id,
    required this.name,
    required this.platform,
  });

  final String id;
  final String name;
  final String platform;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
  };

  factory SenderInfo.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw FormatError('sender is not an object');
    }
    final id = json['id'];
    final name = json['name'];
    final platform = json['platform'];
    if (id is! String ||
        !isValidId(id.replaceAll('-', '')) ||
        name is! String ||
        name.length > 256 ||
        platform is! String ||
        platform.length > 16) {
      throw FormatError('invalid sender');
    }
    return SenderInfo(id: id, name: name, platform: platform);
  }
}

/// Reply to `GET /v1/info`.
class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    this.versions = const [protocolVersion],
    this.uploadSlots = 1,
  });

  final String id;
  final String name;
  final String platform;

  /// Protocol versions this device supports.
  final List<int> versions;

  /// Files of one session the receiver takes at the same time (D-068).
  /// Absent in replies from older versions, which take one at a time.
  final int uploadSlots;

  /// The most a receiver may ask for; a larger claim is cut to this.
  static const int maxUploadSlots = 8;

  DeviceInfo withUploadSlots(int slots) => DeviceInfo(
    id: id,
    name: name,
    platform: platform,
    versions: versions,
    uploadSlots: slots,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
    'versions': versions,
    if (uploadSlots != 1) 'uploadSlots': uploadSlots,
  };

  factory DeviceInfo.fromJson(Object? json) {
    if (json is! Map<String, Object?>) throw FormatError('not an object');
    final id = json['id'];
    final name = json['name'];
    final platform = json['platform'];
    final versions = json['versions'];
    final slots = json['uploadSlots'] ?? 1;
    if (id is! String ||
        name is! String ||
        platform is! String ||
        versions is! List ||
        versions.any((v) => v is! int) ||
        slots is! int ||
        slots < 1) {
      throw FormatError('invalid info');
    }
    return DeviceInfo(
      id: id,
      name: name,
      platform: platform,
      versions: versions.cast<int>(),
      uploadSlots: slots > maxUploadSlots ? maxUploadSlots : slots,
    );
  }
}

/// Body of `POST /v1/sessions`.
class SessionOffer {
  const SessionOffer({
    required this.sender,
    required this.files,
    this.protocol = protocolVersion,
  });

  final int protocol;
  final SenderInfo sender;
  final List<FileOffer> files;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);

  Map<String, Object?> toJson() => {
    'protocol': protocol,
    'sender': sender.toJson(),
    'files': [for (final f in files) f.toJson()],
  };

  factory SessionOffer.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw FormatError('offer is not an object');
    }
    final protocol = json['protocol'];
    final files = json['files'];
    if (protocol is! int) throw FormatError('invalid protocol');
    if (files is! List || files.isEmpty || files.length > maxFilesPerOffer) {
      throw FormatError('invalid files');
    }
    final parsed = [for (final f in files) FileOffer.fromJson(f)];
    final ids = parsed.map((f) => f.fileId).toSet();
    if (ids.length != parsed.length) throw FormatError('duplicate fileId');
    // Each size is at most maxFileBytes, so this sum cannot overflow.
    var total = 0;
    for (final f in parsed) {
      total += f.size;
      if (total > maxOfferBytes) throw FormatError('offer too large');
    }
    return SessionOffer(
      protocol: protocol,
      sender: SenderInfo.fromJson(json['sender']),
      files: parsed,
    );
  }
}

/// Reply to `POST /v1/sessions`.
class SessionCreated {
  const SessionCreated({
    required this.sessionId,
    required this.status,
    this.trusted = false,
  });

  final String sessionId;
  final String status;

  /// The receiver already trusts this sender, so it shows no pairing code.
  /// When false the sender shows its code until the offer is answered.
  final bool trusted;

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'status': status,
    'trusted': trusted,
  };

  factory SessionCreated.fromJson(Object? json) {
    if (json is! Map<String, Object?>) throw FormatError('not an object');
    final sessionId = json['sessionId'];
    final status = json['status'];
    final trusted = json['trusted'];
    if (sessionId is! String || status is! String) {
      throw FormatError('invalid session reply');
    }
    return SessionCreated(
      sessionId: sessionId,
      status: status,
      trusted: trusted == true,
    );
  }
}

/// Reply to `GET .../files/{fileId}`.
class FileStatus {
  const FileStatus({
    required this.fileId,
    required this.size,
    required this.receivedBytes,
    required this.status,
  });

  final String fileId;
  final int size;
  final int receivedBytes;

  /// One of [FileTransferStatus] names: `pending`, `receiving`,
  /// `verifying`, `saved` or `failed`.
  final String status;

  Map<String, Object?> toJson() => {
    'fileId': fileId,
    'size': size,
    'receivedBytes': receivedBytes,
    'status': status,
  };

  factory FileStatus.fromJson(Object? json) {
    if (json is! Map<String, Object?>) throw FormatError('not an object');
    final fileId = json['fileId'];
    final size = json['size'];
    final receivedBytes = json['receivedBytes'];
    final status = json['status'];
    if (fileId is! String ||
        size is! int ||
        receivedBytes is! int ||
        status is! String) {
      throw FormatError('invalid file status');
    }
    return FileStatus(
      fileId: fileId,
      size: size,
      receivedBytes: receivedBytes,
      status: status,
    );
  }
}

/// Body of `POST .../files/{fileId}/complete`.
class CompleteRequest {
  const CompleteRequest({required this.sha256});

  /// Lowercase hex SHA-256 of the whole file.
  final String sha256;

  Map<String, Object?> toJson() => {'sha256': sha256};

  factory CompleteRequest.fromJson(Object? json) {
    if (json is! Map<String, Object?>) throw FormatError('not an object');
    final sha = json['sha256'];
    if (sha is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha)) {
      throw FormatError('invalid sha256');
    }
    return CompleteRequest(sha256: sha.toLowerCase());
  }
}

/// Session states. ARCHITECTURE.md, "Session state machine". The wire value
/// is the [name].
enum SessionStatus {
  offered,
  accepted,
  transferring,
  paused,
  verifying,
  done,
  rejected,
  cancelled,
  failed;

  bool get isFinal => this == done || this == rejected || this == cancelled;

  /// No more bytes will move in this session.
  bool get isTerminal => isFinal || this == failed;

  static SessionStatus? tryParse(Object? value) {
    for (final s in values) {
      if (s.name == value) return s;
    }
    return null;
  }
}

/// Per-file states. The wire value is the [name].
enum FileTransferStatus {
  pending,
  receiving,
  verifying,
  saved,
  failed;

  bool get isTerminal => this == saved || this == failed;

  static FileTransferStatus? tryParse(Object? value) {
    for (final s in values) {
      if (s.name == value) return s;
    }
    return null;
  }
}

/// Reply to `GET /v1/sessions/{id}`: where a session stands, so a sender
/// that reconnects (or whose event socket missed a message) can catch up.
class SessionStatusReply {
  const SessionStatusReply({
    required this.sessionId,
    required this.status,
    required this.files,
    this.reason,
  });

  final String sessionId;
  final SessionStatus status;
  final List<FileStatus> files;

  /// Why the session was rejected, cancelled or failed; one of
  /// [RejectReasons] or [ErrorCodes].
  final String? reason;

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'status': status.name,
    'files': [for (final f in files) f.toJson()],
    if (reason != null) 'reason': reason,
  };

  factory SessionStatusReply.fromJson(Object? json) {
    if (json is! Map<String, Object?>) throw FormatError('not an object');
    final sessionId = json['sessionId'];
    final status = SessionStatus.tryParse(json['status']);
    final files = json['files'];
    final reason = json['reason'];
    if (sessionId is! String ||
        status == null ||
        files is! List ||
        (reason != null && reason is! String)) {
      throw FormatError('invalid session status');
    }
    return SessionStatusReply(
      sessionId: sessionId,
      status: status,
      files: [for (final f in files) FileStatus.fromJson(f)],
      reason: reason as String?,
    );
  }
}

/// Why a receiver refused an offer (`rejected` event and session reason).
abstract final class RejectReasons {
  /// The user tapped Decline.
  static const declined = 'declined';

  /// Nobody answered the Accept prompt within 60 s.
  static const timeout = 'timeout';

  /// Not enough free space; the event carries `neededBytes`.
  static const noSpace = 'no_space';

  /// This sender already has an unfinished session here.
  static const senderBusy = 'sender_busy';
}

/// Error codes returned as `{"error": code, "message": ..., ...}`.
abstract final class ErrorCodes {
  static const badRequest = 'bad_request';
  static const notFound = 'not_found';
  static const offsetMismatch = 'offset_mismatch';
  static const tooManyBytes = 'too_many_bytes';
  static const busy = 'busy';
  static const incomplete = 'incomplete';
  static const hashMismatch = 'hash_mismatch';
  static const alreadySaved = 'already_saved';
  static const ioError = 'io_error';

  /// No common protocol version.
  static const unsupportedVersion = 'unsupported_version';

  /// Bytes sent before the receiver accepted.
  static const notAccepted = 'not_accepted';

  /// The session was cancelled, rejected or failed; stop sending.
  static const sessionClosed = 'session_closed';

  /// The file failed for good (second hash mismatch).
  static const fileFailed = 'file_failed';

  /// The receiver's disk filled up mid-transfer; the partial file is kept.
  static const noSpace = 'no_space';

  /// Too many offers: one unfinished session per sender.
  static const senderBusy = 'sender_busy';

  /// 401: no valid token. Authenticate (`/v1/auth`) and retry once.
  static const authRequired = 'auth_required';

  /// 401: the challenge or the signature did not check out.
  static const authFailed = 'auth_failed';

  /// 429: too many requests from this address; see `retryAfter` (seconds).
  static const rateLimited = 'rate_limited';

  /// 403: receiving is turned off and the sender is not trusted.
  static const receivingOff = 'receiving_off';

  /// 403: the request came from outside this phone's local networks.
  static const notLocal = 'not_local';

  /// 431: request headers over the limit.
  static const headersTooLarge = 'headers_too_large';

  /// 413: a JSON body over the limit for its route.
  static const bodyTooLarge = 'body_too_large';
}
