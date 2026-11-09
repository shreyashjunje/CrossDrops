import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
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
        leading: IconButton(
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      bottomNavigationBar: _access == _Access.denied
          ? null
          : _AddBar(count: n, onAdd: n == 0 ? null : _done),
      body: switch (_access) {
        _Access.checking => const Center(child: CircularProgressIndicator()),
        _Access.denied => const _DeniedView(),
        _ => Column(
          children: [
            if (_access == _Access.limited) _LimitedBanner(onChanged: _reload),
            if (_loadError != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: NoticeCard(
                  tone: NoticeTone.danger,
                  icon: Icons.error_outline_rounded,
                  text: 'Could not load your photos. Pull down to try again.',
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
    final c = context.cd;
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
              ColoredBox(color: c.surface3)
            else
              Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
            if (video)
              Positioned(
                left: 5,
                bottom: 5,
                child: _Badge(_duration(asset.duration)),
              ),
            if (asset.isLivePhoto && !video)
              const Positioned(left: 5, bottom: 5, child: _Badge('Live')),
            if (order != null) ...[
              const ColoredBox(color: Color(0x400E1116)),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: c.accent, width: 3),
                ),
              ),
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$order',
                    textScaler: TextScaler.noScaling,
                    style: CdType.titleS.copyWith(
                      fontSize: 13,
                      color: c.onAccent,
                    ),
                  ),
                ),
              ),
            ] else
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0x590E1116),
                    border: Border.all(
                      color: const Color(0xFFEEF1F5),
                      width: 2,
                    ),
                  ),
                ),
              ),
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
      color: CdColors.dark.bg,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      child: Text(
        text,
        textScaler: TextScaler.noScaling,
        style: CdType.small.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: CdColors.dark.text,
        ),
      ),
    ),
  );
}

/// How many are picked, and Add.
class _AddBar extends StatelessWidget {
  const _AddBar({required this.count, required this.onAdd});

  final int count;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface1,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            CdSpace.gutter,
            12,
            CdSpace.gutter,
            12,
          ),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    count == 0
                        ? 'Tap photos to choose them'
                        : '$count selected',
                    style: CdType.titleS.copyWith(
                      fontSize: 15,
                      color: count == 0 ? c.text2 : c.text,
                    ),
                  ),
                ),
              ),
              FilledButton(
                onPressed: onAdd,
                child: Text(count == 0 ? 'Add' : 'Add $count'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// iOS "Limited" or Android 14 "Selected photos" access.
class _LimitedBanner extends StatelessWidget {
  const _LimitedBanner({required this.onChanged});
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(CdSpace.gutter, 4, CdSpace.gutter, 12),
    child: NoticeCard(
      icon: Icons.photo_library_outlined,
      text: 'CrossDrop can see only the photos you allowed.',
      action: Wrap(
        spacing: 8,
        children: [
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

class _DeniedView extends StatelessWidget {
  const _DeniedView();

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CdSpace.gutter,
        48,
        CdSpace.gutter,
        24,
      ),
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(CdRadius.card),
              border: Border.all(color: c.line),
            ),
            child: Icon(Icons.lock_outline_rounded, size: 32, color: c.text2),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'CrossDrop can\u2019t see your photos',
          textAlign: TextAlign.center,
          style: CdType.h2.copyWith(color: c.text),
        ),
        const SizedBox(height: 12),
        Text(
          Platform.isIOS
              ? 'To send photos and videos, open Settings \u203a CrossDrop \u203a '
                    'Photos and choose "Full Access" or "Limited Access".'
              : 'To send photos and videos, open Settings and allow '
                    'CrossDrop to access photos and videos.',
          textAlign: TextAlign.center,
          style: CdType.bodyL.copyWith(color: c.text2),
        ),
        const SizedBox(height: 8),
        Text(
          'You can still send other files with "Files".',
          textAlign: TextAlign.center,
          style: CdType.bodyM.copyWith(color: c.text3),
        ),
        const SizedBox(height: 28),
        FilledButton(
          style: CdButtonStyles.wide,
          onPressed: PhotoManager.openSetting,
          child: const Text('Open Settings'),
        ),
      ],
    );
  }
}
