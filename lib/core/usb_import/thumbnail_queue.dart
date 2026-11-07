import 'dart:async';
import 'dart:collection';

/// Loads previews from a device that answers one request at a time.
///
/// The newest request goes first, so the tiles on screen load before the
/// ones scrolled past; [cancel] drops a request that has not started (a
/// tile that left the screen). Finished results are kept, up to
/// [capacity], the oldest dropped first.
class ThumbnailQueue {
  ThumbnailQueue(this._fetch, {this.parallel = 2, this.capacity = 2000});

  final Future<String?> Function(int handle) _fetch;
  final int parallel;
  final int capacity;

  final LinkedHashMap<int, String?> _done = LinkedHashMap();
  final Map<int, Completer<String?>> _waiting = {};
  final List<int> _stack = [];
  final Map<int, Future<String?>> _running = {};
  bool _closed = false;
  bool _scheduled = false;

  /// The cached result, if [handle] finished; null otherwise or when the
  /// device has no preview (use [has] to tell).
  String? cached(int handle) => _done[handle];

  bool has(int handle) => _done.containsKey(handle);

  Future<String?> load(int handle) {
    if (_done.containsKey(handle)) return Future.value(_done[handle]);
    final running = _running[handle];
    if (running != null) return running;
    final waiting = _waiting[handle];
    if (waiting != null) {
      // Asked again: move it to the top.
      _stack.remove(handle);
      _stack.add(handle);
      return waiting.future;
    }
    final c = Completer<String?>();
    _waiting[handle] = c;
    _stack.add(handle);
    _schedule();
    return c.future;
  }

  /// Drops a request that has not started; its future completes with null.
  void cancel(int handle) {
    final c = _waiting.remove(handle);
    if (c == null) return;
    _stack.remove(handle);
    c.complete(null);
  }

  /// Completes every waiting request with null and stops.
  void close() {
    _closed = true;
    for (final c in _waiting.values) {
      c.complete(null);
    }
    _waiting.clear();
    _stack.clear();
  }

  /// Starts on the next microtask, so the tiles built in one frame are all
  /// queued first and the last of them goes first.
  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      _pump();
    });
  }

  void _pump() {
    while (!_closed && _running.length < parallel && _stack.isNotEmpty) {
      final handle = _stack.removeLast();
      final c = _waiting.remove(handle)!;
      final f = _run(handle);
      _running[handle] = f;
      c.complete(f);
    }
  }

  Future<String?> _run(int handle) async {
    String? path;
    try {
      path = await _fetch(handle);
    } on Object {
      path = null;
    }
    _running.remove(handle);
    if (!_closed) {
      _done[handle] = path;
      while (_done.length > capacity) {
        _done.remove(_done.keys.first);
      }
      // Let the caller see the result before the next request starts.
      _schedule();
    }
    return path;
  }
}
