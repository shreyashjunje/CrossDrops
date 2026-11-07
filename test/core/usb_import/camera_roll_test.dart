import 'package:crossdrop/core/media/save_target.dart';
import 'package:crossdrop/core/usb_import/camera_roll.dart';
import 'package:flutter_test/flutter_test.dart';

var _next = 1;

CameraObject obj(
  String name, {
  int folder = 100,
  int? size = 1000,
  DateTime? taken,
}) => CameraObject(
  handle: _next++,
  name: name,
  folder: folder,
  size: size,
  taken: taken ?? DateTime(2026, 11, 3, 10),
);

List<String> names(Iterable<RollItem> items) => [
  for (final i in items) i.primary.name,
];

void main() {
  setUp(() => _next = 1);

  group('buildCameraRoll', () {
    test('a plain photo and a plain video are one item each', () {
      final roll = buildCameraRoll([obj('IMG_0001.HEIC'), obj('IMG_0002.MOV')]);
      expect(roll.items, hasLength(2));
      final photo = roll.items.firstWhere((i) => i.kind == RollKind.photo);
      expect(photo.primary.name, 'IMG_0001.HEIC');
      expect(photo.isLive, isFalse);
      expect(photo.isEdited, isFalse);
      final video = roll.items.firstWhere((i) => i.kind == RollKind.video);
      expect(video.primary.name, 'IMG_0002.MOV');
    });

    test('a Live Photo pairs the still with its video', () {
      final roll = buildCameraRoll([obj('IMG_0010.HEIC'), obj('IMG_0010.MOV')]);
      expect(roll.items, hasLength(1));
      final item = roll.items.single;
      expect(item.kind, RollKind.photo);
      expect(item.isLive, isTrue);
      expect(item.motion!.name, 'IMG_0010.MOV');
      expect(item.files().map((o) => o.name), ['IMG_0010.HEIC']);
      expect(item.files(includeLiveVideo: true).map((o) => o.name), [
        'IMG_0010.HEIC',
        'IMG_0010.MOV',
      ]);
    });

    test('pairing ignores case and needs the same folder', () {
      final roll = buildCameraRoll([
        obj('img_0011.heic', folder: 100),
        obj('IMG_0011.MOV', folder: 100),
        obj('IMG_0012.HEIC', folder: 100),
        obj('IMG_0012.MOV', folder: 101),
      ]);
      expect(roll.items, hasLength(3));
      expect(roll.items.where((i) => i.isLive), hasLength(1));
    });

    test('an edited photo shows the edited version, original on request', () {
      final roll = buildCameraRoll([
        obj('IMG_0020.HEIC'),
        obj('IMG_E0020.JPG'),
      ]);
      final item = roll.items.single;
      expect(item.primary.name, 'IMG_E0020.JPG');
      expect(item.original!.name, 'IMG_0020.HEIC');
      expect(item.files().map((o) => o.name), ['IMG_E0020.JPG']);
      expect(item.files(includeOriginal: true).map((o) => o.name), [
        'IMG_E0020.JPG',
        'IMG_0020.HEIC',
      ]);
    });

    test('an edited Live Photo keeps each video with its still', () {
      final roll = buildCameraRoll([
        obj('IMG_0030.HEIC'),
        obj('IMG_0030.MOV'),
        obj('IMG_E0030.HEIC'),
        obj('IMG_E0030.MOV'),
      ]);
      final item = roll.items.single;
      expect(item.primary.name, 'IMG_E0030.HEIC');
      expect(item.motion!.name, 'IMG_E0030.MOV');
      expect(item.original!.name, 'IMG_0030.HEIC');
      expect(item.originalMotion!.name, 'IMG_0030.MOV');
      expect(
        item
            .files(includeLiveVideo: true, includeOriginal: true)
            .map((o) => o.name),
        ['IMG_E0030.HEIC', 'IMG_E0030.MOV', 'IMG_0030.HEIC', 'IMG_0030.MOV'],
      );
    });

    test('an edited still of a Live Photo without an edited video', () {
      // The original video belongs to the original still; it is not
      // shown as a separate tile.
      final roll = buildCameraRoll([
        obj('IMG_0031.HEIC'),
        obj('IMG_0031.MOV'),
        obj('IMG_E0031.HEIC'),
      ]);
      final item = roll.items.single;
      expect(item.isLive, isFalse);
      expect(item.originalMotion!.name, 'IMG_0031.MOV');
    });

    test('an edited video shows the edited version', () {
      final roll = buildCameraRoll([obj('IMG_0040.MOV'), obj('IMG_E0040.MOV')]);
      final item = roll.items.single;
      expect(item.kind, RollKind.video);
      expect(item.primary.name, 'IMG_E0040.MOV');
      expect(item.original!.name, 'IMG_0040.MOV');
    });

    test('a video that does not pair is never hidden', () {
      final roll = buildCameraRoll([
        obj('IMG_0050.HEIC'),
        obj('IMG_E0050.MOV'),
      ]);
      expect(roll.items, hasLength(2));
      expect(
        names(roll.items),
        containsAll(['IMG_0050.HEIC', 'IMG_E0050.MOV']),
      );
    });

    test('a second still with the same name (RAW + HEIC) is its own item', () {
      final roll = buildCameraRoll([obj('IMG_0060.HEIC'), obj('IMG_0060.DNG')]);
      expect(roll.items, hasLength(2));
    });

    test('AAE edit records and unknown formats are skipped and counted', () {
      final roll = buildCameraRoll([
        obj('IMG_0070.HEIC'),
        obj('IMG_0070.AAE'),
        obj('IMG_O0070.AAE'),
        obj('notes.txt'),
        obj('README'),
      ]);
      expect(names(roll.items), ['IMG_0070.HEIC']);
      expect(roll.skipped, 4);
    });

    test('names that are not numbered still pair by stem', () {
      final roll = buildCameraRoll([obj('Holiday.JPG'), obj('Holiday.MOV')]);
      expect(roll.items.single.isLive, isTrue);
    });

    test('sorted newest first, items without a date last', () {
      final roll = buildCameraRoll([
        obj('IMG_0001.HEIC', taken: DateTime(2026, 1, 1)),
        CameraObject(handle: 99, name: 'IMG_0002.HEIC', folder: 100),
        obj('IMG_0003.HEIC', taken: DateTime(2026, 6, 1)),
      ]);
      expect(names(roll.items), [
        'IMG_0003.HEIC',
        'IMG_0001.HEIC',
        'IMG_0002.HEIC',
      ]);
    });

    test('keys are unique', () {
      final roll = buildCameraRoll([
        for (var i = 0; i < 50; i++) ...[
          obj('IMG_${i.toString().padLeft(4, '0')}.HEIC'),
          obj('IMG_${i.toString().padLeft(4, '0')}.DNG'),
        ],
      ]);
      expect(roll.items.map((i) => i.key).toSet(), hasLength(100));
    });
  });

  group('filters', () {
    test('screenshots are PNG photos and not in Photos', () {
      final roll = buildCameraRoll([
        obj('IMG_0001.PNG'),
        obj('IMG_0002.HEIC'),
        obj('IMG_0003.MOV'),
      ]);
      List<String> pick(RollFilter f) =>
          names(roll.items.where((i) => matchesFilter(i, f)));
      expect(pick(RollFilter.all), hasLength(3));
      expect(pick(RollFilter.photos), ['IMG_0002.HEIC']);
      expect(pick(RollFilter.videos), ['IMG_0003.MOV']);
      expect(pick(RollFilter.screenshots), ['IMG_0001.PNG']);
    });
  });

  group('groupByDay', () {
    test('one group per local day, undated last', () {
      final roll = buildCameraRoll([
        obj('A.HEIC', taken: DateTime(2026, 11, 3, 23)),
        obj('B.HEIC', taken: DateTime(2026, 11, 3, 8)),
        obj('C.HEIC', taken: DateTime(2026, 11, 1, 12)),
        CameraObject(handle: 500, name: 'D.HEIC', folder: 100),
      ]);
      final days = groupByDay(roll.items);
      expect(days, hasLength(3));
      expect(days[0].day, DateTime(2026, 11, 3));
      expect(names(days[0].items), ['A.HEIC', 'B.HEIC']);
      expect(days[1].day, DateTime(2026, 11, 1));
      expect(days[2].day, isNull);
      expect(names(days[2].items), ['D.HEIC']);
    });

    test('empty input gives no groups', () {
      expect(groupByDay(const []), isEmpty);
    });
  });

  group('planImport', () {
    test('sends photos to Pictures and videos to Movies', () {
      final roll = buildCameraRoll([
        obj('IMG_0001.HEIC'),
        obj('IMG_0001.MOV'),
        obj('IMG_0002.MOV', taken: DateTime(2026, 1, 1)),
      ]);
      final plan = planImport(roll.items, includeLiveVideo: true);
      expect(plan.map((f) => (f.safeName, f.collection, f.mime)), [
        ('IMG_0001.HEIC', SaveCollection.photos, 'image/heic'),
        ('IMG_0001.MOV', SaveCollection.videos, 'video/quicktime'),
        ('IMG_0002.MOV', SaveCollection.videos, 'video/quicktime'),
      ]);
    });

    test('names from the device are sanitized', () {
      final roll = buildCameraRoll([obj('../../evil/IMG_1.JPG')]);
      final plan = planImport(roll.items);
      expect(plan.single.safeName, 'IMG_1.JPG');
    });

    test('Live videos are left out unless asked', () {
      final roll = buildCameraRoll([obj('IMG_1.HEIC'), obj('IMG_1.MOV')]);
      expect(planImport(roll.items), hasLength(1));
      expect(planImport(roll.items, includeLiveVideo: true), hasLength(2));
    });

    test('plannedBytes counts unknown sizes as 4 GiB', () {
      final roll = buildCameraRoll([
        obj('IMG_1.HEIC', size: 10),
        obj('IMG_2.MOV', size: null),
      ]);
      expect(plannedBytes(planImport(roll.items)), 10 + unknownSizeFloor);
    });
  });
}
