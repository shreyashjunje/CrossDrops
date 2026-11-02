import 'dart:collection';

/// A token bucket per key (the sender's IP address): [burst] requests at
/// once, then one more every [refillEvery] (ARCHITECTURE.md, "Abuse
/// limits", D-032).
class RateLimiter {
  RateLimiter({
    required this.burst,
    required this.refillEvery,
    this.maxKeys = 1024,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int burst;
  final Duration refillEvery;

  /// Keys remembered at most; the least recently used is forgotten first,
  /// so a flood of addresses cannot grow memory without bound.
  final int maxKeys;
  final DateTime Function() _clock;

  // Insertion order = least recently used first.
  final LinkedHashMap<String, _Bucket> _buckets = LinkedHashMap();

  /// Takes one request from [key]'s bucket. Returns null if allowed,
  /// otherwise how long until the next request would be.
  Duration? take(String key) {
    final now = _clock();
    final bucket = _buckets.remove(key) ?? _Bucket(burst.toDouble(), now);
    _buckets[key] = bucket;
    if (_buckets.length > maxKeys) _buckets.remove(_buckets.keys.first);

    final perMs = 1 / refillEvery.inMilliseconds;
    final elapsed = now.difference(bucket.updated).inMilliseconds;
    if (elapsed > 0) {
      bucket.tokens = (bucket.tokens + elapsed * perMs).clamp(
        0,
        burst.toDouble(),
      );
      bucket.updated = now;
    }
    if (bucket.tokens >= 1) {
      bucket.tokens -= 1;
      return null;
    }
    final waitMs = ((1 - bucket.tokens) / perMs).ceil();
    return Duration(milliseconds: waitMs);
  }

  int get trackedKeys => _buckets.length;
}

class _Bucket {
  _Bucket(this.tokens, this.updated);
  double tokens;
  DateTime updated;
}
