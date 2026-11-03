import 'dart:async';

import 'package:crossdrop/core/storage/transfer_repository.dart';
import 'package:crossdrop/features/send/share_listener.dart';
import 'package:crossdrop/features/transfer/unfinished_transfers.dart';
import 'package:crossdrop/platform/share_inbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Inbox implements ShareInbox {
  int takes = 0;

  @override
  Future<SharedFiles> takePending() async {
    takes++;
    return const SharedFiles();
  }

  @override
  Stream<void> get arrivals => const Stream.empty();
}

void main() {
  Future<_Inbox> pump(
    WidgetTester tester,
    Future<List<StoredSession>> Function() cleanup,
  ) async {
    final inbox = _Inbox();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shareInboxProvider.overrideWithValue(inbox),
          unfinishedTransfersProvider.overrideWith((ref) => cleanup()),
        ],
        child: const MaterialApp(home: ShareListener(child: SizedBox())),
      ),
    );
    await tester.pump();
    return inbox;
  }

  testWidgets('a share is taken only after the launch cleanup', (tester) async {
    // Review H4: the cleanup deletes staging folders no unfinished send
    // uses, so a share moved into staging before it ran was lost.
    final cleanup = Completer<List<StoredSession>>();
    final inbox = await pump(tester, () => cleanup.future);
    expect(inbox.takes, 0);
    cleanup.complete(const []);
    await tester.pump();
    expect(inbox.takes, 1);
  });

  testWidgets('a failed cleanup does not block the share', (tester) async {
    final inbox = await pump(
      tester,
      () async => throw StateError('no database'),
    );
    await tester.pump();
    expect(inbox.takes, 1);
  });
}
