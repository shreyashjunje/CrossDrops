/// Messages on `WS /v1/sessions/{id}/events`, receiver to sender.
/// ARCHITECTURE.md, "Protocol spec". Each is one JSON text frame with a
/// `type` field. Unknown types are ignored, so later versions can add some.
library;

import 'models.dart';

sealed class SessionEvent {
  const SessionEvent();

  String get type;

  Map<String, Object?> toJson();

  /// Returns null for unknown event types. Throws [FormatError] for a known
  /// type with bad fields.
  static SessionEvent? fromJson(Object? json) {
    if (json is! Map<String, Object?>) throw FormatError('not an object');
    final fileId = json['fileId'];
    String needFileId() {
      if (fileId is! String || !isValidId(fileId)) {
        throw FormatError('invalid fileId');
      }
      return fileId;
    }

    switch (json['type']) {
      case 'accepted':
        return const AcceptedEvent();
      case 'rejected':
        final reason = json['reason'];
        final needed = json['neededBytes'];
        if (reason is! String || (needed != null && needed is! int)) {
          throw FormatError('invalid rejected event');
        }
        return RejectedEvent(reason, neededBytes: needed as int?);
      case 'progress':
        final received = json['receivedBytes'];
        if (received is! int || received < 0) {
          throw FormatError('invalid progress event');
        }
        return ProgressEvent(needFileId(), received);
      case 'file_done':
        return FileDoneEvent(needFileId());
      case 'cancelled':
        final by = json['by'];
        if (by is! String) throw FormatError('invalid cancelled event');
        return CancelledEvent(by);
      case 'error':
        final code = json['code'];
        if (code is! String) throw FormatError('invalid error event');
        return ErrorEvent(code, fileId: fileId == null ? null : needFileId());
      default:
        return null;
    }
  }
}

/// The receiver tapped Accept. Bytes may now be sent.
class AcceptedEvent extends SessionEvent {
  const AcceptedEvent();

  @override
  String get type => 'accepted';

  @override
  Map<String, Object?> toJson() => {'type': type};
}

/// The receiver refused the offer. [reason] is one of [RejectReasons].
class RejectedEvent extends SessionEvent {
  const RejectedEvent(this.reason, {this.neededBytes});

  final String reason;

  /// For [RejectReasons.noSpace]: bytes the receiver would need.
  final int? neededBytes;

  @override
  String get type => 'rejected';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'reason': reason,
    if (neededBytes != null) 'neededBytes': neededBytes,
  };
}

/// Bytes of [fileId] safely written by the receiver.
class ProgressEvent extends SessionEvent {
  const ProgressEvent(this.fileId, this.receivedBytes);

  final String fileId;
  final int receivedBytes;

  @override
  String get type => 'progress';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'fileId': fileId,
    'receivedBytes': receivedBytes,
  };
}

/// [fileId] was verified and saved.
class FileDoneEvent extends SessionEvent {
  const FileDoneEvent(this.fileId);

  final String fileId;

  @override
  String get type => 'file_done';

  @override
  Map<String, Object?> toJson() => {'type': type, 'fileId': fileId};
}

/// The session was cancelled; [by] is `sender` or `receiver`.
class CancelledEvent extends SessionEvent {
  const CancelledEvent(this.by);

  final String by;

  @override
  String get type => 'cancelled';

  @override
  Map<String, Object?> toJson() => {'type': type, 'by': by};
}

/// Something went wrong; [code] is one of [ErrorCodes]. With a [fileId]
/// it concerns that file only.
class ErrorEvent extends SessionEvent {
  const ErrorEvent(this.code, {this.fileId});

  final String code;
  final String? fileId;

  @override
  String get type => 'error';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'code': code,
    if (fileId != null) 'fileId': fileId,
  };
}
