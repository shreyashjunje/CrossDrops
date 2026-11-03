import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../core/client/peer_check.dart';
import '../../core/media/format_plan.dart';
import '../../core/media/prepare.dart';
import '../../core/protocol/models.dart';
import '../nearby/nearby_screen.dart';
import '../transfer/transfer_format.dart';
import '../transfer/transfer_screen.dart';
import '../transfer/widgets.dart';
import 'gallery_picker_screen.dart';
import 'send_controller.dart';

/// Step 1 of sending: pick photos, videos and files, see what is selected
/// and how big it is, then Send, which asks for the phone to send to.
class SendScreen extends ConsumerWidget {
  const SendScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sendControllerProvider);
    final controller = ref.read(sendControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send'),
        actions: [
          if (state.picked.isNotEmpty && !state.isRunning)
            TextButton(
              onPressed: controller.clearFiles,
              child: const Text('Clear'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.isRunning)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.sync),
                    title: Text(
                      'Sending to ${state.receiverName ?? 'another phone'}',
                    ),
                    subtitle: const Text('One send at a time. Tap to see it.'),
                    onTap: () => pushScreen<void>(
                      context,
                      Routes.transfer,
                      const TransferScreen(),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: state.isRunning
                        ? null
                        : () => _pickMedia(context, ref),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Photos & videos'),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.isRunning
                        ? null
                        : controller.pickDocuments,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Files'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: state.picked.isEmpty
                  ? const _Empty()
                  : _PickedList(
                      picked: state.picked,
                      onRemove: state.isRunning
                          ? null
                          : controller.removePicked,
                    ),
            ),
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

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'Choose photos, videos or files to send. They are sent in original '
        'quality, straight to the other phone.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    ),
  );
}

class _PickedList extends StatelessWidget {
  const _PickedList({required this.picked, this.onRemove});

  final List<PickedItem> picked;
  final void Function(PickedItem item)? onRemove;

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    itemCount: picked.length,
    itemBuilder: (context, i) {
      final item = picked[i];
      final (kind, size) = switch (item) {
        PickedAsset(:final asset) => (asset.kind, null),
        PickedFile(:final platformKind, :final size) => (
          platformKind ?? FileKind.file,
          size,
        ),
      };
      return ListTile(
        leading: Icon(fileKindIcon(kind)),
        title: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: size == null ? null : Text(formatSize(size)),
        trailing: onRemove == null
            ? null
            : IconButton(
                tooltip: 'Remove ${item.label}',
                icon: const Icon(Icons.close),
                onPressed: () => onRemove!(item),
              ),
      );
    },
  );
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
    final theme = Theme.of(context);
    return Material(
      elevation: 3,
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (picked.isNotEmpty) ...[
              Text(summarizePicked(picked), style: theme.textTheme.titleMedium),
              if (picked.any(_sizeUnknown))
                Text(
                  'The full size is shown when sending starts.',
                  style: theme.textTheme.bodyMedium,
                ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: enabled ? onSend : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              icon: const Icon(Icons.send),
              label: const Text('Send'),
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
