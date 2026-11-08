import 'package:crossdrop/core/media/format_plan.dart';
import 'package:crossdrop/core/media/prepare.dart';
import 'package:crossdrop/core/media/thumb_ref.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('thumbForLocation', () {
    test('Photos library ids preview from the library', () {
      expect(
        thumbForLocation('photos:ABC/L0/001', kind: FileKind.photo),
        const LibraryThumb('ABC/L0/001', kind: FileKind.photo),
      );
    });

    test('content URIs and paths preview as files', () {
      expect(
        thumbForLocation(
          'content://media/external/images/media/7',
          kind: FileKind.photo,
        ),
        const FileThumb(
          'content://media/external/images/media/7',
          kind: FileKind.photo,
        ),
      );
      final t = thumbForLocation('/docs/a.pdf', kind: FileKind.file);
      expect(t, isA<FileThumb>());
      expect(t!.kind, FileKind.file);
    });

    test('nothing to preview', () {
      expect(thumbForLocation(null, kind: FileKind.photo), isNull);
      expect(thumbForLocation('', kind: FileKind.photo), isNull);
      expect(thumbForLocation('photos:', kind: FileKind.photo), isNull);
    });
  });

  test('equal references share one cache entry', () {
    expect(
      const LibraryThumb('1', kind: FileKind.photo),
      const LibraryThumb('1', kind: FileKind.video),
    );
    expect(
      const FileThumb('/a', kind: FileKind.photo).hashCode,
      const FileThumb('/a', kind: FileKind.photo).hashCode,
    );
    expect(
      const FileThumb('1', kind: FileKind.photo),
      isNot(const LibraryThumb('1', kind: FileKind.photo)),
    );
  });

  test('picked items preview what was picked', () {
    const asset = PickedAsset(LibraryAsset(id: 'x', kind: FileKind.video));
    expect(asset.thumb, const LibraryThumb('x', kind: FileKind.video));
    const file = PickedFile(
      ref: 'content://docs/9',
      name: 'holiday.MP4',
      mime: 'application/octet-stream',
    );
    expect(file.kind, FileKind.video, reason: 'from the name');
    expect(
      file.thumb,
      const FileThumb('content://docs/9', kind: FileKind.video),
    );
  });
}
