import 'speed_meter.dart';

/// Per-file and total progress of one session, with a moving-average speed
/// and the time left. Used on both sides.
class ProgressTracker {
  ProgressTracker(Map<String, int> sizes, {SpeedMeter? meter})
    : _sizes = Map.of(sizes),
      _done = {for (final id in sizes.keys) id: 0},
      _meter = meter ?? SpeedMeter(),
      totalBytes = sizes.values.fold(0, (sum, s) => sum + s);

  final Map<String, int> _sizes;
  final Map<String, int> _done;
  final SpeedMeter _meter;
  final int totalBytes;
  int _doneBytes = 0;

  int get doneBytes => _doneBytes;

  int bytesOf(String fileId) => _done[fileId] ?? 0;

  int sizeOf(String fileId) => _sizes[fileId] ?? 0;

  double get fraction => totalBytes == 0 ? 1 : _doneBytes / totalBytes;

  double get bytesPerSecond => _meter.bytesPerSecond;

  /// Null until there is a speed to divide by.
  Duration? get eta {
    final speed = _meter.bytesPerSecond;
    if (speed <= 0) return null;
    final left = totalBytes - _doneBytes;
    return Duration(microseconds: (left / speed * 1e6).round());
  }

  /// Records that [bytes] of [fileId] are done. Going backwards (a file
  /// restarted after a hash mismatch) is allowed.
  void set(String fileId, int bytes) {
    final old = _done[fileId];
    if (old == null) return;
    final size = _sizes[fileId]!;
    final clamped = bytes < 0 ? 0 : (bytes > size ? size : bytes);
    _done[fileId] = clamped;
    _doneBytes += clamped - old;
    if (clamped < old) {
      // A drop would read as negative speed; start the average again.
      _meter.reset();
    }
    _meter.add(_doneBytes);
  }

  /// A file that will not move any more (failed): its bytes no longer count
  /// towards the time left.
  void drop(String fileId) {
    final size = _sizes[fileId];
    if (size == null) return;
    set(fileId, size);
  }
}
