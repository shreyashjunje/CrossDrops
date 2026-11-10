import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'chunked_reader.dart';
import 'fd_file.dart';
import 'sha256_isolate.dart';

/// Bytes per leaf of the tree hash. Part of the protocol: both phones must
/// cut the file at the same places.
const int treeLeafBytes = 1024 * 1024;

/// A file is hashed on several cores only from this size; below it one
/// worker is as fast and costs fewer isolates.
const int treeParallelMinBytes = 32 * 1024 * 1024;

/// The tree hash of a file (D-071), as lowercase hex:
///
///     leaf(i) = SHA-256(bytes [i MB, (i + 1) MB))      the last may be short
///     root    = SHA-256(leaf(0) || leaf(1) || ...)     an empty file: no leaves
///
/// One SHA-256 over a whole file can only use one core, and in pure Dart
/// that was slower than the network. The leaves are hashed side by side in
/// [workers] isolates (hard rule 3), and the root still changes with any
/// bit of the file.
///
/// Feed it the file front to back with [add], or let the workers read it
/// with [addSourcePrefix]; then [close].
class TreeHasher implements FileHasher {
  TreeHasher._(this._workers, this._fromWorkers) {
    _fromWorkers.listen(_onMessage);
  }

  final List<_LeafWorker> _workers;
  final ReceivePort _fromWorkers;

  /// By leaf index; null while a worker still hashes that leaf.
  final List<Uint8List?> _leaves = [];
  final BytesBuilder _partial = BytesBuilder(copy: false);
  int _inFlight = 0;
  Completer<void>? _slot;
  Completer<void>? _idle;
  Object? _error;
  bool _closed = false;
  bool _aborted = false;
  bool _fromSource = false;

  /// Leaves waiting in the workers at most; [add] waits beyond that, so a
  /// slow hasher slows the stream instead of growing memory.
  int get _maxInFlight => 2 * _workers.length;

  /// How many isolates a file of [length] bytes is worth.
  static int workersFor(int length) => length >= treeParallelMinBytes ? 3 : 1;

  static Future<TreeHasher> spawn({int workers = 1}) async {
    final fromWorkers = ReceivePort();
    final started = <_LeafWorker>[];
    for (var i = 0; i < workers; i++) {
      final ready = ReceivePort();
      final exit = ReceivePort();
      final isolate = await Isolate.spawn(
        _leafWorker,
        [fromWorkers.sendPort, ready.sendPort],
        debugName: 'tree-hash',
        onExit: exit.sendPort,
      );
      final ports = await ready.first as List<Object?>;
      started.add(
        _LeafWorker(
          isolate,
          ports[0]! as SendPort,
          ports[1]! as SendPort,
          exit.first.then<void>((_) => exit.close()),
        ),
      );
    }
    return TreeHasher._(started, fromWorkers);
  }

  void _onMessage(Object? msg) {
    switch (msg) {
      case [final int index, final Uint8List digest]:
        _leaves[index] = digest;
        _inFlight--;
        final slot = _slot;
        if (slot != null && _inFlight < _maxInFlight) {
          _slot = null;
          slot.complete();
        }
        if (_inFlight == 0) {
          _idle?.complete();
          _idle = null;
        }
      case ['error', final String what]:
        _fail(StateError('tree hash worker: $what'));
    }
  }

  void _fail(Object error) {
    _error = error;
    _slot?.completeError(error);
    _slot = null;
    _idle?.completeError(error);
    _idle = null;
    _dispose();
  }

  /// Adds the next bytes of the file. Waits if the workers are behind.
  @override
  Future<void> add(Uint8List chunk) async {
    if (_aborted) return;
    _checkUsable();
    if (_fromSource) throw StateError('add after addSourcePrefix');
    var at = 0;
    while (at < chunk.length) {
      final room = treeLeafBytes - _partial.length;
      final n = chunk.length - at < room ? chunk.length - at : room;
      final piece = Uint8List.sublistView(chunk, at, at + n);
      at += n;
      if (_partial.isEmpty && n == treeLeafBytes) {
        await _send(piece);
      } else {
        _partial.add(piece);
        if (_partial.length == treeLeafBytes) await _send(_partial.takeBytes());
      }
      if (_aborted) return;
    }
  }

  Future<void> _send(Uint8List leaf) async {
    while (_inFlight >= _maxInFlight) {
      await (_slot ??= Completer<void>()).future;
      if (_aborted) return;
      _checkUsable();
    }
    final index = _leaves.length;
    _leaves.add(null);
    _inFlight++;
    _workers[index % _workers.length].work.send([
      index,
      TransferableTypedData.fromList([leaf]),
    ]);
  }

  /// Hashes bytes [0, length) of [source], read inside the workers, each
  /// taking every n-th leaf. Only on a new hasher, and only [close] may
  /// follow: after an app restart, and for a file the sender reads anyway.
  @override
  Future<void> addSourcePrefix(ByteSource source, int length) async {
    if (_aborted || length <= 0) return;
    _checkUsable();
    if (_leaves.isNotEmpty || _partial.isNotEmpty) {
      throw StateError('addSourcePrefix on a used hasher');
    }
    _fromSource = true;
    final count = (length + treeLeafBytes - 1) ~/ treeLeafBytes;
    _leaves.addAll(List.filled(count, null));
    _inFlight = count;
    for (final (i, w) in _workers.indexed) {
      w.work.send([source, length, i, _workers.length]);
    }
  }

  /// Returns the root and stops the workers.
  @override
  Future<String> close() async {
    _checkUsable();
    if (_partial.isNotEmpty) await _send(_partial.takeBytes());
    _closed = true;
    if (_inFlight > 0) await (_idle ??= Completer<void>()).future;
    final all = BytesBuilder(copy: false);
    for (final leaf in _leaves) {
      all.add(leaf!);
    }
    _dispose();
    return sha256.convert(all.takeBytes()).toString();
  }

  /// Stops the workers without a root. Later [add] calls are ignored.
  @override
  void abort() {
    if (_aborted) return;
    _aborted = true;
    _closed = true;
    _slot?.complete();
    _slot = null;
    final idle = _idle;
    _idle = null;
    if (idle != null && !idle.isCompleted) {
      idle.future.ignore();
      idle.completeError(StateError('hasher aborted'));
    }
    _dispose();
  }

  @override
  Future<void> get exited =>
      Future.wait([for (final w in _workers) w.exited]).then<void>((_) {});

  void _checkUsable() {
    final error = _error;
    if (error != null) throw error;
    if (_closed) throw StateError('hasher closed');
  }

  void _dispose() {
    _fromWorkers.close();
    for (final w in _workers) {
      w.control.send(true);
      w.work.send(null);
      // A worker leaves by itself once it sees the stop; kill a stuck one.
      w.exited.timeout(
        const Duration(seconds: 2),
        onTimeout: () => w.isolate.kill(priority: Isolate.immediate),
      );
    }
  }
}

class _LeafWorker {
  _LeafWorker(this.isolate, this.work, this.control, this.exited);

  final Isolate isolate;
  final SendPort work;

  /// Read between leaves, so a long file read stops quickly.
  final SendPort control;
  final Future<void> exited;
}

Future<void> _leafWorker(List<Object?> args) async {
  final toMain = args[0]! as SendPort;
  final inbox = ReceivePort();
  final control = ReceivePort();
  var stopped = false;
  control.listen((_) => stopped = true);
  (args[1]! as SendPort).send([inbox.sendPort, control.sendPort]);
  try {
    await for (final msg in inbox) {
      if (stopped || msg == null) break;
      switch (msg as List<Object?>) {
        case [final int index, final TransferableTypedData leaf]:
          toMain.send([index, _leaf(leaf.materialize().asUint8List())]);
        case [
          final ByteSource source,
          final int length,
          final int first,
          final int step,
        ]:
          final read = _LeafReader(source);
          try {
            for (
              var i = first;
              i * treeLeafBytes < length && !stopped;
              i += step
            ) {
              final start = i * treeLeafBytes;
              final end = start + treeLeafBytes;
              final leaf = read(start, (end < length ? end : length) - start);
              toMain.send([i, _leaf(leaf)]);
              // Lets a stop request in.
              await Future<void>.delayed(Duration.zero);
            }
          } finally {
            read.close();
          }
      }
    }
  } catch (e) {
    toMain.send(['error', e.toString()]);
  } finally {
    inbox.close();
    control.close();
  }
}

Uint8List _leaf(Uint8List bytes) =>
    Uint8List.fromList(sha256.convert(bytes).bytes);

/// Blocking reads of one leaf at a time, for the worker isolates.
class _LeafReader {
  _LeafReader(ByteSource source)
    : _file = switch (source) {
        PathSource(:final path) => File(path).openSync(),
        FdSource() => null,
      },
      _fd = switch (source) {
        PathSource() => null,
        FdSource(:final fd) => FdFile(fd),
      };

  final RandomAccessFile? _file;
  final FdFile? _fd;

  Uint8List call(int start, int count) {
    final Uint8List bytes;
    if (_file case final file?) {
      file.setPositionSync(start);
      bytes = file.readSync(count);
    } else {
      bytes = _fd!.readAt(start, count);
    }
    if (bytes.length != count) {
      throw const FileSystemException('file shorter than expected');
    }
    return bytes;
  }

  void close() => _file?.closeSync();
}
