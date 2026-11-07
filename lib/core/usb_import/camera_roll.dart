import '../media/save_target.dart';
import '../protocol/file_type.dart';
import '../protocol/models.dart';
import '../security/device_identity.dart';
import '../storage/file_name_sanitizer.dart';

/// One file on a phone connected by cable, as its camera interface (PTP)
/// lists it. The iPhone shows its camera roll as `DCIM/100APPLE`,
/// `101APPLE`, ... with about 1000 files each (D-067).
class CameraObject {
  const CameraObject({
    required this.handle,
    required this.name,
    required this.folder,
    this.size,
    this.taken,
  });

  /// The object's handle on the device, valid while it stays connected.
  final int handle;

  /// The name the device gives. Never logged (hard rule 7) and sanitized
  /// before it is used to save anything (hard rule 5).
  final String name;

  /// Handle of the folder it is in.
  final int folder;

  /// Bytes; null when the device did not say (4 GB and over on PTP).
  final int? size;

  /// When it was taken, as the device reports it.
  final DateTime? taken;
}

enum RollKind { photo, video }

/// What the grid shows as one tile: a photo or a video, with the files
/// that belong to it.
///
/// - **Live Photo:** `IMG_1234.HEIC` and `IMG_1234.MOV` in one folder. The
///   video part is [motion]; it is copied only when asked, because Android
///   galleries show it as a separate 3-second video.
/// - **Edited:** `IMG_E1234.HEIC` next to `IMG_1234.HEIC`. [primary] is the
///   edited version, which is what the Photos app shows; [original] is
///   the unedited one, copied only when asked.
class RollItem {
  const RollItem({
    required this.key,
    required this.kind,
    required this.primary,
    this.motion,
    this.original,
    this.originalMotion,
  });

  /// Unique within one listing.
  final String key;
  final RollKind kind;
  final CameraObject primary;
  final CameraObject? motion;
  final CameraObject? original;

  /// The video part of [original] when both versions are Live Photos.
  final CameraObject? originalMotion;

  bool get isLive => motion != null;
  bool get isEdited => original != null;

  /// iPhone screenshots are PNG; its camera never saves PNG.
  bool get isScreenshot =>
      kind == RollKind.photo && extensionOf(primary.name) == 'png';

  DateTime? get taken => primary.taken ?? original?.taken ?? motion?.taken;

  /// The files to copy for this item.
  List<CameraObject> files({
    bool includeLiveVideo = false,
    bool includeOriginal = false,
  }) => [
    primary,
    if (includeLiveVideo) ?motion,
    if (includeOriginal) ?original,
    if (includeOriginal && includeLiveVideo) ?originalMotion,
  ];
}

/// The camera roll as the grid shows it, newest first.
class CameraRoll {
  const CameraRoll({required this.items, required this.skipped});

  static const empty = CameraRoll(items: [], skipped: 0);

  final List<RollItem> items;

  /// Files that are not photos or videos (`.AAE` edit records, unknown
  /// formats). Not shown, never copied.
  final int skipped;
}

/// `IMG_1234`, `IMG_E1234`: the prefix, the edited mark and the number.
final RegExp _numbered = RegExp(r'^([A-Za-z]+_)(E?)(\d+)$');

/// Builds the roll from the device's flat list of files.
///
/// Files are grouped by folder and name without extension (the `E` of an
/// edited copy removed). In each group the first still and the first video
/// of each version (original, edited) form one item; anything else in the
/// group (`IMG_1234.DNG` next to `IMG_1234.HEIC`, a video that did not
/// pair) becomes its own item, so no file is hidden. A group with no still
/// is a video.
CameraRoll buildCameraRoll(Iterable<CameraObject> objects) {
  final groups = <String, _Group>{};
  final order = <String>[];
  var skipped = 0;
  for (final o in objects) {
    final kind = _kindOf(o.name);
    if (kind == null) {
      skipped++;
      continue;
    }
    final stem = _stem(o.name);
    final m = _numbered.firstMatch(stem);
    final edited = m != null && m.group(2)!.isNotEmpty;
    final base = m == null ? stem : '${m.group(1)}${m.group(3)}';
    final groupKey = '${o.folder}/${base.toUpperCase()}';
    final g = groups.putIfAbsent(groupKey, () {
      order.add(groupKey);
      return _Group();
    });
    g.add(o, kind: kind, edited: edited);
  }

  final items = <RollItem>[];
  for (final key in order) {
    final g = groups[key]!;
    final used = <CameraObject>{};
    RollItem keep(RollItem item) {
      used.addAll([
        item.primary,
        ?item.motion,
        ?item.original,
        ?item.originalMotion,
      ]);
      return item;
    }

    final still = g.editedStill ?? g.originalStill;
    if (still != null) {
      final edited = g.editedStill != null;
      items.add(
        keep(
          RollItem(
            key: '$key#${still.handle}',
            kind: RollKind.photo,
            primary: still,
            // An edited Live Photo has its own edited video; the original
            // video belongs to the original still.
            motion: edited ? g.editedMotion : g.originalMotion,
            original: edited ? g.originalStill : null,
            originalMotion: edited && g.originalStill != null
                ? g.originalMotion
                : null,
          ),
        ),
      );
    } else {
      final video = g.editedMotion ?? g.originalMotion!;
      items.add(
        keep(
          RollItem(
            key: '$key#${video.handle}',
            kind: RollKind.video,
            primary: video,
            original: g.editedMotion != null ? g.originalMotion : null,
          ),
        ),
      );
    }
    // Whatever did not pair is shown on its own, so no file is hidden.
    for (final o in [g.originalStill, g.editedStill]) {
      if (o != null && !used.contains(o)) {
        items.add(_single(key, o, RollKind.photo));
      }
    }
    for (final o in [g.originalMotion, g.editedMotion]) {
      if (o != null && !used.contains(o)) {
        items.add(_single(key, o, RollKind.video));
      }
    }
    for (final (o, kind) in g.extra) {
      items.add(_single(key, o, kind));
    }
  }
  items.sort(compareNewestFirst);
  return CameraRoll(items: items, skipped: skipped);
}

RollItem _single(String groupKey, CameraObject o, RollKind kind) =>
    RollItem(key: '$groupKey#${o.handle}', kind: kind, primary: o);

/// Newest first; items without a date last, then by name for a stable
/// order.
int compareNewestFirst(RollItem a, RollItem b) {
  final ta = a.taken;
  final tb = b.taken;
  if (ta != null && tb != null) {
    final c = tb.compareTo(ta);
    if (c != 0) return c;
  } else if (ta != null) {
    return -1;
  } else if (tb != null) {
    return 1;
  }
  return a.primary.name.compareTo(b.primary.name);
}

class _Group {
  CameraObject? originalStill;
  CameraObject? editedStill;
  CameraObject? originalMotion;
  CameraObject? editedMotion;
  final List<(CameraObject, RollKind)> extra = [];

  void add(CameraObject o, {required RollKind kind, required bool edited}) {
    switch ((kind, edited)) {
      case (RollKind.photo, false) when originalStill == null:
        originalStill = o;
      case (RollKind.photo, true) when editedStill == null:
        editedStill = o;
      case (RollKind.video, false) when originalMotion == null:
        originalMotion = o;
      case (RollKind.video, true) when editedMotion == null:
        editedMotion = o;
      default:
        extra.add((o, kind));
    }
  }
}

String _stem(String name) {
  final ext = extensionOf(name);
  return ext.isEmpty ? name : name.substring(0, name.length - ext.length - 1);
}

RollKind? _kindOf(String name) {
  return switch (kindForMime(mimeForName(name))) {
    FileKind.photo => RollKind.photo,
    FileKind.video => RollKind.video,
    _ => null,
  };
}

/// The grid's filter chips.
enum RollFilter { all, photos, videos, screenshots }

bool matchesFilter(RollItem item, RollFilter filter) => switch (filter) {
  RollFilter.all => true,
  RollFilter.photos => item.kind == RollKind.photo && !item.isScreenshot,
  RollFilter.videos => item.kind == RollKind.video,
  RollFilter.screenshots => item.isScreenshot,
};

/// One day in the grid: a header with "Select all" and its items.
class RollDay {
  const RollDay({required this.day, required this.items});

  /// Local midnight, or null for items without a date.
  final DateTime? day;
  final List<RollItem> items;
}

/// Groups [items] (already newest first) by local day; items without a
/// date form the last group.
List<RollDay> groupByDay(Iterable<RollItem> items) {
  final days = <RollDay>[];
  DateTime? current;
  var started = false;
  List<RollItem> bucket = [];
  for (final item in items) {
    final t = item.taken?.toLocal();
    final day = t == null ? null : DateTime(t.year, t.month, t.day);
    if (!started || day != current) {
      if (started) days.add(RollDay(day: current, items: bucket));
      bucket = [];
      current = day;
      started = true;
    }
    bucket.add(item);
  }
  if (started) days.add(RollDay(day: current, items: bucket));
  return days;
}

/// One file to copy, with what the saver needs.
class ImportFile {
  const ImportFile({
    required this.object,
    required this.itemKey,
    required this.safeName,
    required this.mime,
    required this.collection,
  });

  final CameraObject object;
  final String itemKey;

  /// [CameraObject.name] after [sanitizeFileName] (hard rule 5).
  final String safeName;
  final String mime;
  final SaveCollection collection;
}

/// The files to copy for [items], in grid order, with the gallery folder
/// each goes to. Formats the Android gallery cannot open go to Downloads.
List<ImportFile> planImport(
  Iterable<RollItem> items, {
  bool includeLiveVideo = false,
  bool includeOriginal = false,
}) {
  final files = <ImportFile>[];
  for (final item in items) {
    for (final o in item.files(
      includeLiveVideo: includeLiveVideo,
      includeOriginal: includeOriginal,
    )) {
      final safeName = sanitizeFileName(o.name);
      final mime = mimeForName(safeName) ?? 'application/octet-stream';
      files.add(
        ImportFile(
          object: o,
          itemKey: item.key,
          safeName: safeName,
          mime: mime,
          collection: saveCollectionFor(
            safeName: safeName,
            declaredKind: kindForMime(mime),
            platform: DevicePlatform.android,
          ),
        ),
      );
    }
  }
  return files;
}

/// Bytes [files] will take; files of unknown size count as 4 GiB, the
/// smallest size PTP cannot report.
int plannedBytes(Iterable<ImportFile> files) =>
    files.fold(0, (sum, f) => sum + (f.object.size ?? unknownSizeFloor));

/// PTP reports sizes as 32 bits; 0xFFFFFFFF means "4 GiB or more".
const int unknownSizeFloor = 0xFFFFFFFF;
