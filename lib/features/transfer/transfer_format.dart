import '../../core/media/save_target.dart';
import '../../core/security/device_identity.dart';
import '../../core/server/file_store.dart';

/// Megabytes as 10^6 bytes, matching the MB/s figures in BENCHMARKS.md.
String formatMegabytes(int bytes) => '${(bytes / 1e6).toStringAsFixed(1)} MB';

/// MB below 1 GB, GB above (10^9 bytes).
String formatSize(int bytes) => bytes >= 1e9
    ? '${(bytes / 1e9).toStringAsFixed(2)} GB'
    : formatMegabytes(bytes);

/// "3,482,117 bytes": the exact size, to compare with what a gallery or
/// file manager shows (they round, some in units of 1024).
String formatExactBytes(int bytes) {
  final digits = bytes.abs().toString();
  final out = StringBuffer(bytes < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return '$out ${bytes == 1 ? 'byte' : 'bytes'}';
}

String formatSpeed(double bytesPerSecond) =>
    '${(bytesPerSecond / 1e6).toStringAsFixed(1)} MB/s';

String formatDuration(Duration d) =>
    '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';

/// "about 3 min left", "12 s left"; empty while there is no estimate.
String formatTimeLeft(Duration? eta) {
  if (eta == null) return '';
  final s = eta.inSeconds;
  if (s < 60) return '${s < 1 ? 1 : s} s left';
  if (s < 3600) {
    final m = (s / 60).round();
    return 'about $m min left';
  }
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  return 'about $h h $m min left';
}

/// Where a received file is, for the user: "Saved to Photos",
/// "Saved to Download/CrossDrop (the gallery cannot open this format)".
String formatSavedTo(
  SaveCollection collection,
  String? fallback, {
  required DevicePlatform platform,
}) {
  final where = switch ((platform, collection)) {
    (DevicePlatform.ios, SaveCollection.photos || SaveCollection.videos) =>
      'Photos',
    (DevicePlatform.ios, SaveCollection.files) =>
      'Files > On My iPhone > CrossDrop',
    (DevicePlatform.android, SaveCollection.photos) => 'Pictures/CrossDrop',
    (DevicePlatform.android, SaveCollection.videos) => 'Movies/CrossDrop',
    (DevicePlatform.android, SaveCollection.files) => 'Download/CrossDrop',
  };
  final why = switch (fallback) {
    SaveFallback.unsupported =>
      platform == DevicePlatform.ios
          ? ' (Photos cannot import this format)'
          : ' (the gallery cannot open this format)',
    SaveFallback.permission => ' (CrossDrop may not add to Photos)',
    _ => '',
  };
  return 'Saved to $where$why';
}

/// Where received files go.
String describeSaveLocations(DevicePlatform platform) => switch (platform) {
  DevicePlatform.ios =>
    'Photos and videos go to your Photos library. Other files go to '
        'Files > On My iPhone > CrossDrop.',
  DevicePlatform.android =>
    'Photos go to Pictures/CrossDrop and videos to Movies/CrossDrop, so '
        'your gallery shows them. Other files go to Download/CrossDrop.',
};

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Today", "Yesterday", "3 Nov 2026".
String formatDay(DateTime t, DateTime now) {
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${t.day} ${_months[t.month - 1]} ${t.year}';
}

/// 24-hour "09:05".
String formatTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}';
