import 'dart:async';

import 'package:flutter/services.dart';

import '../core/log.dart';
import '../core/media/prepare.dart';
import '../core/protocol/models.dart';
import 'android_source.dart';

/// Files another app shared to CrossDrop (D-044, D-045).
class SharedFiles {
  const SharedFiles({
    this.files = const [],
    this.textOnly = false,
    this.rejected = 0,
    this.truncated = 0,
  });

  final List<PickedFile> files;

  /// Only text or a link was shared; CrossDrop sends files.
  final bool textOnly;

  /// Items refused for safety (not a content URI, or CrossDrop's own).
  final int rejected;

  /// Items beyond [maxFilesPerOffer], left out.
  final int truncated;

  bool get isEmpty => files.isEmpty && !textOnly && rejected == 0;

  /// Several shares that arrived together, as one.
  static SharedFiles merge(Iterable<SharedFiles> all) {
    final files = <PickedFile>[];
    var text = false, rejected = 0, truncated = 0;
    for (final s in all) {
      files.addAll(s.files);
      text = text || s.textOnly;
      rejected += s.rejected;
      truncated += s.truncated;
    }
    return capped(
      files,
      textOnly: text && files.isEmpty,
      rejected: rejected,
      truncated: truncated,
    );
  }

  /// Keeps at most [max] files, counting the rest in [truncated].
  static SharedFiles capped(
    List<PickedFile> files, {
    bool textOnly = false,
    int rejected = 0,
    int truncated = 0,
    int max = maxFilesPerOffer,
  }) => SharedFiles(
    files: files.length > max ? files.sublist(0, max) : files,
    textOnly: textOnly,
    rejected: rejected,
    truncated: truncated + (files.length > max ? files.length - max : 0),
  );
}

/// Where shares from other apps arrive.
abstract interface class ShareInbox {
  /// Shares received since the last call (the app may have been started
  /// by one). Each is returned once.
  Future<SharedFiles> takePending();

  /// Fires when a share arrives while the app runs.
  Stream<void> get arrivals;
}

/// Android: SEND and SEND_MULTIPLE intents (android/.../ShareChannel.kt).
class AndroidShareInbox implements ShareInbox {
  AndroidShareInbox(this._sources, [MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('crossdrop/share') {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'arrived') _arrivals.add(null);
      return null;
    });
  }

  final AndroidSources _sources;
  final MethodChannel _channel;
  final _arrivals = StreamController<void>.broadcast();

  @override
  Stream<void> get arrivals => _arrivals.stream;

  @override
  Future<SharedFiles> takePending() async {
    final batches =
        await _channel.invokeListMethod<Map<Object?, Object?>>('takePending') ??
        const [];
    final out = <SharedFiles>[];
    for (final b in batches) {
      final uris = (b['uris'] as List? ?? const []).cast<String>();
      List<ContentInfo> infos;
      try {
        infos = await _sources.describe(uris);
      } on PlatformException catch (e) {
        logEvent('share', 'describe failed (${e.code})');
        infos = [for (final u in uris) ContentInfo(uri: u)];
      }
      out.add(
        SharedFiles(
          files: [
            for (final i in infos)
              PickedFile(
                ref: i.uri,
                name: i.name ?? 'file',
                mime: i.mime,
                created: i.created,
                platformKind: _kindFromMime(i.mime),
              ),
          ],
          textOnly: b['textOnly'] == true,
          rejected: (b['rejected'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return SharedFiles.merge(out);
  }

  /// A gallery shares MediaStore items with an image or video type.
  static String? _kindFromMime(String? mime) => mime == null
      ? null
      : mime.startsWith('image/')
      ? FileKind.photo
      : mime.startsWith('video/')
      ? FileKind.video
      : null;
}
