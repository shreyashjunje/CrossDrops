import 'package:crossdrop/core/protocol/auth_messages.dart';
import 'package:crossdrop/core/security/device_credentials.dart';
import 'package:crossdrop/core/security/peer_auth.dart';
import 'package:crossdrop/core/server/rate_limiter.dart';
import 'package:crossdrop/core/server/sender_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DeviceCredentials receiver;
  late DeviceCredentials sender;
  var now = DateTime(2026, 11, 3, 10);

  setUpAll(() async {
    receiver = await DeviceCredentials.generate();
    sender = await DeviceCredentials.generate();
  });

  SenderAuthenticator newAuth({int maxChallenges = 64, int maxTokens = 256}) =>
      SenderAuthenticator(
        ownFingerprint: receiver.fingerprint,
        maxChallenges: maxChallenges,
        maxTokens: maxTokens,
        clock: () => now,
      );

  /// A full, honest exchange; returns the request so tests can tamper.
  (AuthRequest, String) prove(
    SenderAuthenticator auth, {
    DeviceCredentials? who,
    String? receiverFp,
  }) {
    final w = who ?? sender;
    final senderNonce = newNonce();
    final nonce = auth.challenge(
      authCommitment(
        receiverFingerprint: receiverFp ?? receiver.fingerprint,
        senderFingerprint: w.fingerprint,
        senderNonce: senderNonce,
      ),
    );
    final sig = w.sign(
      authSigningInput(
        receiverFingerprint: receiverFp ?? receiver.fingerprint,
        senderFingerprint: w.fingerprint,
        receiverNonce: nonce,
        senderNonce: senderNonce,
      ),
    );
    return (
      AuthRequest(
        certificate: w.certificateDer,
        nonce: nonce,
        senderNonce: senderNonce,
        signature: sig,
      ),
      senderNonce,
    );
  }

  Matcher fails(String reason) =>
      throwsA(isA<AuthFailure>().having((e) => e.reason, 'reason', reason));

  group('SenderAuthenticator', () {
    test('accepts an honest proof; the token maps to the fingerprint', () {
      final auth = newAuth();
      final (req, senderNonce) = prove(auth);
      final granted = auth.authenticate(req);
      expect(granted.sender.fingerprint, sender.fingerprint);
      expect(auth.lookup(granted.token)?.fingerprint, sender.fingerprint);
      expect(
        granted.sender.pairingCode,
        derivePairingCode(
          senderFingerprint: sender.fingerprint,
          receiverFingerprint: receiver.fingerprint,
          senderNonce: senderNonce,
          receiverNonce: req.nonce,
        ),
      );
    });

    test('a challenge is single-use, even after a failure', () {
      final auth = newAuth();
      final (req, _) = prove(auth);
      auth.authenticate(req);
      expect(() => auth.authenticate(req), fails('unknown nonce'));

      final (req2, _) = prove(auth);
      final bad = AuthRequest(
        certificate: req2.certificate,
        nonce: req2.nonce,
        senderNonce: req2.senderNonce,
        signature: [...req2.signature]..[10] ^= 1,
      );
      expect(() => auth.authenticate(bad), fails('bad signature'));
      expect(() => auth.authenticate(req2), fails('unknown nonce'));
    });

    test('a sender nonce that does not match the commitment is refused', () {
      final auth = newAuth();
      final (req, _) = prove(auth);
      final swapped = AuthRequest(
        certificate: req.certificate,
        nonce: req.nonce,
        senderNonce: newNonce(),
        signature: req.signature,
      );
      expect(() => auth.authenticate(swapped), fails('commitment mismatch'));
    });

    test('a certificate other than the committed one is refused', () async {
      // Review H1: a man in the middle learns both nonces, then tries
      // certificates until the receiver's code matches the sender's. The
      // commitment fixed the certificate before the receiver's nonce, so
      // any other one fails, even with a valid signature from its key.
      final auth = newAuth();
      final attacker = await DeviceCredentials.generate();
      final senderNonce = newNonce();
      final nonce = auth.challenge(
        authCommitment(
          receiverFingerprint: receiver.fingerprint,
          senderFingerprint: sender.fingerprint,
          senderNonce: senderNonce,
        ),
      );
      final forged = AuthRequest(
        certificate: attacker.certificateDer,
        nonce: nonce,
        senderNonce: senderNonce,
        signature: attacker.sign(
          authSigningInput(
            receiverFingerprint: receiver.fingerprint,
            senderFingerprint: attacker.fingerprint,
            receiverNonce: nonce,
            senderNonce: senderNonce,
          ),
        ),
      );
      expect(() => auth.authenticate(forged), fails('commitment mismatch'));
    });

    test('a commitment made for another receiver is refused', () async {
      final auth = newAuth();
      final other = await DeviceCredentials.generate();
      final (req, _) = prove(auth, receiverFp: other.fingerprint);
      expect(() => auth.authenticate(req), fails('commitment mismatch'));
    });

    test('a signature made for another receiver is refused', () async {
      final auth = newAuth();
      final other = await DeviceCredentials.generate();
      final senderNonce = newNonce();
      final nonce = auth.challenge(
        authCommitment(
          receiverFingerprint: receiver.fingerprint,
          senderFingerprint: sender.fingerprint,
          senderNonce: senderNonce,
        ),
      );
      final req = AuthRequest(
        certificate: sender.certificateDer,
        nonce: nonce,
        senderNonce: senderNonce,
        signature: sender.sign(
          authSigningInput(
            receiverFingerprint: other.fingerprint,
            senderFingerprint: sender.fingerprint,
            receiverNonce: nonce,
            senderNonce: senderNonce,
          ),
        ),
      );
      expect(() => auth.authenticate(req), fails('bad signature'));
    });

    test('our own certificate is refused', () {
      final auth = newAuth();
      final (req, _) = prove(auth, who: receiver);
      expect(() => auth.authenticate(req), fails('own certificate'));
    });

    test('garbage certificates are refused', () {
      final auth = newAuth();
      final (req, _) = prove(auth);
      final junk = AuthRequest(
        certificate: [0x30, 0x03, 1, 2, 3],
        nonce: req.nonce,
        senderNonce: req.senderNonce,
        signature: req.signature,
      );
      expect(() => auth.authenticate(junk), throwsA(isA<AuthFailure>()));
    });

    test('challenges expire after 60 s', () {
      final auth = newAuth();
      final (req, _) = prove(auth);
      now = now.add(const Duration(seconds: 61));
      expect(() => auth.authenticate(req), fails('unknown nonce'));
    });

    test('tokens expire after an hour unused; use extends them', () {
      final auth = newAuth();
      final token = auth.authenticate(prove(auth).$1).token;
      now = now.add(const Duration(minutes: 50));
      expect(auth.lookup(token), isNotNull);
      now = now.add(const Duration(minutes: 50));
      expect(auth.lookup(token), isNotNull);
      now = now.add(const Duration(minutes: 61));
      expect(auth.lookup(token), isNull);
      expect(auth.lookup('nonsense'), isNull);
    });

    test('memory is bounded: the oldest challenge and token are dropped', () {
      final auth = newAuth(maxChallenges: 2, maxTokens: 1);
      final (first, _) = prove(auth);
      prove(auth);
      prove(auth);
      expect(() => auth.authenticate(first), fails('unknown nonce'));

      final t1 = auth.authenticate(prove(auth).$1).token;
      final t2 = auth.authenticate(prove(auth).$1).token;
      expect(auth.lookup(t1), isNull);
      expect(auth.lookup(t2), isNotNull);
    });
  });

  group('RateLimiter', () {
    var t = DateTime(2026);
    RateLimiter limiter({int burst = 3, int maxKeys = 1024}) => RateLimiter(
      burst: burst,
      refillEvery: const Duration(seconds: 20),
      maxKeys: maxKeys,
      clock: () => t,
    );

    test('allows a burst, then one per refill period', () {
      final l = limiter();
      expect([for (var i = 0; i < 3; i++) l.take('a')], [null, null, null]);
      final wait = l.take('a');
      expect(wait, isNotNull);
      expect(wait!.inSeconds, inInclusiveRange(19, 20));
      t = t.add(const Duration(seconds: 20));
      expect(l.take('a'), isNull);
      expect(l.take('a'), isNotNull);
    });

    test('addresses have separate buckets', () {
      final l = limiter(burst: 1);
      expect(l.take('a'), isNull);
      expect(l.take('a'), isNotNull);
      expect(l.take('b'), isNull);
    });

    test('never refills beyond the burst', () {
      final l = limiter(burst: 2);
      t = t.add(const Duration(days: 1));
      expect(l.take('a'), isNull);
      expect(l.take('a'), isNull);
      expect(l.take('a'), isNotNull);
    });

    test('remembers at most maxKeys addresses', () {
      final l = limiter(maxKeys: 10);
      for (var i = 0; i < 100; i++) {
        l.take('ip$i');
      }
      expect(l.trackedKeys, 10);
    });
  });
}
