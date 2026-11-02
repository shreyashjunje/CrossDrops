/// Protocol v1 message models. See docs/ARCHITECTURE.md, "Protocol spec".
library;

const int protocolVersion = 1;

/// Allowed characters for ids that end up in URL paths and temp file names.
final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

bool isValidId(String id) => _idPattern.hasMatch(id);

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
  });

  final String fileId;
  final String name;
  final int size;
  final String? mime;

  Map<String, Object?> toJson() => {
    'fileId': fileId,
    'name': name,
    'size': size,
    if (mime != null) 'mime': mime,
  };

  factory FileOffer.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw FormatError('file is not an object');
    }
    final fileId = json['fileId'];
    final name = json['name'];
    final size = json['size'];
    final mime = json['mime'];
    if (fileId is! String || !isValidId(fileId)) {
      throw FormatError('invalid fileId');
    }
    if (name is! String || name.isEmpty) throw FormatError('invalid name');
    if (size is! int || size < 0) throw FormatError('invalid size');
    if (mime != null && mime is! String) throw FormatError('invalid mime');
    return FileOffer(
      fileId: fileId,
      name: name,
      size: size,
      mime: mime as String?,
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
    if (id is! String || name is! String || platform is! String) {
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
  });

  final String id;
  final String name;
  final String platform;

  /// Protocol versions this device supports.
  final List<int> versions;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
    'versions': versions,
  };

  factory DeviceInfo.fromJson(Object? json) {
    if (json is! Map<String, Object?>) throw FormatError('not an object');
    final id = json['id'];
    final name = json['name'];
    final platform = json['platform'];
    final versions = json['versions'];
    if (id is! String ||
        name is! String ||
        platform is! String ||
        versions is! List ||
        versions.any((v) => v is! int)) {
      throw FormatError('invalid info');
    }
    return DeviceInfo(
      id: id,
      name: name,
      platform: platform,
      versions: versions.cast<int>(),
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
    if (files is! List || files.isEmpty) throw FormatError('invalid files');
    final parsed = [for (final f in files) FileOffer.fromJson(f)];
    final ids = parsed.map((f) => f.fileId).toSet();
    if (ids.length != parsed.length) throw FormatError('duplicate fileId');
    return SessionOffer(
      protocol: protocol,
      sender: SenderInfo.fromJson(json['sender']),
      files: parsed,
    );
  }
}

/// Reply to `POST /v1/sessions`.
class SessionCreated {
  const SessionCreated({required this.sessionId, required this.status});

  final String sessionId;
  final String status;

  Map<String, Object?> toJson() => {'sessionId': sessionId, 'status': status};

  factory SessionCreated.fromJson(Object? json) {
    if (json is! Map<String, Object?>) throw FormatError('not an object');
    final sessionId = json['sessionId'];
    final status = json['status'];
    if (sessionId is! String || status is! String) {
      throw FormatError('invalid session reply');
    }
    return SessionCreated(sessionId: sessionId, status: status);
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

  /// `receiving` or `saved`.
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
}
