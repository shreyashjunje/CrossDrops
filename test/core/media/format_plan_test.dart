import 'package:crossdrop/core/media/format_plan.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const heic = LibraryAsset(
    id: 'A',
    kind: FileKind.photo,
    originalName: 'IMG_1234.HEIC',
    mime: 'image/heic',
  );
  const live = LibraryAsset(
    id: 'L',
    kind: FileKind.photo,
    originalName: 'IMG_2000.HEIC',
    isLivePhoto: true,
  );
  const jpeg = LibraryAsset(
    id: 'J',
    kind: FileKind.photo,
    originalName: 'IMG_3000.JPG',
  );
  const png = LibraryAsset(
    id: 'S',
    kind: FileKind.photo,
    originalName: 'IMG_4000.PNG',
  );
  const hevc = LibraryAsset(
    id: 'V',
    kind: FileKind.video,
    originalName: 'IMG_5000.MOV',
  );
  const all = FormatSettings(convertHeicToJpeg: true, sendLivePhotoVideo: true);

  group('defaults send the original still', () {
    for (final a in [heic, live, jpeg, png, hevc]) {
      test(a.originalName!, () {
        expect(
          planExport(
            a,
            const FormatSettings(),
            receiver: DevicePlatform.android,
          ),
          ExportPlan(assetId: a.id),
        );
      });
    }
  });

  test('HEIC converts only when the setting is on', () {
    expect(
      planExport(heic, all, receiver: DevicePlatform.android).convertToJpeg,
      isTrue,
    );
    // HEIF detected from the name when the library gives no MIME type.
    expect(
      planExport(live, all, receiver: DevicePlatform.android).convertToJpeg,
      isTrue,
    );
  });

  test('JPEG, PNG and videos are never converted', () {
    for (final a in [jpeg, png, hevc]) {
      expect(
        planExport(a, all, receiver: DevicePlatform.android),
        ExportPlan(assetId: a.id),
        reason: a.originalName,
      );
    }
  });

  test('Live Photo video only with the setting, and only for Live Photos', () {
    expect(
      planExport(
        live,
        const FormatSettings(sendLivePhotoVideo: true),
        receiver: DevicePlatform.android,
      ),
      const ExportPlan(assetId: 'L', includePairedVideo: true),
    );
    expect(
      planExport(
        heic,
        all,
        receiver: DevicePlatform.android,
      ).includePairedVideo,
      isFalse,
    );
  });

  test('an iPhone receiver always gets the original still', () {
    for (final a in [heic, live, jpeg, hevc]) {
      expect(
        planExport(a, all, receiver: DevicePlatform.ios),
        ExportPlan(assetId: a.id),
      );
    }
  });

  test('an unknown receiver is treated as Android', () {
    expect(planExport(heic, all, receiver: null).convertToJpeg, isTrue);
  });

  group('exportedFileName', () {
    test('original is kept as is', () {
      expect(
        exportedFileName(
          originalName: 'IMG_1234.HEIC',
          exportedName: 'IMG_1234.HEIC',
        ),
        'IMG_1234.HEIC',
      );
    });

    test('an edited photo keeps the original base, not FullSizeRender', () {
      expect(
        exportedFileName(
          originalName: 'IMG_1234.HEIC',
          exportedName: 'FullSizeRender.jpg',
        ),
        'IMG_1234.JPG',
      );
      expect(
        exportedFileName(
          originalName: 'IMG_1234.MOV',
          exportedName: 'FullSizeRender.mov',
        ),
        'IMG_1234.MOV',
      );
    });

    test('conversion changes the extension in the original case', () {
      expect(
        exportedFileName(
          originalName: 'IMG_1234.HEIC',
          exportedName: 'IMG_1234.HEIC',
          convertedToJpeg: true,
        ),
        'IMG_1234.JPG',
      );
      expect(
        exportedFileName(
          originalName: 'photo.heic',
          exportedName: 'photo.heic',
          convertedToJpeg: true,
        ),
        'photo.jpg',
      );
    });

    test('a missing original name uses the exported one', () {
      expect(
        exportedFileName(originalName: null, exportedName: 'IMG_9.PNG'),
        'IMG_9.png',
      );
      expect(exportedFileName(originalName: '', exportedName: ''), 'IMG');
    });

    test('folders in names are dropped', () {
      expect(
        exportedFileName(
          originalName: 'DCIM/100APPLE/IMG_1.HEIC',
          exportedName: 'x.heic',
        ),
        'IMG_1.HEIC',
      );
    });

    test('a Live Photo video sorts next to its still', () {
      expect(
        pairedVideoName(
          originalName: 'IMG_2000.HEIC',
          videoResourceName: 'IMG_2000.MOV',
        ),
        'IMG_2000.MOV',
      );
      // Edited Live Photo: the rendered video is FullSizeRender.mov.
      expect(
        pairedVideoName(
          originalName: 'IMG_2000.HEIC',
          videoResourceName: 'FullSizeRender.mov',
        ),
        'IMG_2000.MOV',
      );
    });
  });
}
