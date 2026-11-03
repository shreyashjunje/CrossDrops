import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/log.dart';
import '../../core/protocol/connect_payload.dart';
import '../../platform/hotspot.dart';

enum JoinStep {
  /// Checking whether the other phone already answers.
  checking,

  /// The system "Join network?" prompt is up.
  joining,

  /// Joined or asked to join; waiting until the other phone answers.
  waiting,

  /// The user joins in Settings > Wi-Fi; checking every few seconds.
  manual,

  /// The other phone answers; go on and connect.
  connected,

  /// The user tapped Cancel on the system prompt.
  denied,

  /// See [JoinStatus.error].
  failed,
}

class JoinStatus {
  const JoinStatus(this.step, {this.error});
  final JoinStep step;

  /// `timeout` (joined, but the other phone did not answer) or `invalid`
  /// (iOS refused the name or password) or `failed`.
  final String? error;

  @override
  String toString() =>
      'JoinStatus(${step.name}${error == null ? '' : ', $error'})';
}

/// Opens a TCP connection to [host]:[port] and closes it. True if the
/// receiver answers within [timeout]. The pinned TLS check comes after,
/// when connecting for real.
Future<bool> tcpReachable(String host, int port, Duration timeout) async {
  try {
    final s = await Socket.connect(host, port, timeout: timeout);
    s.destroy();
    return true;
  } on SocketException {
    return false;
  } on OSError {
    return false;
  }
}

typedef Reachable = Future<bool> Function(String host, int port, Duration t);

/// iPhone: join the Android phone's hotspot from its QR code, then wait
/// until the receiver answers (D-055).
///
/// 1. If the receiver already answers, the phone is on that network.
/// 2. With the Hotspot Configuration entitlement, iOS asks the user to
///    join. Without it (free Apple ID builds), or if iOS refuses for an
///    internal reason, the user joins in Settings and the flow checks
///    every [manualPoll] until the receiver answers.
/// 3. "Joined" from iOS is not proof: the flow waits up to [waitTimeout]
///    for the receiver.
class HotspotJoinFlow {
  HotspotJoinFlow({
    required this.payload,
    required this.joiner,
    this.reachable = tcpReachable,
    this.probeTimeout = const Duration(milliseconds: 1500),
    this.waitTimeout = const Duration(seconds: 30),
    this.poll = const Duration(seconds: 1),
    this.manualPoll = const Duration(seconds: 2),
  }) : assert(payload.wifi != null);

  final ConnectPayload payload;
  final HotspotJoiner joiner;
  final Reachable reachable;
  final Duration probeTimeout;
  final Duration waitTimeout;
  final Duration poll;
  final Duration manualPoll;

  final ValueNotifier<JoinStatus> status = ValueNotifier(
    const JoinStatus(JoinStep.checking),
  );

  /// True if this flow made iOS add the network, so it may remove it.
  bool get addedNetwork => _added;
  bool _added = false;

  /// Bumped on every new attempt; older loops stop.
  int _generation = 0;
  bool _disposed = false;

  WifiCredentials get wifi => payload.wifi!;

  Future<bool> _answers() => reachable(payload.ip, payload.port, probeTimeout);

  void _set(int gen, JoinStatus s) {
    if (_disposed || gen != _generation) return;
    if (s.step != status.value.step) {
      logEvent('hotspot', 'join step: ${s.step.name}');
    }
    status.value = s;
  }

  bool _current(int gen) => !_disposed && gen == _generation;

  /// Starts from the beginning.
  Future<void> run() async {
    final gen = ++_generation;
    _set(gen, const JoinStatus(JoinStep.checking));
    if (await _answers()) {
      _set(gen, const JoinStatus(JoinStep.connected));
      return;
    }
    if (!_current(gen)) return;
    if (await joiner.capability() == JoinCapability.manualOnly) {
      if (_current(gen)) await _manual(gen);
      return;
    }
    await _join(gen);
  }

  /// Asks iOS to join again (after Cancel or a failure).
  Future<void> retry() async {
    final gen = ++_generation;
    await _join(gen);
  }

  /// Joins in Settings instead.
  Future<void> useManual() async {
    final gen = ++_generation;
    await _manual(gen);
  }

  Future<void> _join(int gen) async {
    _set(gen, const JoinStatus(JoinStep.joining));
    final outcome = await joiner.join(wifi);
    if (!_current(gen)) return;
    switch (outcome) {
      case JoinOutcome.requested:
        _added = true;
        await _wait(gen);
      case JoinOutcome.alreadyJoined:
        await _wait(gen);
      case JoinOutcome.userDenied:
        _set(gen, const JoinStatus(JoinStep.denied));
      case JoinOutcome.notAvailable:
        await _manual(gen);
      case JoinOutcome.invalid:
        _set(gen, const JoinStatus(JoinStep.failed, error: 'invalid'));
      case JoinOutcome.failed:
        _set(gen, const JoinStatus(JoinStep.failed, error: 'failed'));
    }
  }

  Future<void> _wait(int gen) async {
    _set(gen, const JoinStatus(JoinStep.waiting));
    final deadline = DateTime.now().add(waitTimeout);
    while (_current(gen)) {
      if (await _answers()) {
        _set(gen, const JoinStatus(JoinStep.connected));
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        _set(gen, const JoinStatus(JoinStep.failed, error: 'timeout'));
        return;
      }
      await Future<void>.delayed(poll);
    }
  }

  Future<void> _manual(int gen) async {
    _set(gen, const JoinStatus(JoinStep.manual));
    while (_current(gen)) {
      if (await _answers()) {
        _set(gen, const JoinStatus(JoinStep.connected));
        return;
      }
      await Future<void>.delayed(manualPoll);
    }
  }

  /// Stops any running check.
  void dispose() {
    _disposed = true;
    _generation++;
    status.dispose();
  }
}
