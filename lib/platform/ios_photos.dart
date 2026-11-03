import 'package:flutter/services.dart';

import '../core/log.dart';
import '../core/server/file_store.dart';

/// Dart side of `crossdrop/photos` (ios/Runner/PhotosSaveChannel.swift):
/// saves received photos and videos into the Photos library (D-043).
class IosPhotosSaver implements MediaSaver {
  IosPhotosSaver([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('crossdrop/photos');

  final MethodChannel _channel;

  /// Asks for add-only access (the prompt shows once). True if CrossDrop
  /// may add to the library.
  Future<bool> requestAccess() async {
    try {
      final status = await _channel.invokeMethod<String>('requestAddOnly');
      return status == 'authorized' || status == 'limited';
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<GallerySave> saveToGallery(
    String path, {
    required String safeName,
    required String kind,
    DateTime? created,
  }) async {
    if (!await requestAccess()) {
      return const GallerySave.refused(SaveFallback.permission);
    }
    try {
      final id = await _channel.invokeMethod<String>('save', {
        'path': path,
        'kind': kind,
        'name': safeName,
        'createdMs': created?.millisecondsSinceEpoch,
      });
      return GallerySave.saved('photos:$id');
    } on PlatformException catch (e) {
      logEvent('photos', 'save refused (${e.code})');
      return switch (e.code) {
        'no_space' => const GallerySave.full(),
        'permission' => const GallerySave.refused(SaveFallback.permission),
        _ => const GallerySave.refused(SaveFallback.unsupported),
      };
    }
  }
}
