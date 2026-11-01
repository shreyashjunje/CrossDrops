import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/client/upload_client.dart';

enum SendPhase { idle, sending, done, failed, cancelled }

class SendState {
  const SendState({
    this.path,
    this.name,
    this.size,
    this.phase = SendPhase.idle,
    this.progress,
    this.error,
    this.target,
    this.elapsed,
    this.sentThisRun,
  });

  final String? path;
  final String? name;
  final int? size;
  final SendPhase phase;
  final TransferProgress? progress;
  final String? error;

  /// Set once the receiver accepted the offer; needed to resume.
  final UploadTarget? target;

  /// Duration and bytes of the last run, for the average speed.
  final Duration? elapsed;
  final int? sentThisRun;

  bool get canResume =>
      target != null &&
      (phase == SendPhase.failed || phase == SendPhase.cancelled);

  /// Average MB/s (10^6 bytes) of the last finished run.
  double? get averageMegabytesPerSecond {
    final e = elapsed;
    final sent = sentThisRun;
    if (e == null || sent == null || e.inMicroseconds == 0) return null;
    return sent / e.inMicroseconds;
  }
}

final sendControllerProvider =
    NotifierProvider.autoDispose<SendController, SendState>(SendController.new);

class SendController extends Notifier<SendState> {
  UploadClient? _client;
  String? _host;
  int? _port;

  @override
  SendState build() {
    ref.onDispose(() {
      _client?.cancel();
      _client?.close();
      WakelockPlus.disable();
    });
    return const SendState();
  }

  Future<void> pickFile() async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty || !ref.mounted) return;
    final file = picked.first;
    final path = file.path;
    if (path == null) {
      state = const SendState(error: 'This file cannot be read directly.');
      return;
    }
    final size = await File(path).length();
    if (!ref.mounted) return;
    state = SendState(path: path, name: file.name, size: size);
  }

  /// Offers the picked file to [host]:[port] and sends it from the start.
  Future<void> send(String host, int port) async {
    final path = state.path;
    if (path == null || state.phase == SendPhase.sending) return;
    _client?.close();
    final client = _client = UploadClient(host: host, port: port);
    _host = host;
    _port = port;
    _setPhase(SendPhase.sending);
    try {
      final target = await client.offerFile(path, name: state.name);
      state = _copy(target: target);
      await _run(client, target);
    } on UploadException catch (e) {
      _fail(e);
    } on Exception catch (e) {
      _fail(UploadException('error', '$e'));
    }
  }

  /// Continues an interrupted transfer from the receiver's receivedBytes.
  Future<void> resume() async {
    final target = state.target;
    if (target == null || !state.canResume) return;
    _client?.close();
    final client = _client = UploadClient(host: _host!, port: _port!);
    _setPhase(SendPhase.sending);
    try {
      await _run(client, target);
    } on UploadException catch (e) {
      _fail(e);
    } on Exception catch (e) {
      _fail(UploadException('error', '$e'));
    }
  }

  void cancel() => _client?.cancel();

  Future<void> _run(UploadClient client, UploadTarget target) async {
    await WakelockPlus.enable();
    try {
      final start = (await client.fileStatus(target)).receivedBytes;
      final watch = Stopwatch()..start();
      var lastUi = Duration.zero;
      await client.transfer(
        target,
        onProgress: (pr) {
          // Limit rebuilds to about 10 per second.
          final now = watch.elapsed;
          if (pr.sentBytes != pr.totalBytes &&
              now - lastUi < const Duration(milliseconds: 100)) {
            return;
          }
          lastUi = now;
          if (ref.mounted) state = _copy(progress: pr);
        },
      );
      watch.stop();
      if (!ref.mounted) return;
      state = _copy(
        phase: SendPhase.done,
        elapsed: watch.elapsed,
        sentThisRun: target.size - start,
      );
    } finally {
      await WakelockPlus.disable();
    }
  }

  void _setPhase(SendPhase phase) =>
      state = _copy(phase: phase, clearError: true);

  void _fail(UploadException e) {
    if (!ref.mounted) return;
    state = _copy(
      phase: e.isCancelled ? SendPhase.cancelled : SendPhase.failed,
      error: e.isCancelled ? null : '${e.code}: ${e.message}',
    );
  }

  SendState _copy({
    SendPhase? phase,
    TransferProgress? progress,
    String? error,
    bool clearError = false,
    UploadTarget? target,
    Duration? elapsed,
    int? sentThisRun,
  }) {
    final s = state;
    return SendState(
      path: s.path,
      name: s.name,
      size: s.size,
      phase: phase ?? s.phase,
      progress: progress ?? s.progress,
      error: clearError ? null : (error ?? s.error),
      target: target ?? s.target,
      elapsed: elapsed ?? s.elapsed,
      sentThisRun: sentThisRun ?? s.sentThisRun,
    );
  }
}
