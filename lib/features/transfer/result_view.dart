import 'package:flutter/material.dart';

import '../../core/protocol/models.dart';
import '../../core/security/device_identity.dart';
import 'failure_messages.dart';
import 'file_thumbnail.dart';
import 'transfer_format.dart';
import 'transfer_view.dart';

/// A finished transfer. Done: what arrived, where it was saved, Open.
/// Failed (or partly): the reason in plain words and the next step, with
/// a button for it (ARCHITECTURE.md, "Failure handling").
class ResultView extends StatelessWidget {
  const ResultView({
    super.key,
    required this.view,
    required this.platform,
    this.onOpen,
    this.onAction,
    this.onTrust,
    this.onClose,
  });

  final TransferView view;

  /// This phone's platform, for where files were saved.
  final DevicePlatform platform;
  final void Function(TransferFileView file)? onOpen;
  final void Function(NextAction action)? onAction;

  /// Sender: "Trust" the receiver after a send to an untrusted one.
  final VoidCallback? onTrust;
  final VoidCallback? onClose;

  /// Files listed by name; more are counted.
  static const maxListed = 100;

  @override
  Widget build(BuildContext context) {
    final failure = describeOutcome(view);
    final arrived = [
      for (final f in view.files)
        if (f.status == FileTransferStatus.saved) f,
    ];
    final failed = [
      for (final f in view.files)
        if (f.status == FileTransferStatus.failed) f,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Header(view: view, failure: failure),
              if (failure != null) ...[
                const SizedBox(height: 16),
                _FailureCard(failure: failure, onAction: onAction),
              ],
              if (onTrust != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: onTrust,
                  icon: const Icon(Icons.verified_user_outlined),
                  label: Text('Trust ${view.peerName}'),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Next time, sending to it skips the code check, and a '
                  'different phone using its name is reported.',
                ),
              ],
              if (arrived.isNotEmpty) ...[
                const SizedBox(height: 24),
                _ArrivedList(
                  files: arrived,
                  sending: view.sending,
                  platform: platform,
                  onOpen: onOpen,
                ),
              ],
              if (failed.isNotEmpty) ...[
                const SizedBox(height: 24),
                _FailedList(files: failed),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(onPressed: onClose, child: const Text('Done')),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.view, required this.failure});

  final TransferView view;
  final FailureMessage? failure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final v = view;
    final n = v.savedCount;
    final files = '$n ${n == 1 ? 'file' : 'files'}';
    final cancelled = v.stage == TransferStage.cancelled;
    final (IconData icon, Color color) = failure == null
        ? (Icons.check_circle, scheme.primary)
        : cancelled
        ? (Icons.cancel_outlined, scheme.onSurfaceVariant)
        : (Icons.error, scheme.error);
    final title =
        failure?.title ?? (v.sending ? '$files sent' : '$files received');
    final savedBytes = v.files
        .where((f) => f.status == FileTransferStatus.saved)
        .fold(0, (sum, f) => sum + f.size);
    return Semantics(
      liveRegion: true,
      child: Column(
        children: [
          Icon(icon, size: 72, color: color),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            [
              v.sending ? 'to ${v.peerName}' : 'from ${v.peerName}',
              if (n > 0) formatSize(savedBytes),
            ].join(' · '),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          if (n > 0) ...[
            const SizedBox(height: 4),
            Text(
              v.sending
                  ? 'Original quality: the other phone checked every file '
                        'with SHA-256. Each one is identical to yours, byte '
                        'for byte.'
                  : 'Original quality: every file was checked with SHA-256. '
                        'Each one is identical to the original, byte for '
                        'byte.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.failure, this.onAction});

  final FailureMessage failure;
  final void Function(NextAction action)? onAction;

  static String? _label(NextAction a) => switch (a) {
    NextAction.resume => 'Resume',
    NextAction.sendAgain => 'Send again',
    NextAction.scanQr => 'Scan QR code',
    NextAction.findHelp => 'Other ways to connect',
    NextAction.none => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _label(failure.action);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What happened', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(failure.reason, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 12),
            Text('What to do', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(failure.next, style: theme.textTheme.bodyLarge),
            if (label != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => onAction!(failure.action),
                child: Text(label),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ArrivedList extends StatelessWidget {
  const _ArrivedList({
    required this.files,
    required this.sending,
    required this.platform,
    this.onOpen,
  });

  final List<TransferFileView> files;
  final bool sending;
  final DevicePlatform platform;
  final void Function(TransferFileView file)? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final where = <String>{
      for (final f in files)
        if (f.savedTo case final to?)
          formatSavedTo(to, null, platform: platform),
    };
    final more = files.length - ResultView.maxListed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          sending ? 'Sent' : 'Where to find them',
          style: theme.textTheme.titleMedium,
        ),
        for (final w in where) Text(w),
        const SizedBox(height: 8),
        for (final f in files.take(ResultView.maxListed))
          _ArrivedRow(
            file: f,
            platform: platform,
            // Sent files are on the other phone.
            onOpen: sending ? null : onOpen,
          ),
        if (more > 0) Text('and $more more'),
      ],
    );
  }
}

class _ArrivedRow extends StatelessWidget {
  const _ArrivedRow({required this.file, required this.platform, this.onOpen});

  final TransferFileView file;
  final DevicePlatform platform;
  final void Function(TransferFileView file)? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = file.saveFallback;
    final location = file.location;
    final canOpen = onOpen != null && location != null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          FileThumbnail(thumb: file.thumb, kind: file.kind, size: 48),
          Positioned(
            right: -4,
            bottom: -4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle,
                size: 18,
                color: scheme.primary,
                semanticLabel: 'saved',
              ),
            ),
          ),
        ],
      ),
      title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: fallback == null || file.savedTo == null
          ? Text(
              '${formatSize(file.size)} · ${formatExactBytes(file.size)}\n'
              'Original quality, verified',
            )
          : Text(
              formatSavedTo(file.savedTo!, fallback, platform: platform),
              style: TextStyle(color: scheme.error),
            ),
      isThreeLine: fallback == null || file.savedTo == null,
      trailing: canOpen
          ? TextButton(
              onPressed: () => onOpen!(file),
              child: Text(
                location.startsWith('photos:') ? 'Open Photos' : 'Open',
                semanticsLabel: location.startsWith('photos:')
                    ? 'Open Photos'
                    : 'Open ${file.name}',
              ),
            )
          : null,
    );
  }
}

class _FailedList extends StatelessWidget {
  const _FailedList({required this.files});

  final List<TransferFileView> files;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final more = files.length - ResultView.maxListed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Not saved', style: Theme.of(context).textTheme.titleMedium),
        for (final f in files.take(ResultView.maxListed))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                FileThumbnail(thumb: f.thumb, kind: f.kind, size: 48),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.error,
                      size: 18,
                      color: scheme.error,
                      semanticLabel: 'not saved',
                    ),
                  ),
                ),
              ],
            ),
            title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(describeFileError(f.error)),
          ),
        if (more > 0) Text('and $more more'),
      ],
    );
  }
}
