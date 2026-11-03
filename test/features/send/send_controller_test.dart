import 'dart:async';

import 'package:crossdrop/app/keep_alive.dart';
import 'package:crossdrop/app/media_providers.dart';
import 'package:crossdrop/app/providers.dart';
import 'package:crossdrop/core/client/peer_check.dart';
import 'package:crossdrop/core/media/prepare.dart';
import 'package:crossdrop/features/nearby/nearby_controller.dart';
import 'package:crossdrop/features/send/send_controller.dart';
import 'package:crossdrop/platform/keep_alive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoKeepAlive implements KeepAlivePlatform {
  @override
  Future<void> setScreenOn(bool on) async {}
  @override
  Future<bool> ensureNotificationPermission() async => true;
  @override
  Future<void> startService({
    required String title,
    required String text,
  }) async {}
  @override
  Future<void> updateService({required String text}) async {}
  @override
  Future<void> stopService() async {}
  @override
  Future<void> beginBackgroundTask({
    required void Function() onExpiring,
  }) async {}
  @override
  Future<void> endBackgroundTask() async {}
}

void main() {
  test('Cancel during the peer check stops the send (review L4)', () async {
    // A typed address is checked before anything is prepared; there was
    // no preparation or session yet, so Cancel did nothing and the send
    // started anyway.
    final check = Completer<ConnectTarget>();
    var prepared = false;
    final c = ProviderContainer(
      overrides: [
        keepAliveProvider.overrideWithValue(
          KeepAliveCoordinator(_NoKeepAlive(), pauseInBackground: false),
        ),
        peerCheckProvider.overrideWithValue((_) => check.future),
        appDirsProvider.overrideWith((ref) async {
          prepared = true;
          throw StateError('must not prepare after a cancel');
        }),
      ],
    );
    addTearDown(c.dispose);
    final ctrl = c.read(sendControllerProvider.notifier);
    ctrl.addShared(const [PickedFile(ref: '/tmp/x.bin', name: 'x.bin')]);

    final sending = ctrl.send(
      const ConnectTarget(host: '192.168.1.5', port: 4000),
    );
    await pumpEventQueue();
    expect(c.read(sendControllerProvider).isRunning, isTrue);
    await ctrl.cancel();
    expect(c.read(sendControllerProvider).isRunning, isFalse);

    check.complete(
      ConnectTarget(
        host: '192.168.1.5',
        port: 4000,
        fingerprint: 'a' * 64,
        pinSource: PinSource.firstContact,
      ),
    );
    await sending;
    expect(prepared, isFalse);
    final s = c.read(sendControllerProvider);
    expect(s.snapshot, isNull);
    expect(s.isRunning, isFalse);
    expect(s.picked, hasLength(1), reason: 'the selection stays');
  });
}
