import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crossdrop/core/engine/chunked_reader.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/ephemeral_identity.dart';
import 'package:crossdrop/core/server/receive_server.dart';
import 'package:crossdrop/core/storage/database.dart';
import 'package:crossdrop/core/storage/transfer_repository.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

const int mb = 1024 * 1024;

const testDeviceInfo = DeviceInfo(
  id: '00000000-0000-4000-8000-000000000000',
  name: 'Test receiver',
  platform: 'android',
);

const testSender = SenderInfo(
  id: '11111111-1111-4111-8111-111111111111',
  name: 'Test sender',
  platform: 'ios',
);

/// A receiver running on loopback with its own in-memory database and
/// folders, as the app would run it. Restartable, to test app restarts.
class TestReceiver {
  TestReceiver._(this.root, this.identity, this.db);

  final Directory root;
  final EphemeralIdentity identity;
  AppDatabase db;
  late ReceiveServer server;
  final List<ReceiveEvent> events = [];
  StreamSubscription<ReceiveEvent>? _sub;

  /// Answers the Accept prompt. Default: accept at once.
  OfferDecider decider = (_) async => true;

  /// Free bytes to report, or null for "unknown".
  int? freeBytes;

  String get tempDir => p.join(root.path, 'tmp');
  String get saveDir => p.join(root.path, 'save');
  TransferRepository get repo => TransferRepository(db);
  int get port => server.port;

  static Future<TestReceiver> start({
    required EphemeralIdentity identity,
    Duration bodyIdleTimeout = const Duration(seconds: 15),
    Duration acceptTimeout = const Duration(seconds: 60),
    int checkpointBytes = 4 * mb,
    OfferDecider? decider,
    int? freeBytes,
  }) async {
    final r = TestReceiver._(
      Directory.systemTemp.createTempSync('cd_recv'),
      identity,
      AppDatabase(NativeDatabase.memory()),
    );
    if (decider != null) r.decider = decider;
    r.freeBytes = freeBytes;
    await r._startServer(bodyIdleTimeout, acceptTimeout, checkpointBytes);
    return r;
  }

  Future<void> _startServer(
    Duration bodyIdleTimeout,
    Duration acceptTimeout,
    int checkpointBytes, {
    int port = 0,
  }) async {
    server = await ReceiveServer.start(
      info: testDeviceInfo,
      securityContext: identity.serverContext(),
      tempDir: tempDir,
      saveDir: saveDir,
      repository: repo,
      decider: (o) => decider(o),
      freeSpace: (_) async => freeBytes,
      address: InternetAddress.loopbackIPv4,
      port: port,
      bodyIdleTimeout: bodyIdleTimeout,
      acceptTimeout: acceptTimeout,
      checkpointBytes: checkpointBytes,
    );
    _sub = server.events.listen(events.add);
  }

  /// Stops the server as if the app were killed, keeping the database and
  /// files, then starts it again on [port] (default: same port).
  Future<void> restart({
    int? port,
    Duration bodyIdleTimeout = const Duration(seconds: 15),
  }) async {
    final old = server.port;
    await _sub?.cancel();
    await server.close();
    events.clear();
    await _startServer(
      bodyIdleTimeout,
      const Duration(seconds: 60),
      4 * mb,
      port: port ?? old,
    );
  }

  List<FileSaved> get saved => events.whereType<FileSaved>().toList();

  Future<void> close() async {
    await _sub?.cancel();
    await server.close();
    await db.close();
    root.deleteSync(recursive: true);
  }
}

/// Writes [size] pseudo-random bytes in 1 MB chunks and returns the SHA-256.
Future<String> writeRandomFile(String path, int size, {int seed = 42}) async {
  final sink = File(path).openWrite();
  final out = DigestSink();
  final hash = sha256.startChunkedConversion(out);
  final rnd = Random(seed);
  for (var written = 0; written < size; written += mb) {
    final n = min(mb, size - written);
    final chunk = Uint8List(n);
    for (var i = 0; i < n; i += 4) {
      final v = rnd.nextInt(1 << 32);
      for (var j = 0; j < 4 && i + j < n; j++) {
        chunk[i + j] = (v >> (8 * j)) & 0xff;
      }
    }
    sink.add(chunk);
    hash.add(chunk);
  }
  await sink.close();
  hash.close();
  return out.value.toString();
}

Future<String> hashFile(String path) async {
  final out = DigestSink();
  final hash = sha256.startChunkedConversion(out);
  await for (final chunk in readFileChunks(path)) {
    hash.add(chunk);
  }
  hash.close();
  return out.value.toString();
}

class DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Polls [condition] every 20 ms until it holds or [timeout] passes.
Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('waitFor: ${reason ?? 'condition'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
