import 'package:crossdrop/core/media/save_target.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SaveCollection on(DevicePlatform platform, String name, String kind) =>
      saveCollectionFor(safeName: name, declaredKind: kind, platform: platform);

  for (final platform in DevicePlatform.values) {
    group(platform.name, () {
      test('photos and videos go to the gallery', () {
        expect(
          on(platform, 'IMG_1.HEIC', FileKind.photo),
          SaveCollection.photos,
        );
        expect(
          on(platform, 'IMG_1.JPG', FileKind.photo),
          SaveCollection.photos,
        );
        expect(on(platform, 'shot.png', FileKind.photo), SaveCollection.photos);
        expect(
          on(platform, 'IMG_1.MOV', FileKind.video),
          SaveCollection.videos,
        );
        expect(
          on(platform, 'VID_1.mp4', FileKind.video),
          SaveCollection.videos,
        );
      });

      test('documents, archives and audio go to files', () {
        expect(on(platform, 'a.pdf', FileKind.file), SaveCollection.files);
        expect(on(platform, 'a.zip', FileKind.file), SaveCollection.files);
        expect(on(platform, 'a.mp3', FileKind.file), SaveCollection.files);
        expect(on(platform, 'README', FileKind.file), SaveCollection.files);
      });

      test('the declared MIME type is never used, only the extension', () {
        // A sender calling an executable a photo still gets files.
        expect(on(platform, 'evil.apk', FileKind.photo), SaveCollection.files);
        expect(on(platform, 'noext', FileKind.photo), SaveCollection.files);
      });

      test('a kind that contradicts the extension goes to files', () {
        expect(on(platform, 'IMG_1.JPG', FileKind.video), SaveCollection.files);
        expect(on(platform, 'clip.mp4', FileKind.photo), SaveCollection.files);
      });

      test('a picture the sender offered as a plain file stays a file', () {
        expect(on(platform, 'scan.jpg', FileKind.file), SaveCollection.files);
      });

      test('SVG is never a gallery item', () {
        expect(on(platform, 'logo.svg', FileKind.photo), SaveCollection.files);
      });
    });
  }

  test('iOS Photos refuses WebM, Matroska and AVI; Android takes them', () {
    for (final name in ['a.webm', 'a.mkv', 'a.avi']) {
      expect(
        on(DevicePlatform.ios, name, FileKind.video),
        SaveCollection.files,
      );
      expect(
        on(DevicePlatform.android, name, FileKind.video),
        SaveCollection.videos,
      );
    }
  });

  test('raw HEVC streams are files on both', () {
    for (final p in DevicePlatform.values) {
      expect(on(p, 'a.hevc', FileKind.video), SaveCollection.files);
    }
  });
}
