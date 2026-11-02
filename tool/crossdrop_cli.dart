// Dev tool for testing a phone against this computer, no second phone needed.
// Not part of the app. Uses the same server and client code as the app.
//
//   dart run tool/crossdrop_cli.dart receive [--port 8443] [--dir received]
//   dart run tool/crossdrop_cli.dart send <ip> <port> <file>
//
// The client accepts any certificate until Phase 4 (see D-011), and the
// receiver accepts every offer without asking.
import 'dart:async';
import 'dart:io';

import 'package:crossdrop/core/client/upload_client.dart';
import 'package:crossdrop/core/engine/chunked_reader.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:crossdrop/core/security/device_credentials.dart';
import 'package:crossdrop/core/security/peer_auth.dart';
import 'package:crossdrop/core/security/pinning.dart';
import 'package:crossdrop/core/server/receive_server.dart';
import 'package:crossdrop/core/storage/database.dart';
import 'package:crossdrop/core/storage/transfer_repository.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  if (args.isEmpty) return _usage();
  switch (args.first) {
    case 'receive':
      await _receive(args.skip(1).toList());
    case 'send':
      await _send(args.skip(1).toList());
    default:
      _usage();
  }
}

void _usage() {
  stdout.writeln('''
Usage:
  dart run tool/crossdrop_cli.dart receive [--port 8443] [--dir received]
  dart run tool/crossdrop_cli.dart send <ip> <port> <file>''');
  exitCode = 64;
}

Future<void> _receive(List<String> args) async {
  var port = 8443;
  var dir = 'received';
  for (var i = 0; i + 1 < args.length; i += 2) {
    if (args[i] == '--port') port = int.parse(args[i + 1]);
    if (args[i] == '--dir') dir = args[i + 1];
  }
  final saveDir = p.absolute(dir);
  final tempDir = p.join(Directory.systemTemp.path, 'crossdrop_cli_incoming');
  // A new identity per run: the CLI is a dev tool and trusts nobody.
  final identity = await DeviceCredentials.generate();
  final server = await ReceiveServer.start(
    info: DeviceInfo(
      id: newDeviceId(),
      name: 'CrossDrop CLI',
      platform: 'android',
    ),
    credentials: identity,
    tempDir: tempDir,
    saveDir: saveDir,
    // A throwaway database: the CLI keeps no history.
    repository: TransferRepository(AppDatabase(NativeDatabase.memory())),
    // Dev tool on your own computer: accept every offer, and say so.
    decider: (offer) async {
      stdout.writeln(
        'Accepting ${offer.files.length} file(s) automatically. '
        'Pairing code: ${formatPairingCode(offer.pairingCode)}',
      );
      return true;
    },
    port: port,
  );
  stdout.writeln('Receiving on port ${server.port}. Saving to $saveDir');
  stdout.writeln(
    'Type this PC\'s Wi-Fi IP and the port into Send on the phone:',
  );
  for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
    for (final a in i.addresses) {
      stdout.writeln('  ${a.address}   (${i.name})');
    }
  }
  stdout.writeln('Ctrl+C to stop.\n');

  final started = <String, Stopwatch>{};
  var lastPrint = Stopwatch()..start();
  await for (final e in server.events) {
    switch (e) {
      case SessionOffered(:final files):
        stdout.writeln(
          'Incoming: ${files.length} file(s), '
          '${files.first.size} bytes',
        );
      case FileProgress(:final sessionId, :final receivedBytes, :final size):
        final watch = started.putIfAbsent(sessionId, Stopwatch.new)..start();
        if (lastPrint.elapsedMilliseconds > 500 || receivedBytes == size) {
          lastPrint = Stopwatch()..start();
          final secs = watch.elapsedMilliseconds / 1000;
          final mbs = secs > 0 ? receivedBytes / 1e6 / secs : 0;
          stdout.write(
            '\r  ${(receivedBytes * 100 ~/ (size == 0 ? 1 : size))}%  '
            '${(receivedBytes / 1e6).toStringAsFixed(1)} MB  '
            '${mbs.toStringAsFixed(1)} MB/s (avg this upload)   ',
          );
        }
      case FileSaved(:final savedPath, :final size):
        stdout.writeln('\nSaved $savedPath ($size bytes), SHA-256 verified');
        stdout.writeln(
          '  SHA-256 of saved file: ${await _hashFile(savedPath)}',
        );
      case FileFailed(:final code):
        stdout.writeln('\nFailed: $code');
      case SessionStateChanged(:final status, :final reason):
        stdout.writeln(
          '\nSession ${status.name}${reason == null ? '' : ' ($reason)'}',
        );
      case OfferRefused(:final reason):
        stdout.writeln('Refused an offer: $reason');
    }
  }
}

Future<void> _send(List<String> args) async {
  if (args.length != 3) return _usage();
  final host = args[0];
  final port = int.parse(args[1]);
  final path = args[2];
  if (!File(path).existsSync()) {
    stderr.writeln('File not found: $path');
    exitCode = 66;
    return;
  }
  // First contact: pin whatever certificate answers, then compare the
  // pairing code with the phone's Accept prompt.
  final fingerprint = await probeFingerprint(host, port);
  final client = UploadClient(
    host: host,
    port: port,
    fingerprint: fingerprint,
    credentials: await DeviceCredentials.generate(),
  );
  try {
    final pending = client.offerFile(path);
    // The code is known once the offer is authenticated.
    unawaited(
      Future<void>.delayed(const Duration(seconds: 1), () {
        final code = client.pairingCode;
        if (code != null) {
          stdout.writeln('Pairing code: ${formatPairingCode(code)}');
        }
      }),
    );
    final target = await pending;
    final watch = Stopwatch()..start();
    var lastPrint = 0;
    final sha = await client.transfer(
      target,
      onProgress: (pr) {
        if (watch.elapsedMilliseconds - lastPrint > 500 || pr.fraction == 1) {
          lastPrint = watch.elapsedMilliseconds;
          stdout.write(
            '\r  ${(pr.fraction * 100).toStringAsFixed(0)}%  '
            '${(pr.sentBytes / 1e6).toStringAsFixed(1)} MB  '
            '${(pr.bytesPerSecond / 1e6).toStringAsFixed(1)} MB/s   ',
          );
        }
      },
    );
    watch.stop();
    final secs = watch.elapsedMilliseconds / 1000;
    stdout.writeln(
      '\nDone, SHA-256 verified by receiver.\n'
      '  Time ${secs.toStringAsFixed(1)} s, average '
      '${(target.size / 1e6 / secs).toStringAsFixed(1)} MB/s\n'
      '  SHA-256: $sha',
    );
  } on UploadException catch (e) {
    stderr.writeln('\nFailed: $e');
    exitCode = 1;
  } finally {
    client.close();
  }
}

Future<String> _hashFile(String path) async {
  final out = _Sink();
  final hash = sha256.startChunkedConversion(out);
  await for (final chunk in readFileChunks(path)) {
    hash.add(chunk);
  }
  hash.close();
  return out.value.toString();
}

class _Sink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
