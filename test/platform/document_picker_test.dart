import 'package:crossdrop/platform/document_picker.dart';
import 'package:flutter_test/flutter_test.dart';

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
    // 3 from the platform, 2 unreadable entries here.
    expect(pick.skipped, 5);
  });

  test('backing out of the picker is an empty pick', () {
    final pick = parseFolderPick(null, refKey: 'path');
    expect(pick.files, isEmpty);
    expect(pick.skipped, 0);
  });
}
