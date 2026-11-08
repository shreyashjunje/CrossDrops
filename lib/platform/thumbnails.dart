import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/media/thumb_ref.dart';
import '../core/media/thumbnail_queue.dart';

/// Makes the small previews shown next to files being picked, sent or
/// received (D-068). Platform code stays behind this interface (CLAUDE.md
/// hard rule 9).
abstract interface class ThumbnailLoader {
  /// Null when there is no preview: not an image or video, gone, or no
  /// permission. Never throws.
  Future<ImageProvider?> load(ThumbRef ref);
}

/// Photo-library items through photo_manager (the OS keeps those previews
/// cached); files through `crossdrop/thumbnail` (Android `loadThumbnail`,
/// iOS QuickLook), which returns the path of a small cached JPEG.
class PlatformThumbnailLoader implements ThumbnailLoader {
  PlatformThumbnailLoader({MethodChannel? channel, this.px = 192})
    : _channel = channel ?? const MethodChannel('crossdrop/thumbnail');

  final MethodChannel _channel;

  /// Edge of the preview in pixels: a 48-point tile on a 3x screen, about.
  final int px;

  /// Photo access, checked again at most every 30 s while it is missing
  /// (the user may allow it meanwhile).
  bool _libraryReadable = false;
  DateTime? _libraryCheckedAt;

  @override
  Future<ImageProvider?> load(ThumbRef ref) async {
    try {
      return switch (ref) {
        LibraryThumb(:final assetId) => await _library(assetId),
        FileThumb() => await _file(ref),
      };
    } on Object {
      return null;
    }
  }

  Future<ImageProvider?> _library(String id) async {
    // Never ask for photo access just to draw a preview: a receiving
    // iPhone may only have "add photos" access.
    if (!await _canReadLibrary()) return null;
    final asset = await AssetEntity.fromId(id);
    final bytes = await asset?.thumbnailDataWithSize(
      ThumbnailSize.square(px),
      quality: 80,
    );
    return bytes == null ? null : MemoryImage(bytes);
  }

  Future<bool> _canReadLibrary() async {
    if (_libraryReadable) return true;
    final now = DateTime.now();
    final at = _libraryCheckedAt;
    if (at != null && now.difference(at) < const Duration(seconds: 30)) {
      return false;
    }
    _libraryCheckedAt = now;
    final state = await PhotoManager.getPermissionState(
      requestOption: const PermissionRequestOption(),
    );
    return _libraryReadable = state.hasAccess;
  }

  Future<ImageProvider?> _file(FileThumb ref) async {
    final path = await _channel.invokeMethod<String>('thumbnail', {
      'ref': ref.ref,
      'px': px,
      'kind': ref.kind,
    });
    return path == null ? null : FileImage(File(path));
  }
}

/// Previews for the whole app: at most three made at once, the newest
/// request first (the rows on screen), and the last 600 kept (D-068).
class ThumbnailService {
  ThumbnailService(ThumbnailLoader loader)
    : _queue = ThumbnailQueue<ThumbRef, ImageProvider>(
        loader.load,
        parallel: 3,
        capacity: 600,
      );

  final ThumbnailQueue<ThumbRef, ImageProvider> _queue;

  /// A preview that is ready, so a row built again shows it at once.
  ImageProvider? cached(ThumbRef ref) => _queue.cached(ref);

  bool has(ThumbRef ref) => _queue.has(ref);

  Future<ImageProvider?> load(ThumbRef ref) => _queue.load(ref);

  /// The row left the screen before its preview started.
  void cancel(ThumbRef ref) => _queue.cancel(ref);
}
