import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/media/format_plan.dart';
import '../../core/media/thumbnail_queue.dart';
import '../../core/protocol/models.dart';
import '../transfer/transfer_format.dart';

/// Picks photos and videos from the library (photo_manager). Returns the
/// chosen items, or null if the user backed out. Only ids and names leave
/// this screen; files are read later, as originals (D-038).
class GalleryPickerScreen extends StatefulWidget {
  const GalleryPickerScreen({super.key});

  @override
  State<GalleryPickerScreen> createState() => _GalleryPickerScreenState();
}

enum _Access { checking, full, limited, denied }

class _GalleryPickerScreenState extends State<GalleryPickerScreen>
    with WidgetsBindingObserver {
  static const _pageSize = 120;

  /// The first page is smaller, so the grid shows sooner.
  static const _firstPageSize = 60;

  _Access _access = _Access.checking;
  List<AssetPathEntity> _albums = const [];
  AssetPathEntity? _album;
  final List<AssetEntity> _assets = [];
  int _total = 0;
  bool _loading = false;
  Object? _loadError;

  /// Selected ids, in the order tapped.
  final LinkedHashMap<String, AssetEntity> _selected = LinkedHashMap();

  /// Grid previews: six at a time, the newest request first (the tiles on
  /// screen), tiles scrolled past dropped before they start (D-068).
  late final _thumbs = ThumbnailQueue<String, Uint8List>(
    _thumbnail,
    parallel: 6,
    capacity: 600,
  );
  final Map<String, AssetEntity> _byId = {};
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    PhotoManager.addChangeCallback(_onLibraryChanged);
    unawaited(_requestAccess());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PhotoManager.removeChangeCallback(_onLibraryChanged);
    unawaited(PhotoManager.stopChangeNotify());
    _thumbs.close();
    _scroll.dispose();
    super.dispose();
  }

  Future<Uint8List?> _thumbnail(String id) async {
    final a = _byId[id];
    if (a == null) return null;
    return a.thumbnailDataWithSize(
      const ThumbnailSize.square(200),
      quality: 75,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Settings: the user may have changed photo access.
    if (state == AppLifecycleState.resumed && _access != _Access.full) {
      unawaited(_requestAccess());
    }
  }

  void _onLibraryChanged(MethodCall _) {
    // Limited selection changed, or photos were added or deleted.
    if (mounted) unawaited(_reload());
  }

  Future<void> _requestAccess() async {
    final PermissionState ps;
    try {
      ps = await PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(
          androidPermission: AndroidPermission(
            type: RequestType.common,
            // Without it Android strips GPS from what we read (D-037).
            mediaLocation: true,
          ),
        ),
      );
    } on PlatformException {
      if (mounted) setState(() => _access = _Access.denied);
      return;
    }
    if (!mounted) return;
    final access = switch (ps) {
      PermissionState.authorized => _Access.full,
      PermissionState.limited => _Access.limited,
      _ => _Access.denied,
    };
    final changed = access != _access;
    setState(() => _access = access);
    if (access != _Access.denied && (changed || _albums.isEmpty)) {
      await PhotoManager.startChangeNotify();
      await _reload();
    }
  }

  static FilterOptionGroup get _filter => FilterOptionGroup(
    orders: [const OrderOption(type: OrderOptionType.createDate)],
  );

  /// "All photos" first, so the grid fills at once; the other albums (one
  /// count query each) load after it, for the album menu.
  Future<void> _reload() async {
    try {
      if (_album == null || _album!.isAll) {
        final all = await PhotoManager.getAssetPathList(
          type: RequestType.common,
          onlyAll: true,
          filterOption: _filter,
        );
        if (!mounted) return;
        setState(() {
          _album = all.firstOrNull;
          if (_albums.isEmpty) _albums = all;
        });
        await _loadFirstPage();
      }
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        filterOption: _filter,
      );
      if (!mounted) return;
      final keep = albums.where((a) => a.id == _album?.id).firstOrNull;
      final changed = keep == null;
      setState(() {
        _albums = albums;
        _album = keep ?? albums.firstOrNull;
      });
      if (changed) await _loadFirstPage();
    } on PlatformException catch (e) {
      if (mounted) setState(() => _loadError = e.code);
    }
  }

  Future<void> _loadFirstPage() async {
    final album = _album;
    _assets.clear();
    _total = album == null ? 0 : await album.assetCountAsync;
    if (!mounted) return;
    setState(() {});
    await _loadMore();
    // Drop selections that are gone (deleted, or no longer shared under
    // Limited access).
    if (!mounted || album == null) return;
    final ids = _selected.keys.toList();
    final still = await Future.wait(ids.map(AssetEntity.fromId));
    if (!mounted) return;
    setState(() {
      for (final (i, a) in still.indexed) {
        if (a == null) _selected.remove(ids[i]);
      }
    });
  }

  Future<void> _loadMore() async {
    final album = _album;
    if (album == null || _loading || _assets.length >= _total) return;
    _loading = true;
    try {
      // Ranges, not pages: the first one is smaller.
      final start = _assets.length;
      final size = start == 0 ? _firstPageSize : _pageSize;
      final page = await album.getAssetListRange(
        start: start,
        end: (start + size).clamp(0, _total),
      );
      if (!mounted || album != _album || _assets.length != start) return;
      setState(() {
        _assets.addAll(page);
        for (final a in page) {
          _byId[a.id] = a;
        }
        _loadError = null;
      });
    } on PlatformException catch (e) {
      if (mounted) setState(() => _loadError = e.code);
    } finally {
      _loading = false;
    }
    // The album changed while this page loaded: that request returned at
    // once, so load the new album's first page now.
    if (mounted && album != _album && _assets.isEmpty) unawaited(_loadMore());
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 1500) unawaited(_loadMore());
  }

  void _toggle(AssetEntity a) {
    setState(() {
      if (_selected.remove(a.id) == null) _selected[a.id] = a;
    });
  }

  void _done() {
    Navigator.of(context).pop([
      for (final a in _selected.values)
        LibraryAsset(
          id: a.id,
          kind: a.type == AssetType.video ? FileKind.video : FileKind.photo,
          // Android: the display name. iOS: looked up for the selection by
          // the Send screen (SendController.addMedia), not per tile.
          originalName: Platform.isAndroid && (a.title ?? '').isNotEmpty
              ? a.title
              : null,
          mime: a.mimeType,
          isLivePhoto: a.isLivePhoto,
          created: a.createDateTime.year > 1970 ? a.createDateTime : null,
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final n = _selected.length;
    return Scaffold(
      appBar: AppBar(
        title: _albums.length > 1
            ? DropdownButtonHideUnderline(
                child: DropdownButton<AssetPathEntity>(
                  value: _album,
                  isExpanded: true,
                  items: [
                    for (final a in _albums)
                      DropdownMenuItem(
                        value: a,
                        child: Text(
                          a.isAll ? 'All photos and videos' : a.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (a) {
                    setState(() => _album = a);
                    unawaited(_loadFirstPage());
                  },
                ),
              )
            : const Text('Photos and videos'),
        actions: [
          TextButton(
            onPressed: n == 0 ? null : _done,
            child: Text(n == 0 ? 'Add' : 'Add $n'),
          ),
        ],
      ),
      body: switch (_access) {
        _Access.checking => const Center(child: CircularProgressIndicator()),
        _Access.denied => const _DeniedView(),
        _ => Column(
          children: [
            if (_access == _Access.limited) _LimitedBanner(onChanged: _reload),
            if (_loadError != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Could not load your photos. Pull down to try again.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(child: _grid()),
          ],
        ),
      },
    );
  }

  Widget _grid() {
    final order = {for (final (i, id) in _selected.keys.indexed) id: i + 1};
    if (_album == null || (_total == 0 && !_loading)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _access == _Access.limited
                ? 'CrossDrop can see no photos yet. Tap "Select more" to '
                      'choose some.'
                : 'No photos or videos on this phone.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(2),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: _assets.length,
        itemBuilder: (context, i) {
          final a = _assets[i];
          return _Tile(
            key: ValueKey(a.id),
            asset: a,
            thumbs: _thumbs,
            order: order[a.id],
            onTap: () => _toggle(a),
          );
        },
      ),
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({
    super.key,
    required this.asset,
    required this.thumbs,
    required this.order,
    required this.onTap,
  });

  final AssetEntity asset;
  final ThumbnailQueue<String, Uint8List> thumbs;
  final int? order;
  final VoidCallback onTap;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  Uint8List? _bytes;
  bool _waiting = false;

  @override
  void initState() {
    super.initState();
    final q = widget.thumbs;
    final id = widget.asset.id;
    if (q.has(id)) {
      _bytes = q.cached(id);
      return;
    }
    _waiting = true;
    q.load(id).then((b) {
      _waiting = false;
      if (mounted && b != null) setState(() => _bytes = b);
    });
  }

  @override
  void dispose() {
    // Scrolled past before its turn: never asked.
    if (_waiting) widget.thumbs.cancel(widget.asset.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = widget.asset;
    final order = widget.order;
    final onTap = widget.onTap;
    final bytes = _bytes;
    final video = asset.type == AssetType.video;
    final created = asset.createDateTime;
    // "Video, 0:42, Live, 3 Nov 2026, selected 2".
    final label = [
      video ? 'Video, ${_duration(asset.duration)}' : 'Photo',
      if (asset.isLivePhoto) 'Live',
      if (created.year > 1970) formatDay(created, DateTime.now()),
      if (order != null) 'selected $order',
    ].join(', ');
    return Semantics(
      selected: order != null,
      label: label,
      button: true,
      // The children's semantics are replaced, so the tap is declared here.
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bytes == null)
              ColoredBox(color: theme.colorScheme.surfaceContainerHighest)
            else
              Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
            if (video)
              Positioned(
                right: 4,
                bottom: 4,
                child: _Badge(_duration(asset.duration)),
              ),
            if (asset.isLivePhoto)
              const Positioned(left: 4, bottom: 4, child: _Badge('LIVE')),
            if (order != null) ...[
              ColoredBox(color: Colors.black.withValues(alpha: 0.25)),
              Positioned(
                right: 4,
                top: 4,
                child: CircleAvatar(
                  radius: 12,
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(
                    '$order',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _duration(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return m >= 60
        ? '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:$s'
        : '$m:$s';
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    ),
  );
}

/// iOS "Limited" or Android 14 "Selected photos" access.
class _LimitedBanner extends StatelessWidget {
  const _LimitedBanner({required this.onChanged});
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'CrossDrop can see only the photos you allowed.',
                style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
              ),
            ),
            TextButton(
              onPressed: () async {
                await PhotoManager.presentLimited(type: RequestType.common);
                await onChanged();
              },
              child: const Text('Select more'),
            ),
            TextButton(
              onPressed: PhotoManager.openSetting,
              child: const Text('Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeniedView extends StatelessWidget {
  const _DeniedView();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_library_outlined, size: 48),
          const SizedBox(height: 16),
          Text(
            'CrossDrop has no access to your photos',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            Platform.isIOS
                ? 'To send photos and videos, open Settings > CrossDrop > '
                      'Photos and choose "Full Access" or "Limited Access". '
                      'You can still send other files with "Files".'
                : 'To send photos and videos, open Settings and allow '
                      'CrossDrop to access photos and videos. You can still '
                      'send other files with "Files".',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: PhotoManager.openSetting,
            child: const Text('Open Settings'),
          ),
        ],
      ),
    ),
  );
}
