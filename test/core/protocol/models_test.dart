import 'dart:convert';

import 'package:crossdrop/core/protocol/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionOffer', () {
    test('round-trips through JSON', () {
      const offer = SessionOffer(
        sender: SenderInfo(id: 'abc', name: 'Phone', platform: 'android'),
        files: [
          FileOffer(fileId: 'f1', name: 'a.jpg', size: 10, mime: 'image/jpeg'),
        ],
      );
      final back = SessionOffer.fromJson(offer.toJson());
      expect(back.protocol, protocolVersion);
      expect(back.sender.platform, 'android');
      expect(back.files.single.fileId, 'f1');
      expect(back.files.single.size, 10);
      expect(back.files.single.mime, 'image/jpeg');
    });

    Map<String, Object?> withFiles(List<Object?> files) => {
      'protocol': 2,
      'sender': {'id': 'a', 'name': 'b', 'platform': 'ios'},
      'files': files,
    };

    test('rejects empty file list', () {
      expect(
        () => SessionOffer.fromJson(withFiles([])),
        throwsA(isA<FormatError>()),
      );
    });

    test('rejects duplicate fileIds', () {
      final f = {'fileId': 'f1', 'name': 'a', 'size': 1};
      expect(
        () => SessionOffer.fromJson(withFiles([f, f])),
        throwsA(isA<FormatError>()),
      );
    });

    test('rejects negative size', () {
      expect(
        () => SessionOffer.fromJson(
          withFiles([
            {'fileId': 'f1', 'name': 'a', 'size': -1},
          ]),
        ),
        throwsA(isA<FormatError>()),
      );
    });

    test('rejects fileIds that could form paths', () {
      for (final id in ['../x', 'a/b', '', 'a.b', 'x' * 65]) {
        expect(
          () => SessionOffer.fromJson(
            withFiles([
              {'fileId': id, 'name': 'a', 'size': 1},
            ]),
          ),
          throwsA(isA<FormatError>()),
          reason: id,
        );
      }
    });

    test('rejects non-object', () {
      expect(() => SessionOffer.fromJson('x'), throwsA(isA<FormatError>()));
    });
  });

  group('CompleteRequest', () {
    test('accepts 64 hex chars and lowercases', () {
      final r = CompleteRequest.fromJson({'sha256': 'AB' * 32});
      expect(r.sha256, 'ab' * 32);
    });

    test('rejects bad hashes', () {
      for (final h in ['', 'zz' * 32, 'ab' * 31]) {
        expect(
          () => CompleteRequest.fromJson({'sha256': h}),
          throwsA(isA<FormatError>()),
        );
      }
    });
  });

  group('FileOffer manifest fields', () {
    test('kind, created and livePhotoGroup round-trip', () {
      final f = FileOffer(
        fileId: 'f1',
        name: 'IMG_1.MOV',
        size: 5,
        mime: 'video/quicktime',
        kind: FileKind.video,
        created: DateTime.utc(2026, 10, 30, 18, 22),
        livePhotoGroup: 'g1',
      );
      final back = FileOffer.fromJson(f.toJson());
      expect(back.kind, FileKind.video);
      expect(back.created, DateTime.utc(2026, 10, 30, 18, 22));
      expect(back.livePhotoGroup, 'g1');
    });

    test('older manifests without the new fields still parse', () {
      final f = FileOffer.fromJson({'fileId': 'f1', 'name': 'a', 'size': 1});
      expect(f.kind, FileKind.file);
      expect(f.created, isNull);
      expect(f.livePhotoGroup, isNull);
    });

    test('unknown kind and unreadable date are tolerated', () {
      final f = FileOffer.fromJson({
        'fileId': 'f1',
        'name': 'a',
        'size': 1,
        'kind': 'hologram',
        'created': 'yesterday',
      });
      expect(f.kind, FileKind.file);
      expect(f.created, isNull);
    });

    test('rejects absurd names, mimes and group ids', () {
      for (final bad in [
        {'name': 'x' * (maxOfferedNameLength + 1)},
        {'mime': 'x' * 256},
        {'livePhotoGroup': '../g'},
        {'kind': 3},
      ]) {
        expect(
          () => FileOffer.fromJson({
            'fileId': 'f1',
            'name': 'a',
            'size': 1,
            ...bad,
          }),
          throwsA(isA<FormatError>()),
          reason: '$bad',
        );
      }
    });
  });

  test('offer with too many files is rejected', () {
    expect(
      () => SessionOffer.fromJson({
        'protocol': 2,
        'sender': {'id': 'a', 'name': 'b', 'platform': 'ios'},
        'files': [
          for (var i = 0; i <= maxFilesPerOffer; i++)
            {'fileId': 'f$i', 'name': 'a', 'size': 1},
        ],
      }),
      throwsA(isA<FormatError>()),
    );
  });

  group('declared sizes are bounded (review H2)', () {
    Map<String, Object?> offer(List<int> sizes) => {
      'protocol': 2,
      'sender': {'id': 'a', 'name': 'b', 'platform': 'ios'},
      'files': [
        for (final (i, s) in sizes.indexed)
          {'fileId': 'f$i', 'name': 'a', 'size': s},
      ],
    };

    test('a file of exactly 1 TiB is accepted, one byte more is not', () {
      expect(
        SessionOffer.fromJson(offer([maxFileBytes])).totalBytes,
        maxFileBytes,
      );
      expect(
        () => SessionOffer.fromJson(offer([maxFileBytes + 1])),
        throwsA(isA<FormatError>()),
      );
    });

    test('sizes that would wrap a 64-bit sum are refused', () {
      // 4 * 2^62 + 1024 wraps to 1024: the old check showed "1 KB".
      expect(
        () => SessionOffer.fromJson(
          offer([1 << 62, 1 << 62, 1 << 62, 1 << 62, 1024]),
        ),
        throwsA(isA<FormatError>()),
      );
    });

    test('the total is capped at 4 TiB', () {
      expect(
        SessionOffer.fromJson(
          offer([maxFileBytes, maxFileBytes, maxFileBytes, maxFileBytes]),
        ).totalBytes,
        maxOfferBytes,
      );
      expect(
        () => SessionOffer.fromJson(
          offer([maxFileBytes, maxFileBytes, maxFileBytes, maxFileBytes, 1]),
        ),
        throwsA(isA<FormatError>()),
      );
    });

    test('a size beyond 64 bits arrives as a double and is refused', () {
      final json = jsonDecode(
        '{"fileId":"f","name":"a","size":99999999999999999999}',
      ) as Map<String, Object?>;
      expect(() => FileOffer.fromJson(json), throwsA(isA<FormatError>()));
    });
  });

  test('SessionOffer.totalBytes sums the sizes', () {
    const offer = SessionOffer(
      sender: SenderInfo(id: 'a', name: 'b', platform: 'ios'),
      files: [
        FileOffer(fileId: 'a', name: 'a', size: 3),
        FileOffer(fileId: 'b', name: 'b', size: 4),
      ],
    );
    expect(offer.totalBytes, 7);
  });

  group('negotiateVersion', () {
    test('picks the highest common version', () {
      expect(negotiateVersion([2]), 2);
      expect(negotiateVersion([1, 2, 3]), 2);
    });

    test('returns null when there is none', () {
      expect(negotiateVersion([]), isNull);
      // Version 1 is refused (D-061).
      expect(negotiateVersion([1]), isNull);
      expect(negotiateVersion([0, 3]), isNull);
    });
  });

  test('SessionStatusReply round-trips', () {
    const reply = SessionStatusReply(
      sessionId: 's1',
      status: SessionStatus.rejected,
      reason: RejectReasons.noSpace,
      files: [
        FileStatus(fileId: 'f', size: 5, receivedBytes: 0, status: 'pending'),
      ],
    );
    final back = SessionStatusReply.fromJson(reply.toJson());
    expect(back.status, SessionStatus.rejected);
    expect(back.reason, RejectReasons.noSpace);
    expect(back.files.single.status, 'pending');
    expect(
      () => SessionStatusReply.fromJson({...reply.toJson(), 'status': 'x'}),
      throwsA(isA<FormatError>()),
    );
  });

  test('FileStatus round-trips', () {
    const s = FileStatus(
      fileId: 'f',
      size: 5,
      receivedBytes: 3,
      status: 'receiving',
    );
    final back = FileStatus.fromJson(s.toJson());
    expect(back.receivedBytes, 3);
    expect(back.status, 'receiving');
  });
}
