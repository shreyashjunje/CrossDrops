// SendSession against a real ReceiveServer, through a flaky in-process
// proxy. No phones needed.
import 'dart:async';
import 'dart:io';

import 'package:crossdrop/core/client/upload_client.dart';
import 'package:crossdrop/core/engine/backoff.dart';
import 'package:crossdrop/core/engine/send_session.dart';
import 'package:crossdrop/core/engine/source_opener.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/device_credentials.dart';
import 'package:crossdrop/core/storage/database.dart';
import 'package:crossdrop/core/storage/transfer_repository.dart';
import 'package:crossdrop/core/storage/trust_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/flaky_proxy.dart';
import '../../support/test_receiver.dart';

const sender = testSender;

void main() {
  late DeviceCredentials identity;
  late DeviceCredentials me;
  late Directory src;
  late TestReceiver r;
  late FlakyProxy proxy;

  setUpAll(() async {
    identity = await DeviceCredentials.generate();
    me = await testSenderCredentials();
  });

  setUp(() async {
    src = Directory.systemTemp.createTempSync('cd_src');
    r = await TestReceiver.start(
      identity: identity,
      bodyIdleTimeout: const Duration(seconds: 2),
    );
    proxy = await FlakyProxy.start(r.port);
  });

  tearDown(() async {
    await proxy.close();
    await r.close();
    src.deleteSync(recursive: true);
  });

  /// Fast retries so tests take seconds, not minutes.
  Backoff fastBackoff({Duration giveUp = const Duration(seconds: 30)}) =>
      Backoff(
        steps: const [
          Duration(milliseconds: 20),
          Duration(milliseconds: 40),
          Duration(milliseconds: 80),
          Duration(milliseconds: 160),
        ],
        giveUpAfter: giveUp,
      );

  UploadClient quickClient(String host, int port) => UploadClient(
    host: host,
    port: port,
    fingerprint: identity.fingerprint,
    credentials: me,
    connectTimeout: const Duration(seconds: 2),
    stallTimeout: const Duration(seconds: 2),
  );

  SendSession session(
    List<SendItem> items, {
    int? port,
    Duration giveUp = const Duration(seconds: 30),
    TransferRepository? repo,
    PeerLocator? locate,
    ClientFactory? clientFactory,
    SourceOpener? opener,
  }) => SendSession(
    host: '127.0.0.1',
    port: port ?? proxy.port,
    sender: sender,
    items: items,
    receiverFingerprint: identity.fingerprint,
    credentials: me,
    expectedDeviceId: testDeviceInfo.id,
    repository: repo,
    locate: locate,
    clientFactory: clientFactory ?? quickClient,
    backoff: () => fastBackoff(giveUp: giveUp),
    pollInterval: const Duration(milliseconds: 50),
    opener: opener,
  );

  Future<(SendItem, String)> makeFile(
    String name,
    int size, {
    int seed = 1,
  }) async {
    final path = p.join(src.path, name);
    final sha = await writeRandomFile(path, size, seed: seed);
    return (SendItem(path: path, name: name, size: size), sha);
  }

  Future<void> expectSavedMatches(Map<String, String> shaByName) async {
    expect(r.saved, hasLength(shaByName.length));
    for (final saved in r.saved) {
      final name = p.basename(saved.savedPath);
      expect(await hashFile(saved.savedPath), shaByName[name], reason: name);
    }
  }

  test('sends several files one after another and both sides agree', () async {
    final files = [
      await makeFile('a.jpg', 3 * mb + 1, seed: 1),
      await makeFile('b.mov', 5 * mb, seed: 2),
      await makeFile('c.txt', 0),
    ];
    final s = session([for (final f in files) f.$1]);
    final phases = <SendPhase>{};
    s.updates.listen((u) => phases.add(u.phase));

    final result = await s.run();

    expect(result.phase, SendPhase.done, reason: result.reason);
    expect(result.savedCount, 3);
    expect(result.sentBytes, result.totalBytes);
    expect(
      phases,
      containsAll([SendPhase.waitingForAccept, SendPhase.sending]),
    );
    await expectSavedMatches({for (final f in files) f.$1.name: f.$2});
    expect(r.server.sessions.single.status, SessionStatus.done);
  });

  group('flaky network', () {
    for (final seed in [1, 2, 3]) {
      test('resumes after drops at random points (seed $seed)', () async {
        final (item, sha) = await makeFile('v.mp4', 40 * mb, seed: seed);
        final (small, smallSha) = await makeFile('s.jpg', 300 * 1024);
        proxy.dropEvery = (min: 1 * mb, max: 9 * mb);
        proxy.latency = const Duration(milliseconds: 1);
        final s = session([item, small]);

        final result = await s.run();

        expect(result.phase, SendPhase.done, reason: result.reason);
        expect(proxy.drops, greaterThanOrEqualTo(3));
        await expectSavedMatches({'v.mp4': sha, 's.jpg': smallSha});
      }, timeout: const Timeout(Duration(minutes: 3)));
    }

    test(
      'a link that goes silent (no reset) is detected and resumed',
      () async {
        final (item, sha) = await makeFile('v.mp4', 20 * mb);
        final s = session([item]);
        // Wi-Fi off mid-transfer: packets vanish, nothing closes.
        var tripped = false;
        s.updates.listen((u) {
          if (!tripped && u.sentBytes > 5 * mb) {
            tripped = true;
            proxy.blackhole = true;
            Timer(const Duration(seconds: 3), () {
              proxy.blackhole = false;
              proxy.dropAll(); // the dead sockets finally reset
            });
          }
        });
        final result = await s.run();
        expect(result.phase, SendPhase.done, reason: result.reason);
        await expectSavedMatches({'v.mp4': sha});
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'gives up after the deadline and resumes from the database later',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final repo = TransferRepository(db);
        final (item, sha) = await makeFile('v.mp4', 12 * mb);
        final s = session(
          [item],
          repo: repo,
          giveUp: const Duration(milliseconds: 1500),
        );
        // Wi-Fi gone for good after 5 MB.
        proxy.onDrop = () => proxy.refuse = true;
        proxy.dropAt(5 * mb);

        final first = await s.run();
        expect(first.phase, SendPhase.failed);
        expect(first.reason, SendReasons.network);
        expect(first.canResume, isTrue);
        final stored = (await repo.unfinished(TransferDirection.send)).single;
        expect(stored.status, SessionStatus.paused);
        expect(stored.files.single.sourcePath, item.path);

        // "App restart": a new SendSession from the stored row.
        proxy.onDrop = null;
        proxy.refuse = false;
        final again = SendSession.resume(
          stored,
          sender: sender,
          credentials: me,
          repository: repo,
          clientFactory: quickClient,
          backoff: fastBackoff,
        );
        final result = await again.run();
        expect(result.phase, SendPhase.done, reason: result.reason);
        await expectSavedMatches({'v.mp4': sha});
        expect(await repo.unfinished(TransferDirection.send), isEmpty);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('follows the receiver to a new port after its app restarts', () async {
      final (item, sha) = await makeFile('v.mp4', 16 * mb);
      final s = session(
        [item],
        port: r.port,
        locate: () async => (host: '127.0.0.1', port: r.port),
      );
      var restarted = false;
      s.updates.listen((u) {
        if (!restarted && u.sentBytes > 6 * mb) {
          restarted = true;
          // Killed and relaunched on a new random port.
          unawaited(r.restart(port: 0));
        }
      });
      final result = await s.run();
      expect(restarted, isTrue);
      expect(result.phase, SendPhase.done, reason: result.reason);
      expect(await hashFile(r.saved.single.savedPath), sha);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  test('many small files over one connection', () async {
    final items = <SendItem>[];
    final shas = <String, String>{};
    for (var i = 0; i < 150; i++) {
      final (item, sha) = await makeFile('IMG_$i.jpg', 1000 + i * 337, seed: i);
      items.add(item);
      shas[item.name] = sha;
    }
    final result = await session(items).run();
    expect(result.phase, SendPhase.done, reason: result.reason);
    expect(result.savedCount, 150);
    await expectSavedMatches(shas);
    // HTTP keep-alive: a handful of connections, not one per file.
    expect(proxy.connections, lessThan(10));
  }, timeout: const Timeout(Duration(minutes: 2)));

  group('security', () {
    test(
      'receiving off: an untrusted sender is rejected, nothing sent',
      () async {
        r.acceptsUntrusted = false;
        final (item, _) = await makeFile('a.bin', mb);
        final result = await session([item]).run();
        expect(result.phase, SendPhase.rejected);
        expect(result.reason, ErrorCodes.receivingOff);
        expect(r.server.sessions, isEmpty);
      },
    );

    test('an untrusted sender sees the same code as the receiver', () async {
      String? shown;
      r.decider = (o) async {
        shown = o.pairingCode;
        return true;
      };
      final (item, _) = await makeFile('a.bin', 1000);
      final s = session([item]);
      String? code;
      final sub = s.updates.listen((u) {
        if (u.phase == SendPhase.waitingForAccept) code ??= u.pairingCode;
      });
      final result = await s.run();
      await sub.cancel();
      expect(result.phase, SendPhase.done);
      expect(code, isNotNull);
      expect(code, shown);
    });

    test('a receiver with another key stops the send, never retried', () async {
      final other = await DeviceCredentials.generate();
      final (item, _) = await makeFile('a.bin', 1000);
      final s = SendSession(
        host: '127.0.0.1',
        port: proxy.port,
        sender: sender,
        items: [item],
        receiverFingerprint: other.fingerprint,
        credentials: me,
        backoff: fastBackoff,
      );
      final result = await s.run();
      expect(result.phase, SendPhase.failed);
      expect(result.reason, SendReasons.pinMismatch);
      expect(r.server.sessions, isEmpty);
    });
  });

  group('integrity', () {
    test('hash mismatch restarts the file once and then it succeeds', () async {
      final (item, sha) = await makeFile('a.bin', 3 * mb);
      var corrupt = 1;
      final s = session(
        [item],
        clientFactory: (h, port) =>
            _CorruptingClient(h, port, identity, me, () => corrupt-- > 0),
      );
      final result = await s.run();
      expect(result.phase, SendPhase.done, reason: result.reason);
      await expectSavedMatches({'a.bin': sha});
      final stored = await r.repo.find(
        r.server.sessions.single.sessionId,
        TransferDirection.receive,
      );
      expect(stored!.files.single.hashAttempts, 1);
    });

    test('a second mismatch fails that file; the others are saved', () async {
      final (bad, _) = await makeFile('bad.bin', 1 * mb, seed: 5);
      final (good, goodSha) = await makeFile('good.bin', 1 * mb, seed: 6);
      final s = session(
        [bad, good],
        clientFactory: (h, port) => _CorruptingClient(
          h,
          port,
          identity,
          me,
          () => true,
          onlyFile: 'f0',
        ),
      );
      final result = await s.run();
      expect(result.phase, SendPhase.done);
      expect(result.files[0].status, FileTransferStatus.failed);
      expect(result.files[1].status, FileTransferStatus.saved);
      await expectSavedMatches({'good.bin': goodSha});
    });

    test('a source that changed size is refused before offering', () async {
      final (item, _) = await makeFile('a.bin', 1000);
      final wrong = SendItem(path: item.path, name: 'a.bin', size: 5000);
      final result = await session([wrong]).run();
      expect(result.phase, SendPhase.failed);
      expect(result.reason, SendReasons.sourceUnreadable);
      expect(r.server.sessions, isEmpty);
    });
  });

  group('content URIs through a SourceOpener', () {
    test('each source is opened for its file and always closed', () async {
      final a = await makeFile('a.jpg', 2 * mb + 3, seed: 4);
      final b = await makeFile('b.mov', 3 * mb, seed: 5);
      final opener = _MappedOpener({
        'content://media/1': a.$1.path,
        'content://media/2': b.$1.path,
      });
      final s = session([
        SendItem(path: 'content://media/1', name: 'a.jpg', size: a.$1.size),
        SendItem(path: 'content://media/2', name: 'b.mov', size: b.$1.size),
      ], opener: opener);

      final result = await s.run();

      expect(result.phase, SendPhase.done, reason: result.reason);
      await expectSavedMatches({'a.jpg': a.$2, 'b.mov': b.$2});
      expect(opener.openNow, 0, reason: 'every source closed');
      expect(opener.maxOpen, 1, reason: 'one file at a time');
    });

    test('a permission revoked mid-session stops the send', () async {
      final a = await makeFile('a.jpg', 1000, seed: 6);
      final b = await makeFile('b.jpg', 1000, seed: 7);
      final opener = _MappedOpener({
        'content://x/1': a.$1.path,
        'content://x/2': b.$1.path,
      }, failAfter: 3); // 2 checks before the offer, then file 1 only
      final result = await session([
        SendItem(path: 'content://x/1', name: 'a.jpg', size: 1000),
        SendItem(path: 'content://x/2', name: 'b.jpg', size: 1000),
      ], opener: opener).run();

      expect(result.phase, SendPhase.failed);
      expect(result.reason, SendReasons.sourceUnreadable);
      expect(opener.openNow, 0);
    });
  });

  group('cancel and reject', () {
    test('declined by the receiver', () async {
      r.decider = (_) async => false;
      final (item, _) = await makeFile('a.bin', 1000);
      final result = await session([item]).run();
      expect(result.phase, SendPhase.rejected);
      expect(result.reason, RejectReasons.declined);
    });

    test('no space on the receiver', () async {
      r.freeBytes = 1 * mb;
      final (item, _) = await makeFile('a.bin', 2 * mb);
      final result = await session([item]).run();
      expect(result.phase, SendPhase.rejected);
      expect(result.reason, RejectReasons.noSpace);
      expect(result.neededBytes, 2 * mb);
    });

    test('cancel while connecting ends cancelled, not network', () async {
      // Review M5: killing the connection made info() fail as `network`.
      final (item, _) = await makeFile('a.bin', 1000);
      proxy.latency = const Duration(seconds: 1);
      final s = session([item]);
      final run = s.run();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await s.cancel();
      final result = await run;
      expect(result.phase, SendPhase.cancelled);
      expect(result.reason, 'sender');
      expect(r.server.sessions, isEmpty);
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('cancel while the offer is on its way withdraws it', () async {
      // Review M5: the offer reached the receiver but the sender never
      // learned its id, so no DELETE was sent; an Accept then waited for
      // bytes that never came.
      final (item, _) = await makeFile('a.bin', 1000);
      final gate = Completer<void>();
      r.trustLookup = (_, _) async {
        await gate.future;
        return PeerTrust.unknown;
      };
      final s = session([item]);
      final run = s.run();
      await waitFor(() => s.snapshot.phase == SendPhase.connecting);
      // Give info() and the source checks time; the offer then waits in
      // the receiver's trust lookup.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await s.cancel();
      gate.complete();
      final result = await run;
      expect(result.phase, SendPhase.cancelled);
      expect(result.reason, 'sender');
      await waitFor(() => r.server.sessions.isNotEmpty);
      await waitFor(
        () => r.server.sessions.single.status == SessionStatus.cancelled,
      );
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('sender cancels while waiting for Accept', () async {
      r.decider = (_) => Completer<bool>().future;
      final (item, _) = await makeFile('a.bin', 1000);
      final s = session([item]);
      final run = s.run();
      await waitFor(() => s.snapshot.phase == SendPhase.waitingForAccept);
      await s.cancel();
      final result = await run;
      expect(result.phase, SendPhase.cancelled);
      expect(r.server.sessions.single.status, SessionStatus.cancelled);
    });

    test(
      'sender cancels while sending: receiver deletes the partial',
      () async {
        final (item, _) = await makeFile('v.mp4', 30 * mb);
        proxy.latency = const Duration(milliseconds: 2);
        final s = session([item]);
        final run = s.run();
        await waitFor(() => s.snapshot.sentBytes > 3 * mb);
        await s.cancel();
        final result = await run;
        expect(result.phase, SendPhase.cancelled);
        expect(result.reason, 'sender');
        final sid = result.sessionId!;
        await waitFor(
          () => r.server.sessions.single.status == SessionStatus.cancelled,
        );
        await waitFor(() => !Directory(p.join(r.tempDir, sid)).existsSync());
        expect(r.saved, isEmpty);
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test('receiver cancels while sending', () async {
      final (item, _) = await makeFile('v.mp4', 30 * mb);
      proxy.latency = const Duration(milliseconds: 2);
      final s = session([item]);
      final run = s.run();
      await waitFor(() => s.snapshot.sentBytes > 3 * mb);
      await r.server.cancel(s.sessionId!);
      final result = await run;
      expect(result.phase, SendPhase.cancelled);
      expect(result.reason, 'receiver');
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('sender cancels while retrying', () async {
      final (item, _) = await makeFile('v.mp4', 10 * mb);
      final s = session([item]);
      proxy.onDrop = () => proxy.refuse = true;
      proxy.dropAt(3 * mb);
      final run = s.run();
      await waitFor(() => s.snapshot.phase == SendPhase.retrying);
      await s.cancel();
      final result = await run;
      expect(result.phase, SendPhase.cancelled);
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('cancel while paused, and after done is a no-op', () async {
      final (item, _) = await makeFile('v.mp4', 20 * mb);
      proxy.latency = const Duration(milliseconds: 2);
      final s = session([item]);
      final run = s.run();
      await waitFor(() => s.snapshot.sentBytes > 2 * mb);
      s.pause();
      await waitFor(() => s.snapshot.phase == SendPhase.paused);
      await s.cancel();
      expect((await run).phase, SendPhase.cancelled);
      await s.cancel(); // finished: nothing happens

      final (small, _) = await makeFile('s.bin', 10);
      final done = session([small]);
      expect((await done.run()).phase, SendPhase.done);
      await done.cancel();
      expect(done.snapshot.phase, SendPhase.done);
    }, timeout: const Timeout(Duration(minutes: 1)));
  });

  test('pause stops after the current chunk; resume finishes', () async {
    final (item, sha) = await makeFile('v.mp4', 24 * mb);
    proxy.latency = const Duration(milliseconds: 2);
    final s = session([item]);
    final run = s.run();
    await waitFor(() => s.snapshot.sentBytes > 3 * mb);
    s.pause();
    await waitFor(() => s.snapshot.phase == SendPhase.paused);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final heldAt = proxy.upBytes;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(proxy.upBytes - heldAt, lessThan(64 * 1024), reason: 'no bytes');
    expect(r.server.sessions.single.status, SessionStatus.paused);
    s.resume();
    final result = await run;
    expect(result.phase, SendPhase.done, reason: result.reason);
    await expectSavedMatches({'v.mp4': sha});
  }, timeout: const Timeout(Duration(minutes: 1)));

  group('pause between uploads (review M4)', () {
    test('a pause while the file status is fetched is not lost', () async {
      final (item, sha) = await makeFile('v.mp4', 8 * mb);
      late SendSession s;
      var pausedOnce = false;
      s = session(
        [item],
        clientFactory: (h, port) => _HookedClient(
          host: h,
          port: port,
          fingerprint: identity.fingerprint,
          credentials: me,
          onFileStatus: () {
            if (pausedOnce) return;
            pausedOnce = true;
            unawaited(s.pause());
          },
        ),
      );
      final run = s.run();
      await waitFor(() => pausedOnce && s.snapshot.phase == SendPhase.paused);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final file = r.server.sessions.single.files.single;
      expect(file.receivedBytes, 0, reason: 'nothing sent while paused');
      expect(s.snapshot.phase, SendPhase.paused);
      s.resume();
      final result = await run;
      expect(result.phase, SendPhase.done, reason: result.reason);
      await expectSavedMatches({'v.mp4': sha});
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('pause() completes once the running upload stopped', () async {
      final (item, sha) = await makeFile('v.mp4', 24 * mb);
      proxy.latency = const Duration(milliseconds: 2);
      final s = session([item]);
      final run = s.run();
      await waitFor(() => s.snapshot.sentBytes > 3 * mb);
      // Used to wait for an update that pause() had already sent, so the
      // iOS background task always took its full 10 s.
      await s.pause().timeout(const Duration(seconds: 5));
      expect(s.snapshot.phase, SendPhase.paused);
      // Bytes already in the socket buffers and the proxy still drain.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final heldAt = proxy.upBytes;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(proxy.upBytes - heldAt, lessThan(64 * 1024), reason: 'no bytes');
      s.resume();
      expect((await run).phase, SendPhase.done);
      await expectSavedMatches({'v.mp4': sha});
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('pause() while waiting for Accept completes at once', () async {
      final (item, _) = await makeFile('a.bin', 10);
      final answer = Completer<bool>();
      r.decider = (_) => answer.future;
      final s = session([item]);
      final run = s.run();
      await waitFor(() => s.snapshot.phase == SendPhase.waitingForAccept);
      await s.pause().timeout(const Duration(milliseconds: 200));
      s.resume();
      answer.complete(true);
      expect((await run).phase, SendPhase.done);
    });

    test('UploadClient keeps a pause asked before the PUT', () async {
      final (item, _) = await makeFile('a.bin', 2 * mb);
      final c = clientFor(r, me);
      addTearDown(c.close);
      final t = await c.offerFile(item.path);
      c.requestPause();
      await expectLater(
        c.put(t, 0),
        throwsA(isA<UploadException>().having((e) => e.code, 'code', 'paused')),
      );
      expect(r.server.sessions.single.files.single.receivedBytes, 0);
      // One request stops one upload; the next runs.
      final status = await c.put(t, 0);
      expect(status.receivedBytes, 2 * mb);
    });
  });

  test('progress, speed and time left are reported', () async {
    final (item, _) = await makeFile('v.mp4', 20 * mb);
    proxy.latency = const Duration(milliseconds: 1);
    final s = session([item]);
    final seen = <SendSnapshot>[];
    s.updates.listen(seen.add);
    await s.run();
    final sending = seen.where((u) => u.phase == SendPhase.sending).toList();
    expect(sending.any((u) => u.bytesPerSecond > 0), isTrue);
    expect(sending.any((u) => u.eta != null), isTrue);
    for (var i = 1; i < sending.length; i++) {
      expect(
        sending[i].sentBytes,
        greaterThanOrEqualTo(sending[i - 1].sentBytes),
      );
    }
    expect(seen.last.fraction, 1);
  }, timeout: const Timeout(Duration(minutes: 1)));
}

/// Sends a wrong SHA-256 while [corrupt] says so.
class _CorruptingClient extends UploadClient {
  _CorruptingClient(
    String host,
    int port,
    DeviceCredentials receiver,
    DeviceCredentials sender,
    this.corrupt, {
    this.onlyFile,
  }) : super(
         host: host,
         port: port,
         fingerprint: receiver.fingerprint,
         credentials: sender,
         connectTimeout: const Duration(seconds: 2),
         stallTimeout: const Duration(seconds: 2),
       );

  final bool Function() corrupt;
  final String? onlyFile;

  @override
  Future<void> complete(UploadTarget t, String sha) {
    final hit = (onlyFile == null || t.fileId == onlyFile) && corrupt();
    return super.complete(t, hit ? '0' * 64 : sha);
  }
}

/// Maps fake content URIs to temp files and counts open descriptors.
class _MappedOpener implements SourceOpener {
  _MappedOpener(this.map, {this.failAfter});

  final Map<String, String> map;
  final int? failAfter;
  int opens = 0;
  int openNow = 0;
  int maxOpen = 0;

  @override
  Future<OpenedSource> open(String ref) async {
    opens++;
    final path = map[ref];
    if (path == null || (failAfter != null && opens > failAfter!)) {
      throw const SourceUnavailable('permission revoked');
    }
    final o = await const FileSourceOpener().open(path);
    openNow++;
    if (openNow > maxOpen) maxOpen = openNow;
    return OpenedSource(o.source, o.length, () async => openNow--);
  }
}

/// Calls [onFileStatus] after each `GET .../files/{id}` reply, before the
/// session goes on to the PUT.
class _HookedClient extends UploadClient {
  _HookedClient({
    required super.host,
    required super.port,
    required super.fingerprint,
    required super.credentials,
    required this.onFileStatus,
  }) : super(
         connectTimeout: const Duration(seconds: 2),
         stallTimeout: const Duration(seconds: 2),
       );

  final void Function() onFileStatus;

  @override
  Future<FileStatus> fileStatus(UploadTarget t) async {
    final s = await super.fileStatus(t);
    onFileStatus();
    return s;
  }
}
