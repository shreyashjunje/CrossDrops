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
      expect(back.protocol, 1);
      expect(back.sender.platform, 'android');
      expect(back.files.single.fileId, 'f1');
      expect(back.files.single.size, 10);
      expect(back.files.single.mime, 'image/jpeg');
    });

    Map<String, Object?> withFiles(List<Object?> files) => {
      'protocol': 1,
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
