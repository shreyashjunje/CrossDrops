import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/media_providers.dart';
import '../../core/media/thumb_ref.dart';
import '../../core/protocol/models.dart';
import '../../platform/thumbnails.dart';
import 'widgets.dart';

/// A rounded square preview of a photo, video or file, with the kind's
/// icon while it loads or when there is no preview (D-068). Videos get a
/// small play mark so they are told apart from photos.
class FileThumbnail extends ConsumerStatefulWidget {
  const FileThumbnail({
    super.key,
    required this.thumb,
    required this.kind,
    this.size = 48,
  });

  /// Null: show the icon only (nothing to preview yet).
  final ThumbRef? thumb;
  final String kind;
  final double size;

  @override
  ConsumerState<FileThumbnail> createState() => _FileThumbnailState();
}

class _FileThumbnailState extends ConsumerState<FileThumbnail> {
  ImageProvider? _image;
  ThumbRef? _loading;

  /// Read on the first preview and kept: `ref` may not be used in
  /// [dispose].
  ThumbnailService? _service;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(FileThumbnail old) {
    super.didUpdateWidget(old);
    if (old.thumb != widget.thumb) {
      _stop();
      _image = null;
      _start();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _start() {
    final ref = widget.thumb;
    if (ref == null) return;
    final service =
        _service ?? this.ref.read<ThumbnailService>(thumbnailServiceProvider);
    _service = service;
    if (service.has(ref)) {
      _image = service.cached(ref);
      return;
    }
    _loading = ref;
    service.load(ref).then((image) {
      if (!mounted || _loading != ref) return;
      _loading = null;
      if (image != null) setState(() => _image = image);
    });
  }

  /// A row that leaves the screen gives up its place in the queue.
  void _stop() {
    final ref = _loading;
    _loading = null;
    if (ref != null) _service?.cancel(ref);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = widget.size;
    final image = _image;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: s,
          child: image == null
              ? ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(
                    fileKindIcon(widget.kind),
                    size: s * 0.5,
                    color: scheme.onSurfaceVariant,
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Image(
                      image: image,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      // A broken cache file shows the icon instead.
                      errorBuilder: (_, _, _) => ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(fileKindIcon(widget.kind), size: s * 0.5),
                      ),
                    ),
                    if (widget.kind == FileKind.video)
                      Center(
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            color: Colors.black45,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.play_arrow,
                            size: s * 0.4,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
