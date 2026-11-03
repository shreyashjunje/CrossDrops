import 'dart:io';

import 'package:crossdrop/core/bench/phone_limits.dart';
import 'package:crossdrop/core/security/device_credentials.dart';
import 'package:crossdrop/core/server/file_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const mb = 1 << 20;
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('cd_limits'));
  tearDown(() => root.deleteSync(recursive: true));

  test('SHA-256 rate', () async {
    final r = await measureSha256(bytes: 8 * mb);
    expect(r.test, PhoneLimits.sha256);
    expect(r.bytes, 8 * mb);
    expect(r.mbPerSecond, greaterThan(0));
  });

  test('pinned TLS over loopback delivers every byte', () async {
    final creds = await DeviceCredentials.generate();
    final r = await measureTlsLoopback(creds, bytes: 8 * mb);
    expect(r.test, PhoneLimits.tls);
    expect(r.bytes, 8 * mb);
    expect(r.mbPerSecond, greaterThan(0));
  });

  test('writes go through the store and leave nothing behind', () async {
    final save = p.join(root.path, 'save');
    final store = FolderStore(save);
    final r = await measureWrites(
      store,
      p.join(root.path, 'tmp', 'limits'),
      test: PhoneLimits.write4mb,
      syncEvery: 4 * mb,
      bytes: 8 * mb,
    );
    expect(r.bytes, 8 * mb);
    expect(Directory(p.join(root.path, 'tmp', 'limits')).existsSync(), isFalse);
    expect(Directory(save).existsSync(), isFalse, reason: 'nothing saved');
  });

  test('all four, in order, with a CSV row each', () async {
    final creds = await DeviceCredentials.generate();
    final started = <String>[];
    final all = await measurePhoneLimits(
      credentials: creds,
      store: FolderStore(p.join(root.path, 'save')),
      tempDir: p.join(root.path, 'tmp'),
      bytes: 4 * mb,
      onStart: started.add,
    );
    const order = [
      PhoneLimits.sha256,
      PhoneLimits.tls,
      PhoneLimits.write4mb,
      PhoneLimits.write64mb,
    ];
    expect(started, order);
    expect([for (final r in all) r.test], order);
    final row = all.first.toCsv(platform: 'android', appVersion: '1.0.0');
    expect(row.split(',').length, PhoneLimit.csvHeader.split(',').length);
    expect(row, contains(',sha256,'));
  });
}
