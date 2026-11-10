import '../log.dart';
import 'camera_roll.dart';

/// A copy that failed, with one of the platform's error codes
/// (`UsbCameraErrors`).
class CopyFailure implements Exception {
  const CopyFailure(this.code);
  final String code;

  @override
  String toString() => 'CopyFailure($code)';
}

/// Copies one file and returns the bytes written; throws [CopyFailure].
typedef CopyOne = Future<int> Function(ImportFile file);

/// Not enough free space for the whole selection (hard rule 6). Nothing
/// was copied.
class NotEnoughSpace implements Exception {
  const NotEnoughSpace({required this.needed, required this.free});
  final int needed;
  final int free;
}

class ImportProgress {
  const ImportProgress({
    required this.filesDone,
    required this.filesTotal,
    required this.bytesDone,
    required this.bytesTotal,
    this.currentItem,
    this.copiedItems = const {},
  });

  final int filesDone;
  final int filesTotal;
  final int bytesDone;
  final int bytesTotal;

  /// [ImportFile.itemKey] of the file being copied; null between files.
  final String? currentItem;

  /// Items whose files have all been copied so far.
  final Set<String> copiedItems;

  double get fraction => bytesTotal <= 0
      ? (filesTotal == 0 ? 1 : filesDone / filesTotal)
      : (bytesDone / bytesTotal).clamp(0, 1).toDouble();
}

/// Why an import ended before the last file.
enum ImportStop { cancelled, disconnected, noSpace, deviceError }

class ImportSummary {
  const ImportSummary({
    required this.copiedItems,
    required this.copiedFiles,
    required this.failedFiles,
    required this.notTried,
    required this.bytes,
    required this.elapsed,
    this.stop,
  });

  /// Keys of the items whose files were all copied.
  final Set<String> copiedItems;
  final int copiedFiles;

  /// Files that failed twice (size mismatch, read error); the rest went on.
  final int failedFiles;

  /// Files not started because the import stopped.
  final int notTried;
  final int bytes;
  final Duration elapsed;
  final ImportStop? stop;
}

/// Copies files one at a time (D-067).
///
/// - Checks free space for the whole selection first.
/// - A file that fails with a size mismatch or a read error is tried once
///   more, then counted as failed; the others go on.
/// - Unplugging, a full disk or a device that stops answering ends the
///   import. Files already copied stay in the gallery.
/// - [cancel] stops before the next file. To stop the current one too,
///   the caller also cancels it on the device, which then fails with
///   `cancelled`.
class ImportRunner {
  ImportRunner({
    required this._copy,
    required this._freeBytes,
    this.reserve = 200 * 1000 * 1000,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final CopyOne _copy;
  final Future<int?> Function() _freeBytes;
  final DateTime Function() _clock;

  /// Space left free after the import, so the phone keeps working.
  final int reserve;

  bool _cancelled = false;
  int? _currentHandle;
  String? _currentItem;
  final Set<String> _copiedItems = {};
  int _currentBytes = 0;
  int _doneBytes = 0;
  int _doneFiles = 0;
  int _totalBytes = 0;
  int _totalFiles = 0;
  void Function(ImportProgress)? _onProgress;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  /// Bytes of the file being copied, from the device's progress events.
  void reportBytes(int handle, int bytes) {
    if (handle != _currentHandle) return;
    _currentBytes = bytes;
    _emit();
  }

  ImportProgress get progress => ImportProgress(
    filesDone: _doneFiles,
    filesTotal: _totalFiles,
    bytesDone: _doneBytes + _currentBytes,
    bytesTotal: _totalBytes,
    currentItem: _currentItem,
    copiedItems: Set.unmodifiable(_copiedItems),
  );

  void _emit() => _onProgress?.call(progress);

  /// Throws [NotEnoughSpace] before copying anything.
  Future<ImportSummary> run(
    List<ImportFile> files, {
    void Function(ImportProgress)? onProgress,
  }) async {
    final started = _clock();
    _onProgress = onProgress;
    _totalFiles = files.length;
    _totalBytes = plannedBytes(files);
    final needed = _totalBytes + reserve;
    final free = await _freeBytes();
    if (free != null && free < needed) {
      throw NotEnoughSpace(needed: needed, free: free);
    }
    final perItem = <String, int>{};
    for (final f in files) {
      perItem.update(f.itemKey, (n) => n + 1, ifAbsent: () => 1);
    }
    _emit();

    final failedItems = <String>{};
    final copiedFiles = <String, int>{};
    var failed = 0;
    var bytes = 0;
    ImportStop? stop;
    var i = 0;
    for (; i < files.length; i++) {
      if (_cancelled) {
        stop = ImportStop.cancelled;
        break;
      }
      final f = files[i];
      _currentHandle = f.object.handle;
      _currentItem = f.itemKey;
      _currentBytes = 0;
      _emit();
      final result = await _copyWithRetry(f);
      _currentHandle = null;
      _currentItem = null;
      _currentBytes = 0;
      switch (result) {
        case _Copied(:final written):
          bytes += written;
          final n = copiedFiles.update(
            f.itemKey,
            (n) => n + 1,
            ifAbsent: () => 1,
          );
          if (n == perItem[f.itemKey] && !failedItems.contains(f.itemKey)) {
            _copiedItems.add(f.itemKey);
          }
        case _Failed():
          failed++;
          failedItems.add(f.itemKey);
        case _Stopped(:final reason):
          stop = reason;
      }
      if (stop != null) break;
      _doneFiles++;
      _doneBytes += f.object.size ?? 0;
      _emit();
    }

    final summary = ImportSummary(
      copiedItems: Set.of(_copiedItems),
      copiedFiles: copiedFiles.values.fold(0, (a, b) => a + b),
      failedFiles: failed,
      notTried: files.length - i,
      bytes: bytes,
      elapsed: _clock().difference(started),
      stop: stop,
    );
    logEvent(
      'usb',
      'import: ${summary.copiedFiles} copied, $failed failed, '
          '${summary.notTried} not tried, $bytes bytes, stop ${stop?.name}',
    );
    return summary;
  }

  Future<_Result> _copyWithRetry(ImportFile f) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return _Copied(await _copy(f));
      } on CopyFailure catch (e) {
        logEvent('usb', 'file ${f.object.handle}: ${e.code} (try $attempt)');
        final stop = switch (e.code) {
          'cancelled' => ImportStop.cancelled,
          'disconnected' => ImportStop.disconnected,
          'no_space' => ImportStop.noSpace,
          'permission_denied' || 'busy' || 'locked' => ImportStop.deviceError,
          _ => null,
        };
        if (stop != null) return _Stopped(stop);
        if (attempt >= 2) return const _Failed();
        _currentBytes = 0;
      }
    }
  }
}

sealed class _Result {
  const _Result();
}

class _Copied extends _Result {
  const _Copied(this.written);
  final int written;
}

class _Failed extends _Result {
  const _Failed();
}

class _Stopped extends _Result {
  const _Stopped(this.reason);
  final ImportStop reason;
}
