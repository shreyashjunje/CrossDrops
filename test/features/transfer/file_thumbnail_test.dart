import 'dart:async';
import 'dart:typed_data';

import 'package:crossdrop/app/media_providers.dart';
import 'package:crossdrop/core/media/thumb_ref.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/features/transfer/file_thumbnail.dart';
import 'package:crossdrop/platform/thumbnails.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 1x1 transparent PNG.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _Loader implements ThumbnailLoader {
  final Map<ThumbRef, Completer<ImageProvider?>> pending = {};
  final List<ThumbRef> asked = [];

  @override
  Future<ImageProvider?> load(ThumbRef ref) {
    asked.add(ref);
    return (pending[ref] = Completer<ImageProvider?>()).future;
  }
}

Future<void> pump(
  WidgetTester tester,
  ThumbnailService service,
  Widget child,
) => tester.pumpWidget(
  ProviderScope(
    overrides: [thumbnailServiceProvider.overrideWithValue(service)],
    child: MaterialApp(home: Scaffold(body: child)),
  ),
);

void main() {
  const photo = FileThumb('/staged/IMG_1.HEIC', kind: FileKind.photo);

  testWidgets('the kind icon until the preview arrives', (tester) async {
    final loader = _Loader();
    await pump(
      tester,
      ThumbnailService(loader),
      const FileThumbnail(thumb: photo, kind: FileKind.photo),
    );
    await tester.pump();
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    loader.pending[photo]!.complete(MemoryImage(_png));
    await tester.pump();
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsNothing);
  });

  testWidgets('a video preview gets a play mark', (tester) async {
    final loader = _Loader();
    const video = LibraryThumb('v1', kind: FileKind.video);
    await pump(
      tester,
      ThumbnailService(loader),
      const FileThumbnail(thumb: video, kind: FileKind.video),
    );
    await tester.pump();
    loader.pending[video]!.complete(MemoryImage(_png));
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('no preview keeps the icon; nothing to load asks nothing', (
    tester,
  ) async {
    final loader = _Loader();
    await pump(
      tester,
      ThumbnailService(loader),
      const Column(
        children: [
          FileThumbnail(thumb: photo, kind: FileKind.photo),
          FileThumbnail(thumb: null, kind: FileKind.file),
        ],
      ),
    );
    await tester.pump();
    loader.pending[photo]!.complete(null);
    await tester.pump();
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
    expect(loader.asked, [photo]);
  });

  testWidgets('rows that leave the screen give up their place', (tester) async {
    final loader = _Loader();
    final service = ThumbnailService(loader);
    final refs = [
      for (var i = 0; i < 6; i++) FileThumb('/f/$i.jpg', kind: FileKind.photo),
    ];
    await pump(
      tester,
      service,
      Column(
        children: [
          for (final r in refs) FileThumbnail(thumb: r, kind: FileKind.photo),
        ],
      ),
    );
    await tester.pump();
    // Three run at once, newest first.
    expect(loader.asked, [refs[5], refs[4], refs[3]]);

    await pump(tester, service, const SizedBox());
    for (final r in [refs[5], refs[4], refs[3]]) {
      loader.pending[r]!.complete(null);
    }
    await tester.pump();
    await tester.pump();
    expect(loader.asked, hasLength(3), reason: 'the rest were cancelled');
  });
}
