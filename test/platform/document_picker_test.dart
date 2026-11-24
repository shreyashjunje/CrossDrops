import 'dart:io';

import 'package:crossdrop/core/media/prepare.dart';
import 'package:crossdrop/platform/document_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('a folder pick keeps each file with its folder (D-075)', () {
    final pick = parseFolderPick({
      'files': [
        {
          'uri': 'content://x/tree/1/document/2',
          'name': 'a.jpg',
          'mime': 'image/jpeg',
          'size': 2048,
          'modifiedMs': 1767225600000,
          'folder': 'Trip/Day 1',
        },
        {'uri': 'content://x/3', 'name': 'b.txt', 'size': -1, 'folder': 'Trip'},
        {'uri': 'content://x/4', 'name': 'no folder'},
        {'uri': 'content://x/5', 'name': 'deep', 'folder': 'a' * 1025},
        'not a map',
      ],
      'skipped': 3,
    }, refKey: 'uri');
    expect(pick.files, hasLength(2));
    final a = pick.files.first;
    expect(
      (a.ref, a.name, a.mime, a.size, a.folder),
      (
        'content://x/tree/1/document/2',
        'a.jpg',
        'image/jpeg',
        2048,
        'Trip/Day 1',
      ),
    );
    expect(a.created, DateTime.utc(2026));
    expect(pick.files.last.size, isNull);
    // 3 from the platform, 3 unusable entries here.
    expect(pick.skipped, 6);
  });

  test('backing out of the picker is an empty pick', () {
    final pick = parseFolderPick(null, refKey: 'path');
    expect(pick.files, isEmpty);
    expect(pick.skipped, 0);
  });

  test('iOS: releasing one pick keeps the rest of its batch', () async {
    final root = await Directory.systemTemp.createTemp('staging');
    addTearDown(() => root.delete(recursive: true));
    final a = File(p.join(root.path, 'doc-1', '0', 'a.jpg'));
    final b = File(p.join(root.path, 'doc-1', '1', 'b.jpg'));
    for (final f in [a, b]) {
      await f.create(recursive: true);
    }
    final picker = IosDocumentPicker(root.path);

    await picker.release([PickedFile(ref: a.path, name: 'a.jpg')]);
    expect(a.existsSync(), isFalse);
    expect(b.existsSync(), isTrue, reason: 'still in the selection');

    await picker.release([PickedFile(ref: b.path, name: 'b.jpg')]);
    expect(Directory(p.join(root.path, 'doc-1')).existsSync(), isFalse);
    expect(root.existsSync(), isTrue);
  });

  group('iOS folder pick errors', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('crossdrop/open');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<Directory> answer(String code) async {
      final root = await Directory.systemTemp.createTemp('staging');
      addTearDown(() => root.delete(recursive: true));
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: code),
      );
      return root;
    }

    test('a folder too big to copy says so (D-077)', () async {
      final root = await answer('no_space');
      await expectLater(
        IosDocumentPicker(root.path).pickFolder(),
        throwsA(isA<FolderTooLarge>()),
      );
      expect(root.listSync(), isEmpty, reason: 'the empty batch is gone');
    });

    test('another picker error is an empty pick', () async {
      final root = await answer('busy');
      final pick = await IosDocumentPicker(root.path).pickFolder();
      expect(pick.files, isEmpty);
      expect(root.listSync(), isEmpty);
    });
  });
}
