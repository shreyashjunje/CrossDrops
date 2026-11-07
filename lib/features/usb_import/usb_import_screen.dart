import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/usb_import/camera_roll.dart';
import '../../core/usb_import/import_runner.dart';
import '../../core/usb_import/thumbnail_queue.dart';
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
    final theme = Theme.of(context);
    Widget step(int n, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 13, child: Text('$n')),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.cable, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'Connect the iPhone with a cable',
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        step(
          1,
          'Use a USB-C to USB-C cable, or Lightning to USB-C for older '
          'iPhones.',
        ),
        step(2, 'Unlock the iPhone.'),
        step(3, 'If the iPhone asks to allow access to photos, tap Allow.'),
        step(
          4,
          'Nothing happens? Pull down the notifications on this phone, tap '
          'the USB notification and choose "USB controlled by: This '
          'device".',
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'To get the exact original files, on the iPhone open '
              'Settings > Apps > Photos > Transfer to Mac or PC and choose '
              '"Keep Originals". "Automatic" converts HEIC photos to JPEG, '
              'which changes the files.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Photos go to Pictures/CrossDrop and videos to Movies/CrossDrop, '
          'so your gallery shows them.',
          style: theme.textTheme.bodySmall,
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
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(text, textAlign: TextAlign.center),
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
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => unawaited(onRetry()),
            child: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

class _Gallery extends StatelessWidget {
  const _Gallery({required this.state, required this.controller});

  final UsbImportState state;
  final UsbImportController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = state.visible;
    final days = groupByDay(visible);
    final plan = state.plan;
    final n = state.selected.length;
    final now = DateTime.now();
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              for (final f in RollFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_filterName(f)),
                    selected: state.filter == f,
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
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
        if (state.space case final space?)
          MaterialBanner(
            content: Text(
              'Not enough space on this phone: this needs '
              '${formatSize(space.needed)}, ${formatSize(space.free)} is '
              'free. Choose fewer items.',
            ),
            actions: [
              TextButton(
                onPressed: controller.clearSelection,
                child: const Text('Clear'),
              ),
            ],
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
        Material(
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
                  icon: const Icon(Icons.download),
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
    padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '$title · $count',
            style: Theme.of(context).textTheme.titleSmall,
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

class _Tile extends StatefulWidget {
  const _Tile({
    super.key,
    required this.item,
    required this.thumbs,
    required this.selected,
    required this.imported,
    required this.onTap,
  });

  final RollItem item;
  final ThumbnailQueue? thumbs;
  final bool selected;
  final bool imported;
  final VoidCallback onTap;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  String? _path;
  bool _asked = false;

  int get _handle => widget.item.primary.handle;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_Tile old) {
    super.didUpdateWidget(old);
    if (old.thumbs != widget.thumbs) {
      _asked = false;
      _load();
    }
  }

  void _load() {
    final q = widget.thumbs;
    if (q == null || _asked) return;
    _asked = true;
    if (q.has(_handle)) {
      _path = q.cached(_handle);
      return;
    }
    unawaited(
      q.load(_handle).then((p) {
        if (mounted && p != null) setState(() => _path = p);
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
    final theme = Theme.of(context);
    final item = widget.item;
    final t = item.taken;
    final label = [
      item.kind == RollKind.video ? 'Video' : 'Photo',
      if (item.isScreenshot) 'screenshot',
      if (item.isLive) 'Live',
      if (item.isEdited) 'edited',
      if (t != null) formatDay(t, DateTime.now()),
      if (widget.imported) 'copied',
      if (widget.selected) 'selected',
    ].join(', ');
    final path = _path;
    return Semantics(
      selected: widget.selected,
      label: label,
      button: true,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (path == null)
              ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  item.kind == RollKind.video
                      ? Icons.videocam_outlined
                      : Icons.image_outlined,
                  color: theme.colorScheme.outline,
                ),
              )
            else
              Image.file(
                File(path),
                fit: BoxFit.cover,
                cacheWidth: 256,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            if (item.kind == RollKind.video)
              const Positioned(
                right: 4,
                bottom: 4,
                child: Icon(Icons.videocam, color: Colors.white, size: 18),
              ),
            if (item.isLive)
              const Positioned(left: 4, bottom: 4, child: _Badge('LIVE')),
            if (widget.imported)
              const Positioned(
                left: 4,
                top: 4,
                child: Icon(Icons.check_circle, color: Colors.green, size: 20),
              ),
            if (widget.selected) ...[
              ColoredBox(color: Colors.black.withValues(alpha: 0.25)),
              Positioned(
                right: 4,
                top: 4,
                child: Icon(
                  Icons.check_circle,
                  color: theme.colorScheme.primary,
                  size: 24,
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

class _Copying extends StatelessWidget {
  const _Copying({required this.progress, required this.onStop});

  final ImportProgress? progress;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            p == null
                ? 'Starting...'
                : 'Copying ${p.filesDone + (p.filesDone < p.filesTotal ? 1 : 0)} '
                      'of ${p.filesTotal}',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          LinearProgressIndicator(value: p?.fraction),
          const SizedBox(height: 12),
          if (p != null)
            Text(
              '${formatSize(p.bytesDone)} of ${formatSize(p.bytesTotal)}',
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 24),
          Text(
            'Keep the cable plugged in and the iPhone unlocked.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          OutlinedButton(onPressed: onStop, child: const Text('Stop')),
        ],
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
    final theme = Theme.of(context);
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.info_outline,
            size: 56,
            color: ok ? Colors.green : theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Copied ${s.copiedFiles} '
            '${s.copiedFiles == 1 ? 'file' : 'files'} '
            '(${formatSize(s.bytes)})',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Photos are in Pictures/CrossDrop and videos in Movies/CrossDrop.',
            textAlign: TextAlign.center,
          ),
          if (s.failedFiles > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${s.failedFiles} could not be copied. They stay selected; '
              'try again.',
              textAlign: TextAlign.center,
            ),
          ],
          if (why != null) ...[
            const SizedBox(height: 8),
            Text(why, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => unawaited(onBack()),
            child: const Text('Back to photos'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onDone, child: const Text('Done')),
        ],
      ),
    );
  }
}
