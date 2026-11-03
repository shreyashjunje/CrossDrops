import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../protocol/models.dart';
import '../security/device_credentials.dart';
import '../security/fingerprint.dart';
import '../server/file_store.dart';
import 'bench.dart';
import 'bench_stats.dart' as stats;

/// What one phone manages on its own, without the network, for each step
/// a transfer goes through (review, speed item 1: measure each cost before
/// changing code; D-066). A step whose MB/s is close to the transfer's own
/// MB/s on the same phone is the limit; one far above it is not.
///
/// No plain-HTTP or hash-free transfer mode exists, not even in benchmark
/// builds, so nothing can ever fall back to an unpinned or unverified
/// connection (CLAUDE.md hard rule 4).
class PhoneLimit {
  const PhoneLimit(this.test, this.bytes, this.elapsed);

  /// One of [PhoneLimits].
  final String test;
  final int bytes;
  final Duration elapsed;

  /// 10^6 bytes per second, like every other benchmark figure.
  double get mbPerSecond => stats.mbPerSecond(bytes, elapsed);

  static String get csvHeader => 'time,platform,app_version,test,bytes,ms,mb_s';

  String toCsv({required String platform, required String appVersion}) => [
    DateTime.now().toUtc().toIso8601String(),
    platform,
    appVersion,
    test,
    bytes,
    elapsed.inMilliseconds,
    mbPerSecond.toStringAsFixed(1),
  ].join(',');
}

abstract final class PhoneLimits {
  /// SHA-256 in a background isolate, as both phones hash (pure Dart).
  static const sha256 = 'sha256';

  /// Pinned TLS 1.3 over loopback, encrypting and decrypting on two
  /// isolates: the cost of TLS and the socket stack without the radio.
  static const tls = 'tls_loopback';

  /// Writing through the store received files go to (MediaStore on
  /// Android, the app's folder on iPhone) with a checkpoint every 4 MB,
  /// as before D-065.
  static const write4mb = 'write_fsync_4mb';

  /// The same with the D-065 pace: 64 MB or 2 s.
  static const write64mb = 'write_fsync_64mb';
}

/// 1 MB of random bytes, so nothing on the way can compress them.
Uint8List _randomChunk() {
  final r = Random(1);
  return Uint8List.fromList([for (var i = 0; i < 1 << 20; i++) r.nextInt(256)]);
}

/// Hashes [bytes] (a whole number of MB) in a background isolate.
Future<PhoneLimit> measureSha256({int bytes = 256 << 20}) async {
  final micros = await Isolate.run(() {
    final chunk = _randomChunk();
    final out = _DigestSink();
    final watch = Stopwatch()..start();
    final input = sha256.startChunkedConversion(out);
    for (var done = 0; done < bytes; done += chunk.length) {
      input.add(chunk);
    }
    input.close();
    return watch.elapsedMicroseconds;
  });
  return PhoneLimit(PhoneLimits.sha256, bytes, Duration(microseconds: micros));
}

/// Sends [bytes] in [chunkSize] writes over pinned TLS 1.3 on loopback to a
/// server isolate with this phone's certificate, which discards them.
Future<PhoneLimit> measureTlsLoopback(
  DeviceCredentials credentials, {
  int bytes = 256 << 20,
  int chunkSize = defaultBenchChunk,
}) async {
  final fromServer = ReceivePort();
  // Buffers replies, so the count cannot arrive before anyone listens.
  final replies = StreamIterator(fromServer);
  Future<int> nextReply() async {
    if (!await replies.moveNext().timeout(const Duration(minutes: 2))) {
      throw StateError('TLS loopback: the server stopped');
    }
    return replies.current! as int;
  }

  final isolate = await Isolate.spawn(_tlsSink, [
    fromServer.sendPort,
    credentials.certificatePem,
    credentials.privateKeyPem,
  ]);
  try {
    final port = await nextReply();
    final socket = await SecureSocket.connect(
      InternetAddress.loopbackIPv4,
      port,
      context: SecurityContext(withTrustedRoots: false)
        ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3,
      // Pinned to our own certificate, as every CrossDrop connection is.
      onBadCertificate: (cert) => fingerprintsEqual(
        certificateFingerprint(cert.der),
        credentials.fingerprint,
      ),
    );
    final chunk = _randomChunk().sublist(0, chunkSize);
    final watch = Stopwatch()..start();
    for (var sent = 0; sent < bytes; sent += chunk.length) {
      socket.add(chunk);
      await socket.flush();
    }
    await socket.close();
    final received = await nextReply();
    final elapsed = watch.elapsed;
    socket.destroy();
    if (received != bytes) {
      throw StateError('TLS loopback: $received of $bytes bytes arrived');
    }
    return PhoneLimit(PhoneLimits.tls, bytes, elapsed);
  } finally {
    isolate.kill(priority: Isolate.immediate);
    await replies.cancel();
  }
}

const int defaultBenchChunk = 1 << 20;

Future<void> _tlsSink(List<Object?> args) async {
  final reply = args[0]! as SendPort;
  final context = SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(args[1]! as String))
    ..usePrivateKeyBytes(utf8.encode(args[2]! as String))
    ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3;
  final server = await SecureServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
    context,
  );
  reply.send(server.port);
  final socket = await server.first;
  var received = 0;
  await socket.listen((data) => received += data.length).asFuture<void>();
  reply.send(received);
  await server.close();
}

/// Writes [bytes] (1 MB at a time) through [store], the way the receiver
/// writes a part file, with a checkpoint (fsync) every [syncEvery] bytes
/// or [syncInterval]; then deletes it. [test] names the row.
Future<PhoneLimit> measureWrites(
  ReceivedFileStore store,
  String sessionDir, {
  required String test,
  required int syncEvery,
  Duration syncInterval = const Duration(days: 1),
  int bytes = 256 << 20,
}) async {
  final offer = FileOffer(
    fileId: 'limits',
    name: benchFileName(bytes, newRunId()),
    size: bytes,
  );
  final chunk = _randomChunk();
  final (part, location) = await store.open(
    store.initialLocation(sessionDir, offer),
    sessionDir: sessionDir,
    offer: offer,
  );
  try {
    final watch = Stopwatch()..start();
    var sinceSync = 0;
    final sinceSyncTime = Stopwatch()..start();
    for (var written = 0; written < bytes; written += chunk.length) {
      await part.append(chunk);
      sinceSync += chunk.length;
      if (sinceSync >= syncEvery || sinceSyncTime.elapsed >= syncInterval) {
        await part.sync();
        sinceSync = 0;
        sinceSyncTime.reset();
      }
    }
    await part.sync();
    return PhoneLimit(test, bytes, watch.elapsed);
  } finally {
    await part.close();
    await store.delete(location);
    try {
      await Directory(sessionDir).delete(recursive: true);
    } on FileSystemException {
      // Never created (MediaStore parts live elsewhere).
    }
  }
}

/// The four measurements, one after another. [tempDir] holds the write
/// test's session folder.
Future<List<PhoneLimit>> measurePhoneLimits({
  required DeviceCredentials credentials,
  required ReceivedFileStore store,
  required String tempDir,
  int bytes = 256 << 20,
  void Function(String test)? onStart,
}) async {
  final dir = p.join(tempDir, 'limits-${newRunId()}');
  final out = <PhoneLimit>[];
  onStart?.call(PhoneLimits.sha256);
  out.add(await measureSha256(bytes: bytes));
  onStart?.call(PhoneLimits.tls);
  out.add(await measureTlsLoopback(credentials, bytes: bytes));
  onStart?.call(PhoneLimits.write4mb);
  out.add(
    await measureWrites(
      store,
      dir,
      test: PhoneLimits.write4mb,
      syncEvery: 4 << 20,
      bytes: bytes,
    ),
  );
  onStart?.call(PhoneLimits.write64mb);
  out.add(
    await measureWrites(
      store,
      dir,
      test: PhoneLimits.write64mb,
      syncEvery: 64 << 20,
      syncInterval: const Duration(seconds: 2),
      bytes: bytes,
    ),
  );
  return out;
}

class _DigestSink implements Sink<Digest> {
  @override
  void add(Digest data) {}
  @override
  void close() {}
}
