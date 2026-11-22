import 'dart:async';

import '../engine/source_opener.dart';
import '../log.dart';
import 'format_plan.dart';
import 'prepare.dart';

/// Library items offered before they were exported (D-072): their sizes
/// came from the library, and each is exported while earlier files are
/// already on their way. Opening one waits for its export.
///
/// Exports run in offer order, [parallel] at a time; opening an item that
/// has not started yet starts it at once. A failed export is tried once
/// more when the send opens the file; if that fails too, the open throws
/// [SourceUnavailable] and the send withdraws that file alone.
class ExportPipeline implements DeferredSourceOpener {
  ExportPipeline(this._media, this._inner, {this.parallel = defaultParallel});

  /// Each export mostly waits on the Photos service or iCloud.
  static const int defaultParallel = 4;

  final MediaPlatform _media;
  final SourceOpener _inner;
  final int parallel;
  final PrepareControl _control = PrepareControl();
  final List<_Job> _jobs = [];
  final Map<String, _Job> _byPath = {};
  var _next = 0;
  var _started = false;

  bool get isEmpty => _jobs.isEmpty;

  /// Registers [asset], planned (not exported) into [files] under [dir].
  void add(
    LibraryAsset asset,
    ExportPlan plan,
    String dir,
    List<ResolvedFile> files,
  ) {
    final job = _Job(this, asset, plan, dir, {
      for (final f in files) f.ref: f.size,
    });
    _jobs.add(job);
    for (final f in files) {
      _byPath[f.ref] = job;
    }
  }

  /// Starts exporting in the background, in offer order.
  void start() {
    if (_started || _control.isCancelled) return;
    _started = true;
    for (var i = 0; i < parallel && i < _jobs.length; i++) {
      unawaited(_worker());
    }
  }

  Future<void> _worker() async {
    while (!_control.isCancelled && _next < _jobs.length) {
      final job = _jobs[_next++];
      try {
        await job.run(retry: false);
      } on SourceUnavailable {
        // Retried once when the send opens the file.
      }
    }
  }

  @override
  bool isPending(String ref) => _byPath[ref]?.exported == false;

  @override
  Future<OpenedSource> open(String ref) async {
    final job = _byPath[ref];
    if (job != null) {
      try {
        await job.run(retry: true);
      } on SourceUnavailable {
        // It may have been the background try that failed: one more.
        await job.run(retry: true);
      }
    }
    return _inner.open(ref);
  }

  /// Stops every export. Call before deleting the staging folder.
  Future<void> cancel() async {
    await _control.cancel();
    await Future.wait([for (final j in _jobs) ?j.running?.catchError((_) {})]);
  }
}

class _Job {
  _Job(this._owner, this.asset, this.plan, this.dir, this.expected);

  final ExportPipeline _owner;
  final LibraryAsset asset;
  final ExportPlan plan;
  final String dir;

  /// Planned path to planned size.
  final Map<String, int> expected;
  bool exported = false;
  var _tries = 0;
  Future<void>? running;

  /// Exports once; after a failure, [retry] tries one more time.
  Future<void> run({required bool retry}) {
    if (exported) return Future.value();
    final r = running;
    if (r != null) return r;
    if (_tries >= (retry ? 2 : 1)) {
      return Future.error(const SourceUnavailable('export failed'));
    }
    _tries++;
    return running = _export().whenComplete(() => running = null);
  }

  Future<void> _export() async {
    final control = _owner._control;
    if (control.isCancelled) throw const SourceUnavailable('cancelled');
    final List<ResolvedFile> files;
    try {
      files = await _owner._media.resolveAsset(
        asset,
        plan,
        dir,
        control,
        (_) {},
      );
    } on MediaUnavailable catch (e) {
      logEvent('prepare', 'export during send failed (${e.code})');
      throw SourceUnavailable(e.code);
    }
    // The send compares sizes again when it opens the file.
    final paths = {for (final f in files) f.ref};
    if (!expected.keys.every(paths.contains)) {
      logEvent('prepare', 'export during send: other files than planned');
      throw const SourceUnavailable('export changed');
    }
    exported = true;
  }
}
