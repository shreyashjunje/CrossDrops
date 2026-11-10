import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
import '../../core/usb_import/camera_roll.dart';
import '../../core/usb_import/import_runner.dart';
import '../../core/media/thumbnail_queue.dart';
import '../hotspot/numbered_steps.dart';
import '../transfer/transfer_format.dart';
import 'usb_import_controller.dart';

/// Import photos and videos from an iPhone plugged in by cable (Android,
/// D-067). The iPhone's DCIM folders are shown as one gallery, newest
/// first, grouped by day.
class UsbImportScreen extends ConsumerWidget {
  const UsbImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(usbImportControllerProvider);
    final c = ref.read(usbImportControllerProvider.notifier);
    return PopScope(
      canPop: s.phase != UsbImportPhase.importing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmStop(context, c);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            s.device == null ? 'Import from iPhone' : 'From ${s.device!.name}',
          ),
          actions: [if (s.showsGrid) _Menu(state: s, controller: c)],
        ),
        body: SafeArea(
          child: switch (s.phase) {
            UsbImportPhase.noDevice => const _HowToConnect(),
            UsbImportPhase.connecting => const _Waiting(
              'Connecting to the iPhone...',
            ),
            UsbImportPhase.locked => const _Waiting(
              'Unlock your iPhone. If it asks "Allow this device to access '
              'photos and videos?", tap Allow.',
            ),
            UsbImportPhase.permissionDenied => _Problem(
              text:
                  'CrossDrop needs access to the iPhone. Tap Try again and '
                  'then OK.',
              onRetry: c.connect,
            ),
            UsbImportPhase.busy => _Problem(
              text:
                  'Another app is using the iPhone, often Files or a '
                  'gallery. Close it, unplug the iPhone, plug it in again '
                  'and tap Try again.',
              onRetry: c.connect,
            ),
            UsbImportPhase.failed => _Problem(
              text:
                  'The iPhone stopped answering. Unlock it, check the '
                  'cable and tap Try again.',
              onRetry: c.connect,
            ),
            UsbImportPhase.loading ||
            UsbImportPhase.ready => _Gallery(state: s, controller: c),
            UsbImportPhase.importing => _Copying(
              progress: s.progress,
              items: s.selectedItems,
              thumbs: c.thumbnails,
              onStop: () => _confirmStop(context, c),
            ),
            UsbImportPhase.done => _Summary(
              summary: s.summary!,
              onBack: c.backToPhotos,
              onDone: () => Navigator.of(context).pop(),
            ),
          },
        ),
      ),
    );
  }

  static Future<void> _confirmStop(
    BuildContext context,
    UsbImportController c,
  ) async {
    final stop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop copying?'),
        content: const Text(
          'What is already copied stays in your gallery. The file being '
          'copied now is removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep copying'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (stop == true) c.cancelImport();
  }
}

class _Menu extends StatelessWidget {
  const _Menu({required this.state, required this.controller});

  final UsbImportState state;
  final UsbImportController controller;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Options',
      onSelected: (v) => switch (v) {
        'all' => controller.selectNotImported(),
        'none' => controller.clearSelection(),
        'live' => controller.setIncludeLiveVideo(!state.includeLiveVideo),
        'orig' => controller.setIncludeOriginals(!state.includeOriginals),
        _ => null,
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'all', child: Text('Select all shown')),
        const PopupMenuItem(value: 'none', child: Text('Clear selection')),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          value: 'live',
          checked: state.includeLiveVideo,
          child: const Text('Also copy Live Photo videos'),
        ),
        CheckedPopupMenuItem(
          value: 'orig',
          checked: state.includeOriginals,
          child: const Text('Also copy unedited originals'),
        ),
      ],
    );
  }
}

class _HowToConnect extends StatelessWidget {
  const _HowToConnect();

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return ListView(
      padding: const EdgeInsets.fromLTRB(CdSpace.gutter, 8, CdSpace.gutter, 24),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(CdRadius.card),
            ),
            child: Icon(Icons.cable_rounded, size: 34, color: c.accentInk),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Connect the iPhone with a cable',
          style: CdType.h2.copyWith(color: c.text),
        ),
        const SizedBox(height: 16),
        const NumberedSteps(
          steps: [
            'Use a USB-C to USB-C cable, or Lightning to USB-C for older '
                'iPhones.',
            'Unlock the iPhone.',
            'If the iPhone asks to allow access to photos, tap Allow.',
            'Nothing happens? Pull down the notifications on this phone, tap '
                'the USB notification and choose "USB controlled by: This '
                'device".',
          ],
        ),
        const SizedBox(height: 12),
        const NoticeCard(
          icon: Icons.high_quality_outlined,
          text:
              'To get the exact original files, on the iPhone open '
              'Settings > Apps > Photos > Transfer to Mac or PC and choose '
              '"Keep Originals". "Automatic" converts HEIC photos to JPEG, '
              'which changes the files.',
        ),
        const SizedBox(height: 16),
        Text(
          'Photos go to Pictures/CrossDrop and videos to Movies/CrossDrop, '
          'so your gallery shows them.',
          style: CdType.small.copyWith(color: c.text3),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(CdSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 48,
            child: CircularProgressIndicator(strokeWidth: 4),
          ),
          const SizedBox(height: 24),
          Semantics(
            liveRegion: true,
            child: NoticeCard(
              tone: NoticeTone.warning,
              icon: Icons.phone_iphone_rounded,
              text: text,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Problem extends StatelessWidget {
  const _Problem({required this.text, required this.onRetry});
  final String text;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CdSpace.gutter,
        32,
        CdSpace.gutter,
        24,
      ),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: c.dangerSoft,
              borderRadius: BorderRadius.circular(CdRadius.card),
              border: Border.all(color: c.dangerLine),
            ),
            child: Icon(Icons.error_outline_rounded, size: 34, color: c.danger),
          ),
        ),
        const SizedBox(height: 20),
        Text(text, style: CdType.bodyL.copyWith(color: c.text)),
        const SizedBox(height: 24),
        FilledButton(
          style: CdButtonStyles.wide,
          onPressed: () => unawaited(onRetry()),
          child: const Text('Try again'),
        ),
      ],
    );
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery({required this.state, required this.controller});

  final UsbImportState state;
  final UsbImportController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final visible = state.visible;
    final days = groupByDay(visible);
    final plan = state.plan;
    final n = state.selected.length;
    final now = DateTime.now();
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: CdSpace.gutter,
            vertical: 8,
          ),
          child: Row(
            children: [
              for (final f in RollFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_filterName(f)),
                    selected: state.filter == f,
                    showCheckmark: false,
                    selectedColor: c.text,
                    backgroundColor: c.bg,
                    labelStyle: CdType.titleS.copyWith(
                      color: state.filter == f ? c.bg : c.text,
                    ),
                    side: BorderSide(
                      color: state.filter == f ? c.text : c.lineStrong,
                    ),
                    onSelected: (_) => controller.setFilter(f),
                  ),
                ),
            ],
          ),
        ),
        if (state.phase == UsbImportPhase.loading) ...[
          const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Reading the iPhone: ${state.seen} files so far. You can '
              'start choosing.',
              style: CdType.small.copyWith(color: c.text2),
            ),
          ),
        ],
        if (state.space case final space?)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CdSpace.gutter,
              vertical: 8,
            ),
            child: NoticeCard(
              tone: NoticeTone.warning,
              icon: Icons.sd_storage_outlined,
              text:
                  'Not enough space on this phone: this needs '
                  '${formatSize(space.needed)}, ${formatSize(space.free)} is '
                  'free. Choose fewer items.',
              action: TextButton(
                onPressed: controller.clearSelection,
                child: const Text('Clear'),
              ),
            ),
          ),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(
                    state.phase == UsbImportPhase.loading
                        ? 'Looking for photos...'
                        : 'Nothing here.',
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    for (final day in days) ...[
                      SliverToBoxAdapter(
                        child: _DayHeader(
                          title: day.day == null
                              ? 'Unknown date'
                              : formatDay(day.day!, now),
                          count: day.items.length,
                          allSelected: day.items.every(
                            (i) => state.selected.contains(i.key),
                          ),
                          onToggle: () => controller.toggleAll(day.items),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 120,
                                mainAxisSpacing: 2,
                                crossAxisSpacing: 2,
                              ),
                          itemCount: day.items.length,
                          itemBuilder: (context, i) {
                            final item = day.items[i];
                            return _Tile(
                              key: ValueKey(item.key),
                              item: item,
                              thumbs: controller.thumbnails,
                              selected: state.selected.contains(item.key),
                              imported: state.imported.contains(item.key),
                              onTap: () => controller.toggle(item.key),
                            );
                          },
                        ),
                      ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface1,
            border: Border(top: BorderSide(color: c.line)),
          ),
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
                  child: Text(
                    n == 0
                        ? 'Tap photos to choose them'
                        : '$n selected · ${formatSize(plannedBytes(plan))}',
                  ),
                ),
                FilledButton.icon(
                  onPressed: n == 0
                      ? null
                      : () => unawaited(controller.startImport()),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Copy to this phone'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _filterName(RollFilter f) => switch (f) {
    RollFilter.all => 'All',
    RollFilter.photos => 'Photos',
    RollFilter.videos => 'Videos',
    RollFilter.screenshots => 'Screenshots',
  };
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.title,
    required this.count,
    required this.allSelected,
    required this.onToggle,
  });

  final String title;
  final int count;
  final bool allSelected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(CdSpace.gutter, 16, 12, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '$title · $count',
            style: CdType.titleS.copyWith(color: context.cd.text),
          ),
        ),
        TextButton(
          onPressed: onToggle,
          child: Text(allSelected ? 'Deselect' : 'Select'),
        ),
      ],
    ),
  );
}

/// The iPhone's own preview of [item], from [thumbs]; the kind's icon
/// while it loads or when there is none. Gives up its place in the queue
/// when it leaves the screen.
class _CameraThumb extends StatefulWidget {
  const _CameraThumb({super.key, required this.item, required this.thumbs});

  final RollItem item;
  final ThumbnailQueue<int, String>? thumbs;

  @override
  State<_CameraThumb> createState() => _CameraThumbState();
}

class _CameraThumbState extends State<_CameraThumb> {
  String? _path;
  bool _asked = false;

  int get _handle => widget.item.primary.handle;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_CameraThumb old) {
    super.didUpdateWidget(old);
    if (old.thumbs != widget.thumbs ||
        old.item.primary.handle != widget.item.primary.handle) {
      old.thumbs?.cancel(old.item.primary.handle);
      _path = null;
      _asked = false;
      _load();
    }
  }

  void _load() {
    final q = widget.thumbs;
    if (q == null || _asked) return;
    _asked = true;
    final handle = _handle;
    if (q.has(handle)) {
      _path = q.cached(handle);
      return;
    }
    unawaited(
      q.load(handle).then((p) {
        if (mounted && p != null && handle == _handle) {
          setState(() => _path = p);
        }
      }),
    );
  }

  @override
  void dispose() {
    widget.thumbs?.cancel(_handle);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final path = _path;
    if (path == null) {
      return ColoredBox(
        color: c.surface3,
        child: Icon(
          widget.item.kind == RollKind.video
              ? Icons.videocam_outlined
              : Icons.image_outlined,
          color: c.text3,
        ),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: 256,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => ColoredBox(color: c.surface3),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.item,
    required this.thumbs,
    required this.selected,
    required this.imported,
    required this.onTap,
  });

  final RollItem item;
  final ThumbnailQueue<int, String>? thumbs;
  final bool selected;
  final bool imported;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final t = item.taken;
    final label = [
      item.kind == RollKind.video ? 'Video' : 'Photo',
      if (item.isScreenshot) 'screenshot',
      if (item.isLive) 'Live',
      if (item.isEdited) 'edited',
      if (t != null) formatDay(t, DateTime.now()),
      if (imported) 'copied',
      if (selected) 'selected',
    ].join(', ');
    return Semantics(
      selected: selected,
      label: label,
      button: true,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _CameraThumb(item: item, thumbs: thumbs),
            if (item.kind == RollKind.video)
              Positioned(
                right: 5,
                bottom: 5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: CdColors.dark.bg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.videocam,
                      color: CdColors.dark.text,
                      size: 16,
                    ),
                  ),
                ),
              ),
            if (item.isLive)
              const Positioned(left: 5, bottom: 5, child: _Badge('Live')),
            if (imported)
              Positioned(
                left: 5,
                top: 5,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: CdColors.dark.bg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.download_done_rounded,
                    color: CdColors.dark.text,
                    size: 14,
                  ),
                ),
              ),
            if (selected) ...[
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
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_rounded, color: c.onAccent, size: 16),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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

/// While copying: the photo being copied, the percentage, and a strip of
/// every item in the copy, ticked as each one is done.
class _Copying extends StatefulWidget {
  const _Copying({
    required this.progress,
    required this.items,
    required this.thumbs,
    required this.onStop,
  });

  final ImportProgress? progress;

  /// The items being copied, in copy order.
  final List<RollItem> items;
  final ThumbnailQueue<int, String>? thumbs;
  final VoidCallback onStop;

  @override
  State<_Copying> createState() => _CopyingState();
}

class _CopyingState extends State<_Copying> {
  static const _strip = 64.0;
  static const _gap = 6.0;
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_Copying old) {
    super.didUpdateWidget(old);
    final key = widget.progress?.currentItem;
    if (key == null || key == old.progress?.currentItem) return;
    final i = widget.items.indexWhere((it) => it.key == key);
    if (i < 0) return;
    // Keep the item being copied in view, a little in from the left.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = ((i - 1) * (_strip + _gap)).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(target);
      } else {
        unawaited(
          _scroll.animateTo(
            target,
            duration: CdMotion.base,
            curve: Curves.easeOut,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The item being copied; between files, the next one not done yet.
  RollItem? _current() {
    final items = widget.items;
    if (items.isEmpty) return null;
    final p = widget.progress;
    final key = p?.currentItem;
    final copied = p?.copiedItems ?? const <String>{};
    return items.where((i) => i.key == key).firstOrNull ??
        items.where((i) => !copied.contains(i.key)).firstOrNull ??
        items.last;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final p = widget.progress;
    final percent = p == null ? 0 : (p.fraction * 100).floor();
    final current = _current();
    final copied = p?.copiedItems ?? const <String>{};
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(CdSpace.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                children: [
                  if (current != null)
                    Center(
                      child: ExcludeSemantics(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(CdRadius.button),
                          child: SizedBox.square(
                            dimension: 168,
                            child: _CameraThumb(
                              key: ValueKey(current.key),
                              item: current,
                              thumbs: widget.thumbs,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  ..._details(c, p, percent),
                  if (widget.items.length > 1) ...[
                    const SizedBox(height: 20),
                    ExcludeSemantics(
                      child: SizedBox(
                        height: _strip,
                        child: ListView.separated(
                          controller: _scroll,
                          scrollDirection: Axis.horizontal,
                          itemCount: widget.items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(width: _gap),
                          itemBuilder: (context, i) {
                            final item = widget.items[i];
                            return _StripTile(
                              key: ValueKey(item.key),
                              item: item,
                              thumbs: widget.thumbs,
                              size: _strip,
                              copied: copied.contains(item.key),
                              current: item.key == current?.key,
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const NoticeCard(
                    tone: NoticeTone.accent,
                    icon: Icons.cable_rounded,
                    text: 'Keep the cable plugged in and the iPhone unlocked.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: CdButtonStyles.danger(context).merge(CdButtonStyles.wide),
              onPressed: widget.onStop,
              child: const Text('Stop'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _details(CdColors c, ImportProgress? p, int percent) => [
    ExcludeSemantics(
      child: Text('$percent%', style: CdType.displayXL.copyWith(color: c.text)),
    ),
    const SizedBox(height: 6),
    Semantics(
      liveRegion: true,
      child: Text(
        p == null
            ? 'Starting...'
            : 'Copying ${p.filesDone + (p.filesDone < p.filesTotal ? 1 : 0)} '
                  'of ${p.filesTotal}',
        style: CdType.titleM.copyWith(fontSize: 17, color: c.text),
      ),
    ),
    const SizedBox(height: 18),
    if (p == null)
      const LinearProgressIndicator(minHeight: 10)
    else
      CdProgressBar(value: p.fraction, semanticLabel: 'Copy progress'),
    const SizedBox(height: 8),
    if (p != null)
      Text(
        '${formatSize(p.bytesDone)} of ${formatSize(p.bytesTotal)}',
        style: CdType.small.copyWith(color: c.text2),
      ),
  ];
}

/// One item in the copy strip: ticked when done, outlined while copying.
class _StripTile extends StatelessWidget {
  const _StripTile({
    super.key,
    required this.item,
    required this.thumbs,
    required this.size,
    required this.copied,
    required this.current,
  });

  final RollItem item;
  final ThumbnailQueue<int, String>? thumbs;
  final double size;
  final bool copied;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _CameraThumb(item: item, thumbs: thumbs),
            if (copied) ...[
              const ColoredBox(color: Color(0x660E1116)),
              Center(
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_rounded, color: c.onAccent, size: 16),
                ),
              ),
            ],
            if (current)
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.accent, width: 3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.summary,
    required this.onBack,
    required this.onDone,
  });

  final ImportSummary summary;
  final Future<void> Function() onBack;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final s = summary;
    final ok = s.stop == null && s.failedFiles == 0;
    final why = switch (s.stop) {
      ImportStop.cancelled => 'You stopped the copy.',
      ImportStop.disconnected =>
        'The iPhone was unplugged or locked. Plug it in, unlock it and '
            'copy the rest.',
      ImportStop.noSpace => 'This phone is out of space.',
      ImportStop.deviceError => 'The iPhone stopped answering.',
      null => null,
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CdSpace.gutter,
        40,
        CdSpace.gutter,
        24,
      ),
      children: [
        Center(
          child: ExcludeSemantics(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: ok ? c.accent : c.warningSoft,
                shape: BoxShape.circle,
                border: ok ? null : Border.all(color: c.warningLine),
              ),
              child: Icon(
                ok ? Icons.check_rounded : Icons.info_outline_rounded,
                size: 44,
                color: ok ? c.onAccent : c.warningInk,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Copied ${s.copiedFiles} '
          '${s.copiedFiles == 1 ? 'file' : 'files'} '
          '(${formatSize(s.bytes)})',
          style: CdType.h1.copyWith(color: c.text),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Photos are in Pictures/CrossDrop and videos in Movies/CrossDrop.',
          textAlign: TextAlign.center,
          style: CdType.bodyM.copyWith(color: c.text2),
        ),
        if (s.failedFiles > 0) ...[
          const SizedBox(height: 12),
          NoticeCard(
            tone: NoticeTone.warning,
            icon: Icons.warning_amber_rounded,
            text:
                '${s.failedFiles} could not be copied. They stay selected; '
                'try again.',
          ),
        ],
        if (why != null) ...[
          const SizedBox(height: 12),
          NoticeCard(
            tone: s.stop == ImportStop.cancelled
                ? NoticeTone.neutral
                : NoticeTone.danger,
            icon: Icons.info_outline_rounded,
            text: why,
          ),
        ],
        const SizedBox(height: 28),
        FilledButton(
          style: CdButtonStyles.wide,
          onPressed: () => unawaited(onBack()),
          child: const Text('Back to photos'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: onDone, child: const Text('Done')),
      ],
    );
  }
}
