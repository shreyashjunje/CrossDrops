import 'package:crossdrop/core/media/save_target.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:crossdrop/core/server/file_store.dart';
import 'package:crossdrop/features/transfer/transfer_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatSize switches to GB at 10^9 bytes', () {
    expect(formatSize(999999999), '1000.0 MB');
    expect(formatSize(2000000000), '2.00 GB');
  });

  test('formatTimeLeft', () {
    expect(formatTimeLeft(null), '');
    expect(formatTimeLeft(Duration.zero), '1 s left');
    expect(formatTimeLeft(const Duration(seconds: 42)), '42 s left');
    expect(formatTimeLeft(const Duration(seconds: 150)), 'about 3 min left');
    expect(
      formatTimeLeft(const Duration(hours: 1, minutes: 5)),
      'about 1 h 5 min left',
    );
  });

  group('formatSavedTo', () {
    test('names the place on each platform', () {
      expect(
        formatSavedTo(
          SaveCollection.photos,
          null,
          platform: DevicePlatform.ios,
        ),
        'Saved to Photos',
      );
      expect(
        formatSavedTo(SaveCollection.files, null, platform: DevicePlatform.ios),
        'Saved to Files > On My iPhone > CrossDrop',
      );
      expect(
        formatSavedTo(
          SaveCollection.videos,
          null,
          platform: DevicePlatform.android,
        ),
        'Saved to Movies/CrossDrop',
      );
      expect(
        formatSavedTo(
          SaveCollection.files,
          null,
          platform: DevicePlatform.android,
        ),
        'Saved to Download/CrossDrop',
      );
    });

    test('says why a photo is not in the gallery', () {
      expect(
        formatSavedTo(
          SaveCollection.files,
          SaveFallback.unsupported,
          platform: DevicePlatform.ios,
        ),
        'Saved to Files > On My iPhone > CrossDrop '
        '(Photos cannot import this format)',
      );
      expect(
        formatSavedTo(
          SaveCollection.files,
          SaveFallback.permission,
          platform: DevicePlatform.ios,
        ),
        contains('may not add to Photos'),
      );
      expect(
        formatSavedTo(
          SaveCollection.files,
          SaveFallback.unsupported,
          platform: DevicePlatform.android,
        ),
        contains('gallery cannot open'),
      );
    });
  });
}
