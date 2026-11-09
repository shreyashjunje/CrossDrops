import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
import '../../core/client/peer_check.dart';
import '../../core/media/format_plan.dart';
import '../../core/media/prepare.dart';
import '../../core/protocol/models.dart';
import '../nearby/nearby_screen.dart';
import '../transfer/transfer_format.dart';
import '../transfer/file_thumbnail.dart';
import '../transfer/transfer_screen.dart';
import 'gallery_picker_screen.dart';
import 'send_controller.dart';

/// Step 1 of sending: pick photos, videos and files, see what is selected
/// and how big it is, then Send, which asks for the phone to send to.
/// Layout per D-069: two sources when nothing is picked, then a grid of
/// previews with an Add tile and one Send button.
class SendScreen extends ConsumerWidget {
  const SendScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cd;
    final state = ref.watch(sendControllerProvider);
    final controller = ref.read(sendControllerProvider.notifier);
    final busy = state.isRunning;
    void addMedia() => _pickMedia(context, ref);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send'),
        actions: [
          if (state.picked.isNotEmpty && !busy)
            TextButton(
              onPressed: controller.clearFiles,
              style: TextButton.styleFrom(foregroundColor: c.text2),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  CdSpace.gutter,
                  8,
                  CdSpace.gutter,
                  CdSpace.l,
                ),
                children: [
                  if (busy) ...[
                    _Busy(
                      name: state.receiverName ?? 'another phone',
                      onTap: () => pushScreen<void>(
                        context,
                        Routes.transfer,
                        const TransferScreen(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (state.picked.isEmpty)
                    _Sources(
                      enabled: !busy,
                      onMedia: addMedia,
                      onFiles: controller.pickDocuments,
                    )
                  else
                    _PickedGrid(
                      picked: state.picked,
                      onAdd: busy
                          ? null
                          : () => _chooseSource(
                              context,
                              onMedia: addMedia,
                              onFiles: controller.pickDocuments,
                            ),
                      onRemove: busy ? null : controller.removePicked,
                    ),
                ],
              ),
            ),
            if (state.picked.isNotEmpty)
              _Footer(
                picked: state.picked,
                enabled: state.canSend,
                onSend: () => _chooseAndSend(context, ref),
              ),
          ],
        ),
      ),
    );
  }

  /// The Add tile: photos or files.
  Future<void> _chooseSource(
    BuildContext context, {
    required VoidCallback onMedia,
    required VoidCallback onFiles,
  }) => showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CdSpace.gutter,
          0,
          CdSpace.gutter,
          16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add more', style: CdType.h3.copyWith(color: sheet.cd.text)),
            const SizedBox(height: 16),
            _SourceTile(
              icon: Icons.photo_library_outlined,
              title: 'Photos & videos',
              subtitle: 'From your library',
              accent: true,
              onTap: () {
                Navigator.of(sheet).pop();
                onMedia();
              },
            ),
            const SizedBox(height: 12),
            _SourceTile(
              icon: Icons.insert_drive_file_outlined,
              title: 'Files',
              subtitle: 'PDFs, documents, anything',
              onTap: () {
                Navigator.of(sheet).pop();
                onFiles();
              },
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _pickMedia(BuildContext context, WidgetRef ref) async {
    final assets = await Navigator.of(context).push<List<LibraryAsset>>(
      MaterialPageRoute(builder: (_) => const GalleryPickerScreen()),
    );
    if (assets != null) {
      ref.read(sendControllerProvider.notifier).addMedia(assets);
    }
  }

  /// Step 2: choose the phone; then the transfer screen takes over.
  Future<void> _chooseAndSend(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final target = await pushScreen<ConnectTarget>(
      context,
      Routes.nearby,
      const NearbyScreen(),
    );
    if (target == null) return;
    unawaited(ref.read(sendControllerProvider.notifier).send(target));
    await navigator.pushReplacement(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: Routes.transfer),
        builder: (_) => const TransferScreen(),
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    child: GestureDetector(
      onTap: onTap,
      child: NoticeCard(
        tone: NoticeTone.accent,
        icon: Icons.sync_rounded,
        title: 'Sending to $name',
        text: 'One send at a time. Tap to see it.',
      ),
    ),
  );
}

/// Nothing picked yet: two sources, nothing else to decide.
class _Sources extends StatelessWidget {
  const _Sources({
    required this.enabled,
    required this.onMedia,
    required this.onFiles,
  });

  final bool enabled;
  final VoidCallback onMedia;
  final VoidCallback onFiles;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          'What do you want to send?',
          style: CdType.h1.copyWith(color: c.text),
        ),
        const SizedBox(height: 8),
        Text(
          'Sent in original quality, straight to the other phone. Nothing '
          'is compressed.',
          style: CdType.bodyL.copyWith(color: c.text2),
        ),
        const SizedBox(height: 28),
        _SourceTile(
          icon: Icons.photo_library_outlined,
          title: 'Photos & videos',
          subtitle: 'From your library, Live Photos included',
          accent: true,
          onTap: enabled ? onMedia : null,
        ),
        const SizedBox(height: 12),
        _SourceTile(
          icon: Icons.insert_drive_file_outlined,
          title: 'Files',
          subtitle: 'PDFs, documents, anything',
          onTap: enabled ? onFiles : null,
        ),
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return Material(
      color: c.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CdRadius.card),
        side: BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: accent ? c.accent : c.surface3,
                  borderRadius: BorderRadius.circular(CdRadius.button),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: accent ? c.onAccent : c.text,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: CdType.titleM.copyWith(
                        fontSize: 18,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: CdType.small.copyWith(color: c.text2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What is picked: a summary and a grid of previews with remove buttons.
class _PickedGrid extends StatelessWidget {
  const _PickedGrid({required this.picked, this.onAdd, this.onRemove});

  final List<PickedItem> picked;
  final VoidCallback? onAdd;
  final void Function(PickedItem item)? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              summarizePicked(picked),
              style: CdType.titleM.copyWith(fontSize: 17, color: c.text),
            ),
            const StatusBadge(
              label: 'Original quality',
              tone: BadgeTone.trusted,
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, box) {
            // Three across on phones, more on wide screens.
            final cols = (box.maxWidth / 130).floor().clamp(3, 8);
            const gap = 6.0;
            final size = (box.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                if (onAdd != null) _AddTile(size: size, onTap: onAdd!),
                for (final item in picked)
                  _PickedTile(item: item, size: size, onRemove: onRemove),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.size, required this.onTap});

  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return Semantics(
      container: true,
      button: true,
      label: 'Add more',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CdRadius.tile),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CdRadius.tile),
            border: Border.all(color: c.lineStrong, width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, color: c.text2),
              const SizedBox(height: 4),
              Text('Add', style: CdType.small.copyWith(color: c.text2)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickedTile extends StatelessWidget {
  const _PickedTile({required this.item, required this.size, this.onRemove});

  final PickedItem item;
  final double size;
  final void Function(PickedItem item)? onRemove;

  @override
  Widget build(BuildContext context) {
    final (kind, fileSize, live) = switch (item) {
      PickedAsset(:final asset) => (asset.kind, null, asset.isLivePhoto),
      PickedFile(:final kind, :final size) => (kind, size, false),
    };
    final what = switch (kind) {
      FileKind.photo => live ? 'Live Photo' : 'Photo',
      FileKind.video => 'Video',
      _ => 'File',
    };
    final label = [
      what,
      item.label,
      if (fileSize != null) formatSize(fileSize),
    ].join(', ');
    // Badges sit on the photo, so they use the dark tokens in both themes.
    const ink = CdColors.dark;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Semantics(
            container: true,
            label: label,
            child: FileThumbnail(thumb: item.thumb, kind: kind, size: size),
          ),
          if (live)
            Positioned(
              left: 6,
              bottom: 6,
              child: ExcludeSemantics(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: ink.bg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      'Live',
                      style: CdType.overline.copyWith(
                        letterSpacing: 0,
                        color: ink.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (onRemove != null)
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: 'Remove ${item.label}',
                onPressed: () => onRemove!(item),
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: EdgeInsets.zero,
                ),
                icon: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: ink.bg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close_rounded, size: 14, color: ink.text),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.picked,
    required this.enabled,
    required this.onSend,
  });

  final List<PickedItem> picked;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final n = picked.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CdSpace.gutter,
          12,
          CdSpace.gutter,
          16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (picked.any(_sizeUnknown)) ...[
              Text(
                'The full size is shown when sending starts.',
                style: CdType.small.copyWith(color: c.text2),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              onPressed: enabled ? onSend : null,
              style: CdButtonStyles.wide,
              icon: const Icon(Icons.north_east_rounded),
              label: Text(n == 1 ? 'Send 1 item' : 'Send $n items'),
            ),
          ],
        ),
      ),
    );
  }

  static bool _sizeUnknown(PickedItem p) => switch (p) {
    PickedAsset() => true,
    PickedFile(:final size) => size == null,
  };
}

/// "2 photos, 1 video, 3 files · at least 12.4 MB": "at least" while
/// some sizes are only known once the files are prepared.
String summarizePicked(List<PickedItem> picked) {
  var photos = 0, videos = 0, files = 0, bytes = 0;
  var unknown = false;
  for (final p in picked) {
    switch (p) {
      case PickedAsset(:final asset) when asset.kind == FileKind.video:
        videos++;
        unknown = true;
      case PickedAsset():
        photos++;
        unknown = true;
      case PickedFile(:final size):
        files++;
        if (size == null) unknown = true;
        bytes += size ?? 0;
    }
  }
  String n(int c, String one, String many) => '$c ${c == 1 ? one : many}';
  final counts = [
    if (photos > 0) n(photos, 'photo', 'photos'),
    if (videos > 0) n(videos, 'video', 'videos'),
    if (files > 0) n(files, 'file', 'files'),
  ].join(', ');
  if (bytes == 0) return counts;
  return '$counts · ${unknown ? 'at least ' : ''}${formatSize(bytes)}';
}
