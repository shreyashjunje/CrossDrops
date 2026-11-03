import 'dart:math';

import 'package:crossdrop/core/protocol/auth_messages.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/peer_auth.dart';
import 'package:flutter_test/flutter_test.dart';

const _fpS = 'aa00000000000000000000000000000000000000000000000000000000000000';
const _fpR = 'bb00000000000000000000000000000000000000000000000000000000000000';
const _fpX = 'cc00000000000000000000000000000000000000000000000000000000000000';

void main() {
  final ns = newNonce(Random(1));
  final nr = newNonce(Random(2));

  String code({
    String s = _fpS,
    String r = _fpR,
    String? senderNonce,
    String? receiverNonce,
  }) => derivePairingCode(
    senderFingerprint: s,
    receiverFingerprint: r,
    senderNonce: senderNonce ?? ns,
    receiverNonce: receiverNonce ?? nr,
  );

  group('nonces', () {
    test('are 43 base64url characters and differ', () {
      final all = {for (var i = 0; i < 200; i++) newNonce()};
      expect(all.length, 200);
      expect(all.every(isValidNonce), isTrue);
    });

    test('isValidNonce refuses other shapes', () {
      expect(isValidNonce(''), isFalse);
      expect(isValidNonce('${ns}A'), isFalse);
      expect(isValidNonce('${ns.substring(1)}='), isFalse);
      expect(isValidNonce('${ns.substring(1)}+'), isFalse);
    });

    String commit({String r = _fpR, String s = _fpS, String? nonce}) =>
        authCommitment(
          receiverFingerprint: r,
          senderFingerprint: s,
          senderNonce: nonce ?? ns,
        );

    test('authCommitment is fixed for its inputs, hex SHA-256', () {
      expect(commit(), commit());
      expect(commit(), matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('authCommitment binds the nonce and both fingerprints', () {
      // The sender's certificate is fixed before the receiver's nonce is
      // known, so a man in the middle cannot pick it later (D-061).
      expect(commit(nonce: nr), isNot(commit()));
      expect(commit(s: _fpX), isNot(commit()));
      expect(commit(r: _fpX), isNot(commit()));
      expect(commit(r: _fpS, s: _fpR), isNot(commit()));
    });

    test('authCommitment known answer, so both platforms stay in step', () {
      // Python: sha256(b"crossdrop-commit-v2\n" + fpR + b"\n" + fpS + b"\n"
      // + b"A" * 43).hexdigest()
      expect(
        commit(nonce: 'A' * 43),
        'de5904bc6044ae3d85814eed798433c6f213a4389e4c667d97616c69327b0aac',
      );
    });
  });

  group('derivePairingCode', () {
    test('is 6 digits', () {
      for (var i = 0; i < 200; i++) {
        final c = code(senderNonce: newNonce(Random(i)));
        expect(c, matches(RegExp(r'^\d{6}$')));
      }
    });

    test('both phones compute the same code from the same exchange', () {
      // Sender's view and receiver's view build the same inputs.
      final onSender = derivePairingCode(
        senderFingerprint: _fpS,
        receiverFingerprint: _fpR,
        senderNonce: ns,
        receiverNonce: nr,
      );
      final onReceiver = derivePairingCode(
        receiverNonce: nr,
        senderNonce: ns,
        receiverFingerprint: _fpR,
        senderFingerprint: _fpS,
      );
      expect(onSender, onReceiver);
    });

    test('a different peer gives a different code', () {
      expect(code(s: _fpX), isNot(code()));
      expect(code(r: _fpX), isNot(code()));
    });

    test('roles matter: swapping sender and receiver changes the code', () {
      expect(code(s: _fpR, r: _fpS), isNot(code()));
    });

    test('fresh nonces give a fresh code', () {
      expect(code(senderNonce: newNonce(Random(9))), isNot(code()));
      expect(code(receiverNonce: newNonce(Random(9))), isNot(code()));
    });

    test('known answer, so both platforms stay in step', () {
      expect(
        derivePairingCode(
          senderFingerprint: _fpS,
          receiverFingerprint: _fpR,
          senderNonce: 'A' * 43,
          receiverNonce: 'B' * 43,
        ),
        // Python: int.from_bytes(sha256(b"crossdrop-code-v1\n" + ...)
        // .digest()[:6], "big") % 10**6
        _knownCode,
      );
    });

    test('codes spread over the range', () {
      final buckets = List.filled(10, 0);
      for (var i = 0; i < 5000; i++) {
        final c = code(senderNonce: newNonce(Random(i)));
        buckets[int.parse(c[0])]++;
      }
      for (final b in buckets) {
        expect(b, inInclusiveRange(380, 620));
      }
    });

    test('formatPairingCode', () {
      expect(formatPairingCode('012345'), '012 345');
    });
  });

  test('authSigningInput binds every field', () {
    final base = authSigningInput(
      receiverFingerprint: _fpR,
      senderFingerprint: _fpS,
      receiverNonce: nr,
      senderNonce: ns,
    );
    final changed = [
      authSigningInput(
        receiverFingerprint: _fpX,
        senderFingerprint: _fpS,
        receiverNonce: nr,
        senderNonce: ns,
      ),
      authSigningInput(
        receiverFingerprint: _fpR,
        senderFingerprint: _fpX,
        receiverNonce: nr,
        senderNonce: ns,
      ),
      authSigningInput(
        receiverFingerprint: _fpR,
        senderFingerprint: _fpS,
        receiverNonce: ns,
        senderNonce: nr,
      ),
    ];
    for (final c in changed) {
      expect(c, isNot(base));
    }
  });

  group('auth messages', () {
    test('AuthChallengeRequest checks the commitment shape', () {
      final c = authCommitment(
        receiverFingerprint: _fpR,
        senderFingerprint: _fpS,
        senderNonce: ns,
      );
      expect(AuthChallengeRequest.fromJson({'commit': c}).commit, c);
      expect(
        () => AuthChallengeRequest.fromJson({'commit': 'xyz'}),
        throwsA(isA<FormatError>()),
      );
    });

    test('AuthRequest round-trips and refuses oversized fields', () {
      final r = AuthRequest(
        certificate: [1, 2, 3],
        nonce: nr,
        senderNonce: ns,
        signature: [4, 5],
      );
      final back = AuthRequest.fromJson(r.toJson());
      expect(back.certificate, [1, 2, 3]);
      expect(back.signature, [4, 5]);
      expect(
        () => AuthRequest.fromJson({...r.toJson(), 'certificate': 'A' * 9000}),
        throwsA(isA<FormatError>()),
      );
      expect(
        () => AuthRequest.fromJson({...r.toJson(), 'signature': '%%'}),
        throwsA(isA<FormatError>()),
      );
      expect(
        () => AuthRequest.fromJson({...r.toJson(), 'nonce': 'short'}),
        throwsA(isA<FormatError>()),
      );
    });
  });
}

const _knownCode = '828838';
