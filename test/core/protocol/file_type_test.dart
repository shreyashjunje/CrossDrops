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
    expect(guessFileType('Screenshot 2026-11-03.png').kind, FileKind.photo);
    expect(guessFileType('backup.ZIP').mime, 'application/zip');
    expect(guessFileType('IMG_0001.DNG').kind, FileKind.photo);
    expect(guessFileType('clip.mkv').kind, FileKind.video);
  });

  test('unknown or missing extension is a plain file', () {
    expect(guessFileType('README'), (mime: null, kind: FileKind.file));
    expect(guessFileType('a.xyz'), (mime: null, kind: FileKind.file));
    expect(guessFileType('.hidden'), (mime: null, kind: FileKind.file));
    expect(guessFileType('trailing.'), (mime: null, kind: FileKind.file));
  });

  test('audio, SVG and icons are files, not photos or videos', () {
    expect(guessFileType('song.mp3').kind, FileKind.file);
    expect(guessFileType('voice.m4a').kind, FileKind.file);
    expect(guessFileType('logo.svg').kind, FileKind.file);
    expect(guessFileType('favicon.ico').kind, FileKind.file);
    expect(guessFileType('design.psd').kind, FileKind.file);
  });

  test('a TypeScript .ts file is not taken for a video', () {
    expect(guessFileType('main.ts'), (mime: null, kind: FileKind.file));
  });

  test('extensionOf ignores folders and leading dots', () {
    expect(extensionOf('a/b.c/README'), '');
    expect(extensionOf(r'C:\x.y\photo.JPG'), 'jpg');
    expect(extensionOf('archive.tar.gz'), 'gz');
    expect(extensionOf('.bashrc'), '');
  });

  group('detectFileType', () {
    test('the photo library kind wins', () {
      // A Live Photo still exported as JPEG is still a photo; a video
      // without a known extension is still a video.
      expect(
        detectFileType(name: 'IMG_1.JPG', platformKind: FileKind.photo).kind,
        FileKind.photo,
      );
      expect(
        detectFileType(
          name: 'clip',
          platformMime: 'video/mp4',
          platformKind: FileKind.video,
        ),
        (mime: 'video/mp4', kind: FileKind.video),
      );
    });

    test('the OS MIME type wins over the extension', () {
      // Android content URIs often have names without an extension.
      expect(
        detectFileType(name: 'document', platformMime: 'application/pdf'),
        (mime: 'application/pdf', kind: FileKind.file),
      );
      expect(detectFileType(name: 'image', platformMime: 'image/jpeg'), (
        mime: 'image/jpeg',
        kind: FileKind.photo,
      ));
    });

    test('octet-stream, wildcards and junk fall back to the extension', () {
      for (final junk in [
        'application/octet-stream',
        'image/*',
        '*/*',
        'nonsense',
        '',
        'image/jpeg/extra',
      ]) {
        expect(detectFileType(name: 'a.png', platformMime: junk), (
          mime: 'image/png',
          kind: FileKind.photo,
        ), reason: junk);
      }
    });

    test('MIME parameters and case are normalized', () {
      expect(
        detectFileType(name: 'x', platformMime: 'Text/Plain; charset=UTF-8'),
        (mime: 'text/plain', kind: FileKind.file),
      );
    });

    test('an unknown library kind is ignored', () {
      expect(
        detectFileType(name: 'a.pdf', platformKind: 'hologram').kind,
        FileKind.file,
      );
    });
  });
}
