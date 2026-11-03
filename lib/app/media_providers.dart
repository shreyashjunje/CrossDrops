import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/engine/source_opener.dart';
import '../core/media/prepare.dart';
import '../core/server/file_store.dart';
import '../platform/android_source.dart';
import '../platform/android_store.dart';
import '../platform/document_picker.dart';
import '../platform/ios_export.dart';
import '../platform/ios_photos.dart';
import '../platform/share_inbox.dart';
import 'app_dirs.dart';

/// App folders, resolved once.
final appDirsProvider = FutureProvider<AppDirs>((ref) => AppDirs.resolve());

final androidSourcesProvider = Provider<AndroidSources>(
  (ref) => AndroidSources(),
);

/// Opens what a send reads: content URIs as descriptors on Android,
/// files elsewhere (D-036).
final sourceOpenerProvider = Provider<SourceOpener>(
  (ref) => Platform.isAndroid
      ? AndroidSourceOpener(ref.read(androidSourcesProvider))
      : const FileSourceOpener(),
);

/// Exports (iOS) or resolves (Android) photo-library items (D-038).
final mediaPlatformProvider = Provider<MediaPlatform>(
  (ref) => Platform.isIOS
      ? IosMedia()
      : AndroidMedia(
          ref.read(androidSourcesProvider),
          uriFor: (id) async => (await AssetEntity.fromId(id))?.getMediaUrl(),
        ),
);

/// The "any file" picker (D-041).
final documentPickerProvider = FutureProvider<DocumentPicker>((ref) async {
  if (Platform.isAndroid) {
    return AndroidDocumentPicker(ref.read(androidSourcesProvider));
  }
  final dirs = await ref.read(appDirsProvider.future);
  return IosDocumentPicker(dirs.outgoingStaging);
});

/// Where received files go: MediaStore on Android (D-040), the app folder
/// with Photos on iOS.
final receivedFileStoreProvider = FutureProvider<ReceivedFileStore>((
  ref,
) async {
  if (Platform.isAndroid) return MediaStoreFileStore(ChannelMediaStore());
  final dirs = await ref.read(appDirsProvider.future);
  return FolderStore(dirs.received, mediaSaver: ref.read(photosSaverProvider));
});

/// iOS Photos library saving (D-043); unused on Android.
final photosSaverProvider = Provider<IosPhotosSaver>((ref) => IosPhotosSaver());

/// The App Group inbox of the iOS Share Extension (D-045). Null until the
/// app folders are known.
final iosShareInboxProvider = Provider<ShareInbox?>((ref) {
  final dirs = ref.watch(appDirsProvider).value;
  if (dirs == null) return null;
  return IosShareInbox(stagingRoot: dirs.outgoingStaging);
});
