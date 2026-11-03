import 'package:crossdrop/core/media/format_plan.dart';
import 'package:crossdrop/core/storage/database.dart';
import 'package:crossdrop/core/storage/settings_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsRepository(db);
  });
  tearDown(() => db.close());

  test('defaults: receiving on, originals, still only', () async {
    expect(await settings.receivingEnabled(), isTrue);
    expect(await settings.formatSettings(), const FormatSettings());
  });

  test('each setter changes only its own value', () async {
    await settings.setReceivingEnabled(false);
    await settings.setConvertHeicToJpeg(true);
    expect(
      await settings.formatSettings(),
      const FormatSettings(convertHeicToJpeg: true),
    );
    await settings.setSendLivePhotoVideo(true);
    expect(
      await settings.formatSettings(),
      const FormatSettings(convertHeicToJpeg: true, sendLivePhotoVideo: true),
    );
    await settings.setConvertHeicToJpeg(false);
    expect(
      await settings.formatSettings(),
      const FormatSettings(sendLivePhotoVideo: true),
    );
    expect(await settings.receivingEnabled(), isFalse);
  });

  test('watchers see changes', () async {
    final seen = <FormatSettings>[];
    final sub = settings.watchFormatSettings().listen(seen.add);
    await pumpEventQueue();
    await settings.setSendLivePhotoVideo(true);
    await pumpEventQueue();
    await sub.cancel();
    expect(seen.first, const FormatSettings());
    expect(seen.last, const FormatSettings(sendLivePhotoVideo: true));
  });
}
