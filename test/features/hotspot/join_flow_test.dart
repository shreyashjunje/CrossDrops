import 'dart:async';

import 'package:crossdrop/core/protocol/connect_payload.dart';
import 'package:crossdrop/features/hotspot/join_flow.dart';
import 'package:crossdrop/platform/hotspot.dart';
import 'package:flutter_test/flutter_test.dart';

const _fp = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _wifi = WifiCredentials(ssid: 'AndroidShare_1', password: 'secret123');
const _payload = ConnectPayload(
  ip: '192.168.49.1',
  port: 40000,
  fingerprint: _fp,
  deviceId: '3f2a9c1b-0d4e-4f5a-8b6c-7d8e9f0a1b2c',
  name: 'Pixel',
  wifi: _wifi,
);

class FakeJoiner implements HotspotJoiner {
  FakeJoiner({this.capable = true, List<JoinOutcome>? outcomes})
    : outcomes = outcomes ?? [JoinOutcome.requested];
  final bool capable;
  final List<JoinOutcome> outcomes;
  final joined = <WifiCredentials>[];
  final forgotten = <String>[];

  @override
  Future<JoinCapability> capability() async =>
      capable ? JoinCapability.inApp : JoinCapability.manualOnly;

  @override
  Future<JoinOutcome> join(WifiCredentials wifi) async {
    joined.add(wifi);
    return outcomes.length > 1 ? outcomes.removeAt(0) : outcomes.single;
  }

  @override
  Future<void> forget(String ssid) async => forgotten.add(ssid);
}

/// Answers after [answerAfter] checks; never if null.
class FakeNetwork {
  FakeNetwork({this.answerAfter});
  int? answerAfter;
  int checks = 0;

  Future<bool> reachable(String host, int port, Duration t) async {
    expect(host, '192.168.49.1');
    expect(port, 40000);
    checks++;
    final n = answerAfter;
    return n != null && checks > n;
  }
}

HotspotJoinFlow flowWith(FakeJoiner joiner, FakeNetwork net) => HotspotJoinFlow(
  payload: _payload,
  joiner: joiner,
  reachable: net.reachable,
  waitTimeout: const Duration(milliseconds: 50),
  poll: const Duration(milliseconds: 1),
  manualPoll: const Duration(milliseconds: 1),
);

Future<void> settle(HotspotJoinFlow flow, JoinStep step) async {
  final done = Completer<void>();
  void check() {
    if (flow.status.value.step == step && !done.isCompleted) done.complete();
  }

  flow.status.addListener(check);
  check();
  await done.future.timeout(const Duration(seconds: 5));
  flow.status.removeListener(check);
}

void main() {
  test('already on the network: no join prompt', () async {
    final joiner = FakeJoiner();
    final flow = flowWith(joiner, FakeNetwork(answerAfter: 0));
    await flow.run();
    expect(flow.status.value.step, JoinStep.connected);
    expect(joiner.joined, isEmpty);
    expect(flow.addedNetwork, isFalse);
    flow.dispose();
  });

  test('joins in-app, then waits for the receiver', () async {
    final joiner = FakeJoiner();
    final net = FakeNetwork(answerAfter: 3);
    final flow = flowWith(joiner, net);
    await flow.run();
    expect(flow.status.value.step, JoinStep.connected);
    expect(joiner.joined, [_wifi]);
    expect(flow.addedNetwork, isTrue);
    expect(net.checks, 4);
    flow.dispose();
  });

  test('alreadyAssociated waits, but did not add the network', () async {
    final joiner = FakeJoiner(outcomes: [JoinOutcome.alreadyJoined]);
    final flow = flowWith(joiner, FakeNetwork(answerAfter: 1));
    await flow.run();
    expect(flow.status.value.step, JoinStep.connected);
    expect(flow.addedNetwork, isFalse);
    flow.dispose();
  });

  test('joined but the receiver never answers: timeout', () async {
    final flow = flowWith(FakeJoiner(), FakeNetwork());
    await flow.run();
    expect(flow.status.value.step, JoinStep.failed);
    expect(flow.status.value.error, 'timeout');
    flow.dispose();
  });

  test('Cancel on the prompt, then Try again', () async {
    final joiner = FakeJoiner(
      outcomes: [JoinOutcome.userDenied, JoinOutcome.requested],
    );
    final net = FakeNetwork();
    final flow = flowWith(joiner, net);
    await flow.run();
    expect(flow.status.value.step, JoinStep.denied);
    net.answerAfter = net.checks;
    await flow.retry();
    expect(flow.status.value.step, JoinStep.connected);
    expect(joiner.joined, hasLength(2));
    flow.dispose();
  });

  test('without the entitlement: manual, until the receiver answers', () async {
    final joiner = FakeJoiner(capable: false);
    final net = FakeNetwork(answerAfter: 5);
    final flow = flowWith(joiner, net);
    await flow.run();
    expect(flow.status.value.step, JoinStep.connected);
    expect(joiner.joined, isEmpty);
    flow.dispose();
  });

  test('iOS refuses (entitlement stripped): falls back to manual', () async {
    final joiner = FakeJoiner(outcomes: [JoinOutcome.notAvailable]);
    final net = FakeNetwork();
    final flow = flowWith(joiner, net);
    unawaited(flow.run());
    await settle(flow, JoinStep.manual);
    net.answerAfter = net.checks;
    await settle(flow, JoinStep.connected);
    flow.dispose();
  });

  test('invalid name or password', () async {
    final flow = flowWith(
      FakeJoiner(outcomes: [JoinOutcome.invalid]),
      FakeNetwork(),
    );
    await flow.run();
    expect(flow.status.value.error, 'invalid');
    flow.dispose();
  });

  test('switching to manual stops the wait loop', () async {
    final net = FakeNetwork();
    final flow = flowWith(FakeJoiner(), net);
    final first = flow.run();
    await settle(flow, JoinStep.waiting);
    unawaited(flow.useManual());
    await first;
    expect(flow.status.value.step, JoinStep.manual);
    flow.dispose();
  });

  test('dispose stops polling', () async {
    final net = FakeNetwork();
    final flow = flowWith(FakeJoiner(capable: false), net);
    final run = flow.run();
    await settle(flow, JoinStep.manual);
    flow.dispose();
    await run;
    final after = net.checks;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(net.checks, after);
  });
}
