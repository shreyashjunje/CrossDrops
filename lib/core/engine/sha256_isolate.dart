import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'chunked_reader.dart';

/// Incremental SHA-256 computed in a background isolate, so hashing never
/// blocks the UI isolate (CLAUDE.md hard rule 3).
///
/// Chunks are handed over with [TransferableTypedData]. At most
/// [maxInFlight] chunks wait in the worker; [add] waits beyond that, so a
/// slow hasher slows the stream instead of growing memory.
class Sha256Isolate {
  Sha256Isolate._(
    this._isolate,
    this._toWorker,
    this._fromWorker,
    Stream<Object?> messages,
    this.maxInFlight,
  ) {
    messages.listen(_onMessage);
  }

  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;
  final int maxInFlight;

  int _inFlight = 0;
  Completer<void>? _slot;
  Completer<String>? _digest;
  Object? _error;
  bool _closed = false;
  bool _aborted = false;

  static Future<Sha256Isolate> spawn({int maxInFlight = 4}) async {
    final fromWorker = ReceivePort();
    final isolate = await Isolate.spawn(
      _workerMain,
      fromWorker.sendPort,
      debugName: 'sha256',
    );
    // The first message is the worker's SendPort; the rest go to _onMessage.
    // The worker sends nothing else until it receives work.
    final messages = fromWorker.asBroadcastStream();
    final toWorker = await messages.first as SendPort;
    return Sha256Isolate._(
      isolate,
      toWorker,
      fromWorker,
      messages,
      maxInFlight,
    );
  }

  void _onMessage(Object? msg) {
    if (msg == 'ack') {
      _inFlight--;
      final slot = _slot;
      if (slot != null && _inFlight < maxInFlight) {
        _slot = null;
        slot.complete();
      }
    } else if (msg is List && msg.length == 2 && msg[0] == 'digest') {
      _digest?.complete(msg[1] as String);
      _dispose();
    } else if (msg is List && msg.length == 2 && msg[0] == 'error') {
      _fail(StateError('sha256 worker: ${msg[1]}'));
    }
  }

  void _fail(Object error) {
    _error = error;
    _slot?.completeError(error);
    _slot = null;
    _digest?.completeError(error);
    _digest = null;
    _dispose();
  }

  /// Hashes bytes [0, length) of [path], read from disk inside the worker.
  /// Used on resume to rebuild the hash state of bytes sent or received
  /// earlier.
  Future<void> addFilePrefix(String path, int length) async {
    if (length <= 0) return;
    await _send(['file', path, length]);
  }

  /// Adds [chunk] to the hash. Waits if too many chunks are in flight.
  Future<void> add(Uint8List chunk) async {
    if (chunk.isEmpty) return;
    await _send([
      'chunk',
      TransferableTypedData.fromList([chunk]),
    ]);
  }

  Future<void> _send(Object message) async {
    if (_aborted) return;
    _checkUsable();
    while (_inFlight >= maxInFlight) {
      await (_slot ??= Completer<void>()).future;
      if (_aborted) return;
      _checkUsable();
    }
    _inFlight++;
    _toWorker.send(message);
  }

  /// Returns the lowercase hex digest and stops the worker.
  Future<String> close() {
    _checkUsable();
    _closed = true;
    final digest = _digest = Completer<String>();
    _toWorker.send(['close']);
    return digest.future;
  }

  /// Stops the worker without a digest. Later [add] and [addFilePrefix]
  /// calls are ignored, so a producer that is still running when its
  /// transfer is cancelled does not fail.
  void abort() {
    if (_aborted) return;
    _aborted = true;
    _closed = true;
    final slot = _slot;
    _slot = null;
    slot?.complete();
    _dispose();
  }

  void _checkUsable() {
    final error = _error;
    if (error != null) throw error;
    if (_closed) throw StateError('hasher closed');
  }

  void _dispose() {
    _fromWorker.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

Future<void> _workerMain(SendPort toMain) async {
  final inbox = ReceivePort();
  toMain.send(inbox.sendPort);
  final out = _DigestSink();
  final input = sha256.startChunkedConversion(out);
  try {
    // Messages are processed strictly in order.
    await for (final msg in inbox) {
      final list = msg as List;
      switch (list[0]) {
        case 'chunk':
          input.add(
            (list[1] as TransferableTypedData).materialize().asUint8List(),
          );
          toMain.send('ack');
        case 'file':
          await for (final chunk in readFileChunks(
            list[1] as String,
            end: list[2] as int,
          )) {
            input.add(chunk);
          }
          toMain.send('ack');
        case 'close':
          input.close();
          toMain.send(['digest', out.value.toString()]);
          inbox.close();
      }
    }
  } catch (e) {
    toMain.send(['error', e.toString()]);
    inbox.close();
  }
}
