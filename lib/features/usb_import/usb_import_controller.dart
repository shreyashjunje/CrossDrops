import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../core/log.dart';
import '../../core/usb_import/camera_roll.dart';
import '../../core/usb_import/import_runner.dart';
import '../../core/media/thumbnail_queue.dart';
import '../../platform/usb_camera.dart';

/// The cable connection to an iPhone (Android, D-067).
final usbCameraProvider = Provider<UsbCamera>(
  (ref) => Platform.isAndroid ? ChannelUsbCamera() : const NoUsbCamera(),
);

/// Whether this phone offers cable import: Android only.
final usbImportAvailableProvider = Provider<bool>((ref) => Platform.isAndroid);

/// Keeps the screen on while copying; replaced in tests.
final usbKeepScreenOnProvider = Provider<Future<void> Function(bool on)>(
  (ref) => (on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } on Object catch (e) {
      logEvent('usb', 'wakelock failed (${e.runtimeType})');
    }
  },
);

/// Free bytes where imported files go (the shared storage volume).
final usbFreeBytesProvider = Provider<Future<int?> Function()>((ref) {
  final space = ref.watch(freeSpaceProvider);
  return () async {
    final dir =
        await getExternalStorageDirectory() ??
        await getApplicationSupportDirectory();
    return space.freeBytes(dir.path);
  };
});

/// The iPhones plugged in now, for the home screen card.
final usbDevicesProvider = StreamProvider<List<UsbCameraDevice>>((ref) {
  final camera = ref.watch(usbCameraProvider);
  final devices = <String, UsbCameraDevice>{};
  final out = StreamController<List<UsbCameraDevice>>();
  void push() => out.add(List.unmodifiable(devices.values));
  final sub = camera.events.listen((e) {
    switch (e) {
      case UsbCameraAttached(:final device):
        devices[device.id] = device;
        push();
      case UsbCameraDetached(:final id):
        if (devices.remove(id) != null) push();
      case UsbCopyProgress():
        break;
    }
  });
  unawaited(
    camera.devices().then(
      (list) {
        for (final d in list) {
          devices[d.id] = d;
        }
        push();
      },
      onError: (Object e) {
        logEvent('usb', 'devices failed (${e.runtimeType})');
        push();
      },
    ),
  );
  ref.onDispose(() async {
    await sub.cancel();
    await out.close();
  });
  return out.stream;
});

enum UsbImportPhase {
  /// No iPhone plugged in.
  noDevice,
  connecting,
  permissionDenied,

  /// Another app holds the iPhone (often Files).
  busy,

  /// Locked, or "Allow" not tapped yet; retried every few seconds.
  locked,

  /// Reading the file list; the grid fills as pages arrive.
  loading,
  ready,
  importing,
  done,

  /// The device stopped answering while reading the list.
  failed,
}

class UsbImportState {
  const UsbImportState({
    this.phase = UsbImportPhase.noDevice,
    this.device,
    this.roll = CameraRoll.empty,
    this.seen = 0,
    this.selected = const {},
    this.filter = RollFilter.all,
    this.includeLiveVideo = false,
    this.includeOriginals = false,
    this.imported = const {},
    this.progress,
    this.summary,
    this.space,
  });

  final UsbImportPhase phase;
  final UsbCameraDevice? device;
  final CameraRoll roll;

  /// Files read from the device so far.
  final int seen;

  /// [RollItem.key]s.
  final Set<String> selected;
  final RollFilter filter;
  final bool includeLiveVideo;
  final bool includeOriginals;

  /// Items copied while this screen was open.
  final Set<String> imported;
  final ImportProgress? progress;
  final ImportSummary? summary;

  /// Set when the last start was refused for lack of space.
  final NotEnoughSpace? space;

  bool get showsGrid =>
      phase == UsbImportPhase.loading || phase == UsbImportPhase.ready;

  List<RollItem> get visible => [
    for (final i in roll.items)
      if (matchesFilter(i, filter)) i,
  ];

  List<RollItem> get selectedItems => [
    for (final i in roll.items)
      if (selected.contains(i.key)) i,
  ];

  List<ImportFile> get plan => planImport(
    selectedItems,
    includeLiveVideo: includeLiveVideo,
    includeOriginal: includeOriginals,
  );

  UsbImportState copyWith({
    UsbImportPhase? phase,
    UsbCameraDevice? device,
    CameraRoll? roll,
    int? seen,
    Set<String>? selected,
    RollFilter? filter,
    bool? includeLiveVideo,
    bool? includeOriginals,
    Set<String>? imported,
    ImportProgress? progress,
    ImportSummary? summary,
    NotEnoughSpace? space,
    bool clearSpace = false,
  }) => UsbImportState(
    phase: phase ?? this.phase,
    device: device ?? this.device,
    roll: roll ?? this.roll,
    seen: seen ?? this.seen,
    selected: selected ?? this.selected,
    filter: filter ?? this.filter,
    includeLiveVideo: includeLiveVideo ?? this.includeLiveVideo,
    includeOriginals: includeOriginals ?? this.includeOriginals,
    imported: imported ?? this.imported,
    progress: progress ?? this.progress,
    summary: summary ?? this.summary,
    space: clearSpace ? null : (space ?? this.space),
  );
}

/// Owns the cable connection while the import screen is open (D-067):
/// connects to the first iPhone, reads its file list page by page, keeps
/// the selection, and copies with [ImportRunner]. Leaving the screen
/// closes the device.
class UsbImportController extends Notifier<UsbImportState> {
  static const lockedRetry = Duration(seconds: 2);

  late UsbCamera _camera;
  StreamSubscription<UsbCameraEvent>? _events;
  Timer? _retry;
  ImportRunner? _runner;
  ThumbnailQueue<int, String>? _thumbs;

  /// Bumped on each connect; a stale listing stops.
  int _generation = 0;
  final List<CameraObject> _objects = [];

  ThumbnailQueue<int, String>? get thumbnails => _thumbs;

  @override
  UsbImportState build() {
    _camera = ref.watch(usbCameraProvider);
    final keepOn = ref.watch(usbKeepScreenOnProvider);
    _events = _camera.events.listen(_onEvent);
    // No state or ref here: Riverpod forbids them in onDispose.
    ref.onDispose(() {
      _generation++;
      _retry?.cancel();
      unawaited(_events?.cancel());
      _thumbs?.close();
      final runner = _runner;
      _runner = null;
      if (runner != null) {
        runner.cancel();
        unawaited(_camera.cancelCurrent());
        unawaited(keepOn(false));
      }
      unawaited(_camera.close());
    });
    unawaited(_findDevice());
    return const UsbImportState(phase: UsbImportPhase.connecting);
  }

  Future<void> _findDevice() async {
    List<UsbCameraDevice> list;
    try {
      list = await _camera.devices();
    } on PlatformException {
      list = const [];
    }
    if (!ref.mounted) return;
    if (list.isEmpty) {
      if (state.phase == UsbImportPhase.connecting) {
        state = const UsbImportState();
      }
      return;
    }
    await connect(list.first);
  }

  void _onEvent(UsbCameraEvent e) {
    switch (e) {
      case UsbCameraAttached(:final device):
        if (state.device == null ||
            state.phase == UsbImportPhase.noDevice ||
            state.phase == UsbImportPhase.done &&
                state.device?.id != device.id) {
          unawaited(connect(device));
        }
      case UsbCameraDetached(:final id):
        if (state.device?.id != id) return;
        _generation++;
        _retry?.cancel();
        _thumbs?.close();
        _thumbs = null;
        // A running import ends by itself with "disconnected".
        if (state.phase != UsbImportPhase.importing &&
            state.phase != UsbImportPhase.done) {
          state = UsbImportState(imported: state.imported);
        }
      case UsbCopyProgress(:final handle, :final bytes):
        _runner?.reportBytes(handle, bytes);
    }
  }

  /// Opens [device] and reads its list. Also "Try again".
  Future<void> connect([UsbCameraDevice? device]) async {
    final d = device ?? state.device;
    if (d == null) return _findDevice();
    final gen = ++_generation;
    _retry?.cancel();
    _thumbs?.close();
    _thumbs = null;
    _objects.clear();
    state = UsbImportState(
      phase: UsbImportPhase.connecting,
      device: d,
      includeLiveVideo: state.includeLiveVideo,
      includeOriginals: state.includeOriginals,
      imported: state.device?.id == d.id ? state.imported : const {},
    );
    try {
      await _camera.open(d.id);
    } on PlatformException catch (e) {
      if (gen != _generation) return;
      logEvent('usb', 'open failed: ${e.code}');
      final phase = switch (e.code) {
        UsbCameraErrors.permissionDenied => UsbImportPhase.permissionDenied,
        UsbCameraErrors.busy => UsbImportPhase.busy,
        UsbCameraErrors.locked => UsbImportPhase.locked,
        UsbCameraErrors.disconnected => UsbImportPhase.noDevice,
        _ => UsbImportPhase.failed,
      };
      state = phase == UsbImportPhase.noDevice
          ? const UsbImportState()
          : state.copyWith(phase: phase);
      if (phase == UsbImportPhase.locked) {
        _retry = Timer(lockedRetry, () {
          if (gen == _generation) unawaited(connect(d));
        });
      }
      return;
    }
    if (gen != _generation) return;
    _thumbs = ThumbnailQueue(_camera.thumbnail);
    state = state.copyWith(phase: UsbImportPhase.loading);
    await _list(gen);
  }

  Future<void> _list(int gen) async {
    while (true) {
      final CameraPage page;
      try {
        page = await _camera.nextPage();
      } on PlatformException catch (e) {
        if (gen != _generation) return;
        logEvent('usb', 'list failed: ${e.code}');
        state = e.code == UsbCameraErrors.disconnected
            ? UsbImportState(imported: state.imported)
            : state.copyWith(phase: UsbImportPhase.failed);
        return;
      }
      if (gen != _generation) return;
      _objects.addAll(page.objects);
      final roll = buildCameraRoll(_objects);
      final keys = {for (final i in roll.items) i.key};
      state = state.copyWith(
        roll: roll,
        seen: page.seen,
        // A Live video paired late changes its still's key: drop gone keys.
        selected: state.selected.where(keys.contains).toSet(),
        phase: page.done ? UsbImportPhase.ready : UsbImportPhase.loading,
      );
      if (page.done) return;
    }
  }

  void toggle(String key) {
    final s = {...state.selected};
    if (!s.remove(key)) s.add(key);
    state = state.copyWith(selected: s, clearSpace: true);
  }

  /// Selects [items] if any of them is not selected, else clears them.
  void toggleAll(Iterable<RollItem> items) {
    final keys = items.map((i) => i.key).toSet();
    final s = {...state.selected};
    if (keys.every(s.contains)) {
      s.removeAll(keys);
    } else {
      s.addAll(keys);
    }
    state = state.copyWith(selected: s, clearSpace: true);
  }

  void clearSelection() =>
      state = state.copyWith(selected: const {}, clearSpace: true);

  /// Selects what is shown that was not copied yet.
  void selectNotImported() => state = state.copyWith(
    selected: {
      ...state.selected,
      for (final i in state.visible)
        if (!state.imported.contains(i.key)) i.key,
    },
    clearSpace: true,
  );

  void setFilter(RollFilter f) => state = state.copyWith(filter: f);

  void setIncludeLiveVideo(bool v) =>
      state = state.copyWith(includeLiveVideo: v, clearSpace: true);

  void setIncludeOriginals(bool v) =>
      state = state.copyWith(includeOriginals: v, clearSpace: true);

  /// Copies the selection. Refused with [UsbImportState.space] set when
  /// the phone has too little space (hard rule 6).
  Future<void> startImport() async {
    if (state.phase != UsbImportPhase.ready &&
        state.phase != UsbImportPhase.loading) {
      return;
    }
    final files = state.plan;
    if (files.isEmpty) return;
    final previous = state.phase;
    final runner = ImportRunner(
      copy: _copy,
      freeBytes: ref.read(usbFreeBytesProvider),
    );
    _runner = runner;
    final keepOn = ref.read(usbKeepScreenOnProvider);
    state = state.copyWith(
      phase: UsbImportPhase.importing,
      progress: runner.progress,
      clearSpace: true,
    );
    await keepOn(true);
    try {
      final summary = await runner.run(
        files,
        onProgress: (p) {
          if (_runner == runner) state = state.copyWith(progress: p);
        },
      );
      if (_runner != runner) return;
      state = state.copyWith(
        phase: UsbImportPhase.done,
        summary: summary,
        imported: {...state.imported, ...summary.copiedItems},
        selected: state.selected.difference(summary.copiedItems),
      );
    } on NotEnoughSpace catch (e) {
      if (_runner == runner) state = state.copyWith(phase: previous, space: e);
    } finally {
      if (_runner == runner) _runner = null;
      await keepOn(false);
    }
  }

  Future<int> _copy(ImportFile f) async {
    try {
      final r = await _camera.importFile(
        handle: f.object.handle,
        safeName: f.safeName,
        mime: f.mime,
        collection: f.collection,
        expectedSize: f.object.size,
        taken: f.object.taken,
      );
      return r.bytes;
    } on PlatformException catch (e) {
      throw CopyFailure(e.code);
    }
  }

  /// Stops the copy, including the file in progress.
  void cancelImport() {
    final r = _runner;
    if (r == null) return;
    r.cancel();
    unawaited(_camera.cancelCurrent());
  }

  /// From the summary back to the grid, if the iPhone is still there.
  Future<void> backToPhotos() async {
    if (state.phase != UsbImportPhase.done) return;
    if (state.summary?.stop == ImportStop.disconnected ||
        state.device == null) {
      state = UsbImportState(imported: state.imported);
      return _findDevice();
    }
    state = state.copyWith(phase: UsbImportPhase.ready);
  }
}

final usbImportControllerProvider =
    NotifierProvider.autoDispose<UsbImportController, UsbImportState>(
      UsbImportController.new,
    );
