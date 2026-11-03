import 'dart:convert';
import 'dart:io';

import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/platform/share_inbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late String inbox;
  late String staging;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cd_inbox');
    inbox = p.join(root.path, 'group', 'Inbox');
    staging = p.join(root.path, 'support', 'crossdrop_outgoing');
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// A share as the extension writes it.
  String share(
    String id,
    Map<String, String> files, {
    Object? manifest,
    String kind = 'photo',
  }) {
    final dir = p.join(inbox, id);
    var n = 0;
    final items = [];
    for (final e in files.entries) {
      final f = File(p.join(dir, '$n', e.key))..createSync(recursive: true);
      f.writeAsStringSync(e.value);
      items.add({'file': '$n/${e.key}', 'name': e.key, 'kind': kind});
      n++;
    }
    Directory(dir).createSync(recursive: true);
    File(p.join(dir, 'manifest.json')).writeAsStringSync(
      jsonEncode(manifest ?? {'v': 1, 'items': items, 'failed': 0}),
    );
    return dir;
  }

  IosShareInbox inboxFor({DateTime? now}) => IosShareInbox(
    stagingRoot: staging,
    clock: now == null ? null : () => now,
  );

  test('a complete share moves into staging and is offered once', () async {
    share('A', {'IMG_1.HEIC': 'one', 'IMG_2.MOV': 'two'});
    final got = await inboxFor().takeFrom(inbox);

    expect(got.files.map((f) => f.name), ['IMG_1.HEIC', 'IMG_2.MOV']);
    expect(got.files.first.platformKind, FileKind.photo);
    for (final f in got.files) {
      expect(p.isWithin(staging, f.ref), isTrue);
      expect(File(f.ref).existsSync(), isTrue);
    }
    expect(File(got.files.first.ref).readAsStringSync(), 'one');
    expect(Directory(p.join(inbox, 'A')).existsSync(), isFalse);

    expect((await inboxFor().takeFrom(inbox)).isEmpty, isTrue);
  });

  test('a share still being written (no manifest) waits', () async {
    File(p.join(inbox, 'B', '0', 'x.jpg')).createSync(recursive: true);
    expect((await inboxFor().takeFrom(inbox)).isEmpty, isTrue);
    expect(Directory(p.join(inbox, 'B')).existsSync(), isTrue);

    // An hour later it was abandoned.
    final later = DateTime.now().add(const Duration(hours: 2));
    await inboxFor(now: later).takeFrom(inbox);
    expect(Directory(p.join(inbox, 'B')).existsSync(), isFalse);
  });

  test('the extension reports items it could not read', () async {
    share('C', {'a.pdf': 'x'}, kind: 'file');
    final dir = p.join(inbox, 'C');
    final m = jsonDecode(
      File(p.join(dir, 'manifest.json')).readAsStringSync(),
    ) as Map;
    m['failed'] = 2;
    File(p.join(dir, 'manifest.json')).writeAsStringSync(jsonEncode(m));

    final got = await inboxFor().takeFrom(inbox);
    expect(got.files.single.platformKind, isNull);
    expect(got.rejected, 2);
  });

  group('parseShareManifest refuses', () {
    late String dir;
    setUp(() {
      dir = p.join(root.path, 'share');
      File(p.join(dir, '0', 'ok.jpg')).createSync(recursive: true);
      File(p.join(root.path, 'secret.db')).writeAsStringSync('private');
    });

    void refused(Object manifest) => expect(
      () => parseShareManifest(jsonEncode(manifest), dir),
      throwsFormatException,
      reason: jsonEncode(manifest),
    );

    Map<String, Object> one(String file) => {
      'v': 1,
      'items': [
        {'file': file, 'name': 'x'},
      ],
    };

    test('paths outside the share folder', () {
      refused(one('../secret.db'));
      refused(one('0/../../secret.db'));
      refused(one(p.join(root.path, 'secret.db')));
      refused(one('./0/ok.jpg'));
    });

    test('missing files and folders', () {
      refused(one('0/missing.jpg'));
      refused(one('0'));
      refused(one(''));
    });

    test('links, even to a real file', () {
      final link = p.join(dir, '0', 'link.jpg');
      try {
        Link(link).createSync(p.join(root.path, 'secret.db'));
      } on FileSystemException {
        markTestSkipped('this OS needs privileges to create links');
        return;
      }
      refused(one('0/link.jpg'));
    });

    test('unknown versions, junk and too many items', () {
      expect(() => parseShareManifest('not json', dir), throwsFormatException);
      refused({'v': 2, 'items': []});
      refused({'v': 1, 'items': 'x'});
      refused({
        'v': 1,
        'items': [
          for (var i = 0; i <= maxFilesPerOffer; i++) {'file': '0/ok.jpg'},
        ],
      });
    });

    test('and accepts a good one, keeping only the base name', () {
      final r = parseShareManifest(
        jsonEncode({
          'v': 1,
          'items': [
            {'file': '0/ok.jpg', 'name': '../../evil/ok.jpg', 'kind': 'photo'},
          ],
          'failed': -3,
        }),
        dir,
      );
      expect(r.items.single.name, 'ok.jpg');
      expect(r.items.single.kind, FileKind.photo);
      expect(r.failed, 0);
    });
  });

  test('a bad manifest deletes the share and counts it', () async {
    share(
      'D',
      {'x.jpg': 'x'},
      manifest: {
        'v': 1,
        'items': [
          {'file': '../x'},
        ],
      },
    );
    final got = await inboxFor().takeFrom(inbox);
    expect(got.files, isEmpty);
    expect(got.rejected, 1);
    expect(Directory(p.join(inbox, 'D')).existsSync(), isFalse);
  });

  test('stray files in the inbox are removed', () async {
    File(p.join(inbox, 'junk.txt')).createSync(recursive: true);
    await inboxFor().takeFrom(inbox);
    expect(File(p.join(inbox, 'junk.txt')).existsSync(), isFalse);
  });
}
