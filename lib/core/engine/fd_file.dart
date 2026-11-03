import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Blocking POSIX I/O on a raw file descriptor, through `dart:ffi` (D-036).
///
/// Android hands us content URIs (MediaStore, Storage Access Framework,
/// share intents) as file descriptors (`ParcelFileDescriptor.detachFd`).
/// `dart:io` cannot wrap a descriptor, and reopening `/proc/self/fd/N` is
/// refused for many providers (FUSE passthrough, other apps' documents).
/// Reading and writing the descriptor itself always works.
///
/// Every call blocks. Use it directly only in background isolates (the
/// hash worker); elsewhere use [FdWorker]. Offsets are explicit
/// (`pread`/`pwrite`), so several isolates can share one descriptor.
/// Not available on Windows.
final class FdFile {
  FdFile(this.fd);

  final int fd;

  static _Libc get _c => _Libc.instance;

  /// The size in bytes, or -1 if the descriptor is not seekable (a pipe
  /// from a streaming provider).
  int length() {
    final r = _c.lseek(fd, 0, _seekEnd);
    if (r < 0) {
      if (_c.errno == _espipe) return -1;
      throw _error('lseek');
    }
    return r;
  }

  /// Reads up to [count] bytes at [offset]. Shorter only at end of file.
  Uint8List readAt(int offset, int count) {
    if (count <= 0) return Uint8List(0);
    final buf = malloc<Uint8>(count); // pread fills it: no need to zero
    try {
      return Uint8List.fromList(buf.asTypedList(readInto(buf, offset, count)));
    } finally {
      malloc.free(buf);
    }
  }

  /// Reads up to [count] bytes at [offset] into [buf]; returns how many.
  /// Shorter only at end of file.
  int readInto(Pointer<Uint8> buf, int offset, int count) {
    var got = 0;
    while (got < count) {
      final n = _c.pread(fd, buf + got, count - got, offset + got);
      if (n < 0) {
        if (_c.errno == _eintr) continue;
        throw _error('pread');
      }
      if (n == 0) break;
      got += n;
    }
    return got;
  }

  /// Writes all of [bytes] at [offset].
  void writeAt(int offset, Uint8List bytes) {
    if (bytes.isEmpty) return;
    final buf = malloc<Uint8>(bytes.length);
    try {
      buf.asTypedList(bytes.length).setAll(0, bytes);
      _writeFrom(buf, offset, bytes.length);
    } finally {
      malloc.free(buf);
    }
  }

  void _writeFrom(Pointer<Uint8> buf, int offset, int length) {
    var put = 0;
    while (put < length) {
      final n = _c.pwrite(fd, buf + put, length - put, offset + put);
      if (n < 0) {
        if (_c.errno == _eintr) continue;
        throw _error('pwrite');
      }
      put += n;
    }
  }

  /// [readAt] for [FdWorker]: reads into the worker's kept buffer and
  /// copies once, straight into memory that moves to the caller without
  /// another copy (review, speed item 5). Worker isolate only: the buffer
  /// lives as long as the isolate.
  TransferableTypedData readTransferable(int offset, int count) {
    if (count <= 0) return TransferableTypedData.fromList(const []);
    final buf = _WorkerBuffer.atLeast(count);
    final got = readInto(buf, offset, count);
    return TransferableTypedData.fromList([buf.asTypedList(got)]);
  }

  /// [writeAt] for [FdWorker], through the worker's kept buffer.
  void writeAtWithWorkerBuffer(int offset, Uint8List bytes) {
    if (bytes.isEmpty) return;
    final buf = _WorkerBuffer.atLeast(bytes.length);
    buf.asTypedList(bytes.length).setAll(0, bytes);
    _writeFrom(buf, offset, bytes.length);
  }

  void truncate(int length) {
    while (_c.ftruncate(fd, length) != 0) {
      if (_c.errno != _eintr) throw _error('ftruncate');
    }
  }

  /// Forces written bytes to disk, so a stored checkpoint is never ahead
  /// of the file (D-022).
  void sync() {
    while (_c.fsync(fd) != 0) {
      if (_c.errno != _eintr) throw _error('fsync');
    }
  }

  /// Sets access and modification time, for the creation date of a
  /// received file (best effort: some providers ignore it).
  void setModified(DateTime time) {
    final ts = calloc<_Timespec>(2);
    try {
      final us = time.microsecondsSinceEpoch;
      for (var i = 0; i < 2; i++) {
        ts[i].sec = us ~/ 1000000;
        ts[i].nsec = (us % 1000000) * 1000;
      }
      if (_c.futimens(fd, ts) != 0) throw _error('futimens');
    } finally {
      calloc.free(ts);
    }
  }

  /// Closes the descriptor. Never retried: after EINTR the descriptor is
  /// already released on Linux and Android.
  void close() {
    _c.close(fd);
  }

  /// Opens [path] and returns its descriptor. For tests on Linux and
  /// macOS; the app gets descriptors from the platform.
  static int openPath(String path, {bool write = false}) {
    final p = path.toNativeUtf8();
    try {
      final create = Platform.isMacOS ? 0x200 : 0x40;
      final flags = write ? (2 | create) : 0;
      final fd = _c.open(p, flags, 420); // 0644
      if (fd < 0) throw _error('open');
      return fd;
    } finally {
      calloc.free(p);
    }
  }

  static FileSystemException _error(String call) {
    final code = _c.errno;
    return FileSystemException(
      '$call failed',
      '',
      OSError(_messages[code] ?? 'errno $code', code),
    );
  }
}

/// Runs [FdFile] calls in one long-lived background isolate, so the main
/// isolate never blocks on disk or provider I/O (D-036). Calls run one at
/// a time, in order.
final class FdWorker {
  FdWorker._(this._toWorker);

  final SendPort _toWorker;

  static Future<FdWorker>? _instance;

  /// The process-wide worker, started on first use.
  static Future<FdWorker> get instance => _instance ??= _start();

  static Future<FdWorker> _start() async {
    final ready = ReceivePort();
    await Isolate.spawn(_main, ready.sendPort, debugName: 'fd-io');
    final port = await ready.first as SendPort;
    return FdWorker._(port);
  }

  Future<R> _run<R>(R Function() task) async {
    final reply = ReceivePort();
    _toWorker.send([reply.sendPort, task]);
    final msg = await reply.first as List<Object?>;
    reply.close();
    if (msg.length == 2) {
      Error.throwWithStackTrace(msg[0]!, msg[1]! as StackTrace);
    }
    return msg[0] as R;
  }

  Future<int> length(int fd) => _run(() => FdFile(fd).length());

  Future<Uint8List> readAt(int fd, int offset, int count) async {
    final t = await _run(() => FdFile(fd).readTransferable(offset, count));
    return t.materialize().asUint8List();
  }

  Future<void> writeAt(int fd, int offset, Uint8List bytes) {
    final t = TransferableTypedData.fromList([bytes]);
    return _run(
      () =>
          FdFile(fd)
              .writeAtWithWorkerBuffer(offset, t.materialize().asUint8List()),
    );
  }

  Future<void> truncate(int fd, int length) =>
      _run(() => FdFile(fd).truncate(length));

  Future<void> sync(int fd) => _run(() => FdFile(fd).sync());

  Future<void> setModified(int fd, DateTime time) =>
      _run(() => FdFile(fd).setModified(time));

  Future<void> close(int fd) => _run(() => FdFile(fd).close());

  static void _main(SendPort ready) {
    final inbox = ReceivePort();
    ready.send(inbox.sendPort);
    inbox.listen((msg) {
      final list = msg as List<Object?>;
      final reply = list[0]! as SendPort;
      try {
        reply.send([(list[1]! as Object? Function())()]);
      } catch (e, st) {
        reply.send([e, st]);
      }
    });
  }
}

/// One native buffer per isolate, grown when needed and never freed, for
/// the long-lived [FdWorker] isolate: mapping and unmapping 1 MB for each
/// read or write costs page faults every time.
abstract final class _WorkerBuffer {
  static Pointer<Uint8> _buf = nullptr;
  static int _size = 0;

  static Pointer<Uint8> atLeast(int size) {
    if (size > _size) {
      if (_buf != nullptr) malloc.free(_buf);
      _buf = malloc<Uint8>(size);
      _size = size;
    }
    return _buf;
  }
}

const int _seekEnd = 2;
const int _eintr = 4;
const int _espipe = 29;

const Map<int, String> _messages = {
  2: 'No such file or directory',
  4: 'Interrupted system call',
  5: 'I/O error',
  9: 'Bad file descriptor',
  13: 'Permission denied',
  27: 'File too large',
  28: 'No space left on device',
  29: 'Illegal seek',
  30: 'Read-only file system',
  122: 'Disk quota exceeded',
};

final class _Timespec extends Struct {
  @Long()
  external int sec;
  @Long()
  external int nsec;
}

/// libc entry points. 64-bit offset variants on Android and Linux, where
/// `off_t` is 32 bits on 32-bit ABIs; macOS `off_t` is always 64 bits.
final class _Libc {
  _Libc._(DynamicLibrary lib)
    : pread = lib
          .lookupFunction<
            IntPtr Function(Int32, Pointer<Uint8>, Size, Int64),
            int Function(int, Pointer<Uint8>, int, int)
          >(_large ? 'pread64' : 'pread'),
      pwrite = lib
          .lookupFunction<
            IntPtr Function(Int32, Pointer<Uint8>, Size, Int64),
            int Function(int, Pointer<Uint8>, int, int)
          >(_large ? 'pwrite64' : 'pwrite'),
      lseek = lib
          .lookupFunction<
            Int64 Function(Int32, Int64, Int32),
            int Function(int, int, int)
          >(_large ? 'lseek64' : 'lseek'),
      ftruncate = lib
          .lookupFunction<Int32 Function(Int32, Int64), int Function(int, int)>(
            _large ? 'ftruncate64' : 'ftruncate',
          ),
      fsync = lib.lookupFunction<Int32 Function(Int32), int Function(int)>(
        'fsync',
      ),
      close = lib.lookupFunction<Int32 Function(Int32), int Function(int)>(
        'close',
      ),
      futimens = lib
          .lookupFunction<
            Int32 Function(Int32, Pointer<_Timespec>),
            int Function(int, Pointer<_Timespec>)
          >('futimens'),
      open = lib
          .lookupFunction<
            Int32 Function(Pointer<Utf8>, Int32, VarArgs<(Int32,)>),
            int Function(Pointer<Utf8>, int, int)
          >('open'),
      _errno = lib
          .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
            Platform.isAndroid
                ? '__errno'
                : Platform.isMacOS || Platform.isIOS
                ? '__error'
                : '__errno_location',
          );

  static final _Libc instance = _Libc._(
    Platform.isAndroid
        ? DynamicLibrary.open('libc.so')
        : DynamicLibrary.process(),
  );

  static bool get _large => Platform.isAndroid || Platform.isLinux;

  final int Function(int, Pointer<Uint8>, int, int) pread;
  final int Function(int, Pointer<Uint8>, int, int) pwrite;
  final int Function(int, int, int) lseek;
  final int Function(int, int) ftruncate;
  final int Function(int) fsync;
  final int Function(int) close;
  final int Function(int, Pointer<_Timespec>) futimens;
  final int Function(Pointer<Utf8>, int, int) open;
  final Pointer<Int32> Function() _errno;

  int get errno => _errno().value;
}
