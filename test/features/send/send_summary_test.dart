import 'package:crossdrop/core/media/format_plan.dart';
import 'package:crossdrop/core/media/prepare.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/features/send/send_screen.dart';
import 'package:flutter_test/flutter_test.dart';

PickedAsset asset(String kind) =>
    PickedAsset(LibraryAsset(id: kind, kind: kind));

void main() {
  test('files with known sizes: exact total', () {
    expect(
      summarizePicked(const [
        PickedFile(ref: 'a', name: 'a.pdf', size: 1500000),
        PickedFile(ref: 'b', name: 'b.zip', size: 2500000),
      ]),
      '2 files · 4.0 MB',
    );
  });

  test('photos and videos: counted, total is a lower bound', () {
    expect(
      summarizePicked([
        asset(FileKind.photo),
        asset(FileKind.photo),
        asset(FileKind.video),
        const PickedFile(ref: 'a', name: 'a.pdf', size: 3000000),
      ]),
      '2 photos, 1 video, 1 file · at least 3.0 MB',
    );
  });

  test('no size known: counts only', () {
    expect(summarizePicked([asset(FileKind.photo)]), '1 photo');
    expect(summarizePicked(const [PickedFile(ref: 'a', name: 'a')]), '1 file');
  });
}
