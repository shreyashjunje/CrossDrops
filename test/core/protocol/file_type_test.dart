import 'package:crossdrop/core/protocol/file_type.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('photos, videos and files', () {
    expect(guessFileType('IMG_4021.HEIC'), (
      mime: 'image/heic',
      kind: FileKind.photo,
    ));
    expect(guessFileType('IMG_4021.MOV'), (
      mime: 'video/quicktime',
      kind: FileKind.video,
    ));
    expect(guessFileType('notes.pdf'), (
      mime: 'application/pdf',
      kind: FileKind.file,
    ));
  });

  test('unknown or missing extension is a plain file', () {
    expect(guessFileType('README'), (mime: null, kind: FileKind.file));
    expect(guessFileType('a.xyz'), (mime: null, kind: FileKind.file));
    expect(guessFileType('.hidden'), (mime: null, kind: FileKind.file));
  });
}
