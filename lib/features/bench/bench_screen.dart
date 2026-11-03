import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/media_providers.dart';
import '../../app/providers.dart';
import '../../app/version.dart';
import '../../core/bench/bench.dart';
import '../../core/bench/bench_runner.dart';
import '../../core/bench/bench_stats.dart';
import '../../core/bench/phone_limits.dart';
import '../../core/client/peer_check.dart';
import '../../core/engine/send_session.dart';
import '../../core/protocol/models.dart';
import '../../core/security/device_identity.dart';
import '../nearby/nearby_screen.dart';
import '../receive/receive_controller.dart';
import '../receive/receive_host.dart';
import '../transfer/widgets.dart';
import 'receiver_bench.dart';

const benchNetworks = [
  'Router 2.4 GHz',
  'Router 5 GHz',
  'Android hotspot',
  'iPhone hotspot',
  'Android tethering (Settings)',
  'Other',
];

/// Benchmark mode, only in benchmark builds (D-058). Runs a series of
/// sends through the real engine, records what this phone receives, and
/// writes both to `crossdrop-bench.csv` in the app's Documents folder.
class BenchScreen extends ConsumerStatefulWidget {
  const BenchScreen({super.key});

  @override
  ConsumerState<BenchScreen> createState() => _BenchScreenState();
}

class _BenchScreenState extends ConsumerState<BenchScreen> {
  String _network = benchNetworks[1];
  final Set<int> _sizes = {benchSizes[2]};
  final Set<int> _buffers = {...benchBuffers};
  int _repeats = 3;
  ConnectTarget? _target;
  BenchRunner? _runner;
  String? _progress;
  bool _recordReceiving = true;
  final List<BenchResult> _results = [];
  String? _csvPath;
  ReceiverBenchTracker? _tracker;

  /// "This phone's limits" (D-066): results, and the step running now.
  final List<PhoneLimit> _limits = [];
  String? _limitsStep;
  String? _limitsError;

  DevicePlatform get _me => DevicePlatform.current;

  @override
  void initState() {
    super.initState();
    unawaited(_openCsv());
  }

  @override
  void dispose() {
    unawaited(_runner?.cancel());
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  Future<void> _openCsv() async {
    final docs = await getApplicationDocumentsDirectory();
    final path = p.join(docs.path, 'crossdrop-bench.csv');
    final file = File(path);
    if (!await file.exists()) {
      await file.writeAsString('${BenchResult.csvHeader}\n');
    }
    if (mounted) setState(() => _csvPath = path);
  }

  Future<void> _record(BenchResult r) async {
    setState(() => _results.add(r));
    final path = _csvPath;
    if (path != null) {
      await File(path).writeAsString('${r.toCsv()}\n', mode: FileMode.append);
    }
  }

  /// SHA-256, pinned TLS on loopback and writes through the receive
  /// store, each 256 MB; rows go to `crossdrop-limits.csv` next to the
  /// benchmark CSV.
  Future<void> _measureLimits() async {
    setState(() {
      _limitsStep = 'starting';
      _limitsError = null;
    });
    await WakelockPlus.enable();
    try {
      final dirs = await ref.read(appDirsProvider.future);
      final results = await measurePhoneLimits(
        credentials: await ref.read(credentialsProvider.future),
        store: await ref.read(receivedFileStoreProvider.future),
        tempDir: dirs.incomingTemp,
        onStart: (t) {
          if (mounted) setState(() => _limitsStep = t);
        },
      );
      final docs = await getApplicationDocumentsDirectory();
      final csv = File(p.join(docs.path, 'crossdrop-limits.csv'));
      if (!await csv.exists()) {
        await csv.writeAsString('${PhoneLimit.csvHeader}\n');
      }
      await csv.writeAsString(
        [
          for (final r in results)
            '${r.toCsv(platform: _me.name, appVersion: appVersion)}\n',
        ].join(),
        mode: FileMode.append,
      );
      if (mounted) {
        setState(() {
          _limits
            ..clear()
            ..addAll(results);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _limitsError = '$e');
    } finally {
      await WakelockPlus.disable();
      if (mounted) setState(() => _limitsStep = null);
    }
  }

  Future<(String?, int?)> _wifi() async {
    final s = await ref.read(networkPlatformProvider).wifiState();
    return (s?.band, s?.linkMbps);
  }

  Future<void> _chooseReceiver() async {
    final target = await Navigator.of(context).push<ConnectTarget>(
      MaterialPageRoute(builder: (_) => const NearbyScreen()),
    );
    if (target != null && mounted) setState(() => _target = target);
  }

  Future<void> _start() async {
    final target = _target;
    if (target == null || _sizes.isEmpty || _buffers.isEmpty) return;
    final device = await ref.read(identityProvider.future);
    final credentials = await ref.read(credentialsProvider.future);
    final tmp = await getTemporaryDirectory();
    final (band, link) = await _wifi();
    final runner = BenchRunner(
      direction:
          '${platformShort(_me.name)} → ${platformShort(target.platform)}',
      network: _network,
      wifiBand: band,
      linkMbps: link,
      appVersion: appVersion,
      fileFor: (size) {
        if (mounted) {
          setState(() => _progress = 'Making a ${sizeLabel(size)} test file…');
        }
        return ensureBenchFile(p.join(tmp.path, 'bench'), size);
      },
      newSession:
          ({
            required String path,
            required String name,
            required int size,
            required int chunkSize,
          }) => SendSession(
            host: target.host,
            port: target.port,
            sender: SenderInfo(
              id: device.deviceId,
              name: device.deviceName,
              platform: _me.name,
            ),
            items: [SendItem(path: path, name: name, size: size)],
            receiverFingerprint: target.fingerprint!,
            credentials: credentials,
            expectedDeviceId: target.deviceId,
            chunkSize: chunkSize,
          ),
    );
    final cases = planCases(
      sizes: benchSizes.where(_sizes.contains).toList(),
      buffers: benchBuffers.where(_buffers.contains).toList(),
      repeats: _repeats,
    );
    setState(() => _runner = runner);
    await WakelockPlus.enable();
    var i = 0;
    try {
      setState(() => _progress = 'Run 1 of ${cases.length}: ${cases.first}');
      await for (final r in runner.run(cases)) {
        i++;
        await _record(r);
        if (!mounted) return;
        setState(
          () => _progress = i < cases.length
              ? 'Run ${i + 1} of ${cases.length}: ${cases[i]}'
              : null,
        );
      }
    } finally {
      await WakelockPlus.disable();
      if (mounted) {
        setState(() {
          _runner = null;
          _progress = null;
        });
      }
    }
  }

  Future<void> _copyCsv() async {
    final path = _csvPath;
    if (path == null) return;
    await Clipboard.setData(
      ClipboardData(text: await File(path).readAsString()),
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('CSV copied')));
    }
  }

  Future<void> _newCsv() async {
    final path = _csvPath;
    if (path == null) return;
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '');
    await File(path)
        .rename(p.join(p.dirname(path), 'crossdrop-bench-$stamp.csv'));
    setState(_results.clear);
    await _openCsv();
  }

  void _onReceive(Iterable<IncomingSession> sessions) {
    if (!_recordReceiving) return;
    final tracker = _tracker ??= ReceiverBenchTracker(
      me: _me.name,
      network: _network,
      appVersion: appVersion,
    );
    tracker.network = _network;
    for (final r in tracker.update(sessions)) {
      unawaited(_record(r));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      receiveStateProvider.select((s) => s.sessions),
      (_, sessions) => _onReceive(sessions.values),
    );
    final theme = Theme.of(context);
    final running = _runner != null;
    final best = bestBuffer(_results);
    final medians = medianByCase(_results);
    return Scaffold(
      appBar: AppBar(title: const Text('Benchmark')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const WarningBox(
            icon: Icons.info_outline,
            text:
                'Benchmark build. On the receiving phone: open this screen '
                'too, trust this phone and turn on auto-accept for it. Keep '
                'both screens on and the phones where they are.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _network,
            decoration: const InputDecoration(labelText: 'Network'),
            items: [
              for (final n in benchNetworks)
                DropdownMenuItem(value: n, child: Text(n)),
            ],
            onChanged: running ? null : (v) => setState(() => _network = v!),
          ),
          const SizedBox(height: 16),
          Text('Send from this phone', style: theme.textTheme.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_target?.name ?? 'No receiver chosen'),
            subtitle: _target == null
                ? null
                : Text(platformShort(_target!.platform)),
            trailing: TextButton(
              onPressed: running ? null : _chooseReceiver,
              child: const Text('Choose'),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final s in benchSizes)
                FilterChip(
                  label: Text(sizeLabel(s)),
                  selected: _sizes.contains(s),
                  onSelected: running
                      ? null
                      : (on) => setState(
                          () => on ? _sizes.add(s) : _sizes.remove(s),
                        ),
                ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final b in benchBuffers)
                FilterChip(
                  label: Text('Buffer ${sizeLabel(b)}'),
                  selected: _buffers.contains(b),
                  onSelected: running
                      ? null
                      : (on) => setState(
                          () => on ? _buffers.add(b) : _buffers.remove(b),
                        ),
                ),
            ],
          ),
          Row(
            children: [
              const Text('Runs each'),
              const SizedBox(width: 16),
              DropdownButton<int>(
                value: _repeats,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1')),
                  DropdownMenuItem(value: 3, child: Text('3')),
                  DropdownMenuItem(value: 5, child: Text('5')),
                ],
                onChanged: running
                    ? null
                    : (v) => setState(() => _repeats = v!),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (running) ...[
            Text(_progress ?? '', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _runner?.cancel(),
              child: const Text('Stop the series'),
            ),
          ] else
            FilledButton(
              onPressed: _target == null || _sizes.isEmpty || _buffers.isEmpty
                  ? null
                  : _start,
              child: const Text('Start series'),
            ),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Record runs this phone receives'),
            subtitle: const Text('CPU and memory of the receiving side'),
            value: _recordReceiving,
            onChanged: (v) => setState(() => _recordReceiving = v),
          ),
          const Divider(height: 32),
          Text("This phone's limits", style: theme.textTheme.titleMedium),
          const Text(
            'SHA-256, pinned TLS on this phone alone, and writing as '
            'received files are written, with a checkpoint every 4 MB '
            'and every 64 MB. A step close to the transfer speed is the '
            'limit. About a minute; keep the screen on.',
          ),
          if (_limitsStep != null) ...[
            const SizedBox(height: 8),
            Text('Measuring: $_limitsStep'),
            const LinearProgressIndicator(),
          ] else
            OutlinedButton(
              onPressed: running ? null : _measureLimits,
              child: const Text('Measure this phone'),
            ),
          if (_limitsError != null) Text('Failed: $_limitsError'),
          for (final r in _limits)
            Text('${r.test}: ${r.mbPerSecond.toStringAsFixed(0)} MB/s'),
          const Divider(height: 32),
          Text('Results', style: theme.textTheme.titleMedium),
          if (best != null)
            Text(
              'Best buffer so far: ${sizeLabel(best)} (median of sender '
              'runs of 100 MB and up, within 5 %; ties go to 1 MB).',
            ),
          for (final e in medians.entries)
            Text(
              '${sizeLabel(e.key.$1)}, buffer ${sizeLabel(e.key.$2)}: '
              'median ${e.value.toStringAsFixed(1)} MB/s',
            ),
          const SizedBox(height: 8),
          for (final r in _results.reversed.take(40))
            Text(
              '${r.role.name} ${sizeLabel(r.fileBytes)} '
              '${r.role == BenchRole.sender ? 'buf ${sizeLabel(r.bufferBytes)} #${r.run} ' : ''}'
              '${r.ok ? '${r.avgMBps?.toStringAsFixed(1)} MB/s'
                        '${r.peakMBps == null ? '' : ' (peak ${r.peakMBps!.toStringAsFixed(1)})'}'
                        '${r.cpuPercent == null ? '' : ', CPU ${r.cpuPercent!.toStringAsFixed(0)} %'}' : 'failed: ${r.reason}'}',
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 16),
          if (_csvPath != null)
            SelectableText(
              Platform.isIOS
                  ? 'CSV: Files > On My iPhone > CrossDrop > '
                        '${p.basename(_csvPath!)}'
                  : 'CSV: $_csvPath\n(adb pull it, or use Copy CSV)',
              style: theme.textTheme.bodySmall,
            ),
          Row(
            children: [
              TextButton(onPressed: _copyCsv, child: const Text('Copy CSV')),
              TextButton(
                onPressed: running ? null : _newCsv,
                child: const Text('Start a new CSV'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
