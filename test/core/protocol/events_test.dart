import 'package:crossdrop/core/protocol/events.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every event round-trips through JSON', () {
    const events = <SessionEvent>[
      AcceptedEvent(),
      RejectedEvent(RejectReasons.noSpace, neededBytes: 42),
      ProgressEvent('f1', 1024),
      FileDoneEvent('f1'),
      CancelledEvent('receiver'),
      ErrorEvent(ErrorCodes.fileFailed, fileId: 'f2'),
      ErrorEvent(ErrorCodes.noSpace),
    ];
    for (final e in events) {
      final back = SessionEvent.fromJson(e.toJson())!;
      expect(back.runtimeType, e.runtimeType);
      expect(back.toJson(), e.toJson());
    }
  });

  test('unknown types are ignored', () {
    expect(SessionEvent.fromJson({'type': 'future_thing', 'x': 1}), isNull);
  });

  test('bad fields are refused', () {
    for (final bad in <Object?>[
      'text',
      {'type': 'progress', 'fileId': 'f1'},
      {'type': 'progress', 'fileId': '../x', 'receivedBytes': 1},
      {'type': 'progress', 'fileId': 'f1', 'receivedBytes': -1},
      {'type': 'rejected'},
      {'type': 'file_done'},
      {'type': 'cancelled'},
      {'type': 'error', 'code': 'x', 'fileId': 3},
    ]) {
      expect(
        () => SessionEvent.fromJson(bad),
        throwsA(isA<FormatError>()),
        reason: '$bad',
      );
    }
  });
}
