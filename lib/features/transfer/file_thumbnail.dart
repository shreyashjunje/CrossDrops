import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/media_providers.dart';
import '../../app/tokens.dart';
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
    final c = context.cd;
    final s = widget.size;
    final image = _image;
    final placeholder = ColoredBox(
      color: c.surface3,
      child: Icon(fileKindIcon(widget.kind), size: s * 0.45, color: c.text2),
    );
    return ExcludeSemantics(
      child: ClipRRect(
        // 12 for tiles, a little less for small list thumbnails.
        borderRadius: BorderRadius.circular((s * 0.2).clamp(6, 12)),
        child: SizedBox.square(
          dimension: s,
          child: image == null
              ? placeholder
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Image(
                      image: image,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      // A broken cache file shows the icon instead.
                      errorBuilder: (_, _, _) => placeholder,
                    ),
                    if (widget.kind == FileKind.video)
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: CdColors.dark.bg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              size: (s * 0.28).clamp(12, 18),
                              color: CdColors.dark.text,
                            ),
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
