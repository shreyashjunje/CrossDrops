import 'dart:io';

import 'package:crossdrop/core/engine/chunked_reader.dart';
import 'package:crossdrop/core/engine/source_opener.dart';
import 'package:crossdrop/platform/android_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('crossdrop/source');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('ContentInfo reads sizes, dates and unknowns', () {
    final i = ContentInfo.fromMap({
      'uri': 'content://media/external/images/media/5',
      'name': 'IMG_1.jpg',
      'size': 1234,
      'mime': 'image/jpeg',
      'takenMs': 1700000000000,
      'modifiedMs': 1600000000000,
    });
    expect(i.size, 1234);
    expect(i.created, DateTime.utc(2023, 11, 14, 22, 13, 20));

    final unknown = ContentInfo.fromMap({'uri': 'content://x/1', 'size': -1});
    expect(unknown.size, isNull);
    expect(unknown.created, isNull);
    expect(unknown.name, isNull);

    final docs = ContentInfo.fromMap({
      'uri': 'content://d/1',
      'size': 0,
      'modifiedMs': 1600000000000,
    });
    expect(docs.size, 0, reason: 'an empty file has a size');
    expect(
      docs.created,
      DateTime.fromMillisecondsSinceEpoch(1600000000000, isUtc: true),
    );
  });

  test('the opener maps content URIs to descriptors and errors', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'open');
      final uri = (call.arguments as Map)['uri'];
      if (uri == 'content://gone') {
        throw PlatformException(code: SourceErrors.notFound);
      }
      return {'fd': 42, 'size': 10, 'original': false};
    });
    final opener = AndroidSourceOpener(AndroidSources());

    final o = await opener.open('content://media/external/images/media/1');
    expect(o.source, isA<FdSource>().having((s) => s.fd, 'fd', 42));
    expect(o.length, 10);

    await expectLater(
      opener.open('content://gone'),
      throwsA(
        isA<SourceUnavailable>().having((e) => e.reason, 'reason', 'not_found'),
      ),
    );
  });

  test('the opener reads plain paths as files without the channel', () async {
    final dir = Directory.systemTemp.createTempSync('cd_src');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = p.join(dir.path, 'a.txt');
    File(path).writeAsStringSync('hello');
    final o = await AndroidSourceOpener(AndroidSources()).open(path);
    expect(o.source, isA<PathSource>());
    expect(o.length, 5);
  });
}
