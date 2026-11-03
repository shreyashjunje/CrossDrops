import 'package:crossdrop/core/media/prepare.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/platform/android_source.dart';
import 'package:crossdrop/platform/share_inbox.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const share = MethodChannel('crossdrop/share');
  const source = MethodChannel('crossdrop/source');
  tearDown(() {
    messenger.setMockMethodCallHandler(share, null);
    messenger.setMockMethodCallHandler(source, null);
  });

  PickedFile f(int i) => PickedFile(ref: 'content://x/$i', name: '$i.jpg');

  group('SharedFiles', () {
    test('caps at the offer limit and counts the rest', () {
      final s = SharedFiles.capped([
        for (var i = 0; i < 12; i++) f(i),
      ], max: 10);
      expect(s.files, hasLength(10));
      expect(s.files.last.ref, 'content://x/9');
      expect(s.truncated, 2);
    });

    test('merges batches; text-only counts only without files', () {
      final m = SharedFiles.merge([
        SharedFiles(files: [f(1)], rejected: 1),
        const SharedFiles(textOnly: true),
        SharedFiles(files: [f(2)]),
      ]);
      expect(m.files.map((x) => x.ref), ['content://x/1', 'content://x/2']);
      expect(m.textOnly, isFalse);
      expect(m.rejected, 1);

      final text = SharedFiles.merge([const SharedFiles(textOnly: true)]);
      expect(text.textOnly, isTrue);
      expect(text.isEmpty, isFalse);
      expect(SharedFiles.merge(const []).isEmpty, isTrue);
    });
  });

  test('Android shares are described into picked files', () async {
    messenger.setMockMethodCallHandler(share, (call) async {
      expect(call.method, 'takePending');
      return [
        {
          'uris': ['content://media/external/images/media/7', 'content://d/2'],
          'textOnly': false,
          'rejected': 1,
        },
      ];
    });
    messenger.setMockMethodCallHandler(source, (call) async {
      expect(call.method, 'describe');
      return [
        {
          'uri': 'content://media/external/images/media/7',
          'name': 'PXL_1.jpg',
          'size': 10,
          'mime': 'image/jpeg',
          'takenMs': 1700000000000,
        },
        {'uri': 'content://d/2', 'size': -1, 'mime': 'application/pdf'},
      ];
    });

    final s = await AndroidShareInbox(AndroidSources()).takePending();

    expect(s.rejected, 1);
    expect(s.files, hasLength(2));
    expect(s.files[0].name, 'PXL_1.jpg');
    expect(s.files[0].platformKind, FileKind.photo);
    expect(s.files[0].created, isNotNull);
    expect(s.files[1].name, 'file', reason: 'no name from the provider');
    expect(s.files[1].platformKind, isNull);
  });

  test('a share whose describe fails still lists its URIs', () async {
    messenger.setMockMethodCallHandler(
      share,
      (call) async => [
        {
          'uris': ['content://x/1'],
          'textOnly': false,
          'rejected': 0,
        },
      ],
    );
    messenger.setMockMethodCallHandler(
      source,
      (call) async => throw PlatformException(code: 'permission'),
    );
    final s = await AndroidShareInbox(AndroidSources()).takePending();
    expect(s.files.single.ref, 'content://x/1');
  });

  test('nothing pending', () async {
    messenger.setMockMethodCallHandler(share, (call) async => []);
    expect(
      (await AndroidShareInbox(AndroidSources()).takePending()).isEmpty,
      isTrue,
    );
  });
}
