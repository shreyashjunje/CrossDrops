import 'dart:collection';

import '../protocol/auth_messages.dart';
import '../security/device_credentials.dart';
import '../security/peer_auth.dart';

/// A sender that proved it holds the key of [fingerprint].
class AuthenticatedSender {
  const AuthenticatedSender({
    required this.fingerprint,
    required this.pairingCode,
  });

  final String fingerprint;

  /// The code from this authentication; both phones show the same one.
  final String pairingCode;
}

class AuthFailure implements Exception {
  const AuthFailure(this.reason);

  /// For the log only; the sender always gets the same `auth_failed`.
  final String reason;

  @override
  String toString() => 'AuthFailure($reason)';
}

/// The receiver's side of sender authentication (flow in `peer_auth.dart`,
/// D-027): challenges, signature checks and tokens. Memory only; a new
/// server run starts empty and senders authenticate again.
class SenderAuthenticator {
  SenderAuthenticator({
    required this.ownFingerprint,
    this.challengeTtl = const Duration(seconds: 60),
    this.tokenTtl = const Duration(hours: 1),
    this.maxChallenges = 64,
    this.maxTokens = 256,
    DateTime Function()? clock,
    String Function()? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? newNonce;

  final String ownFingerprint;
  final Duration challengeTtl;

  /// Since last use; a sender that keeps working keeps its token.
  final Duration tokenTtl;
  final int maxChallenges;
  final int maxTokens;
  final DateTime Function() _clock;
  final String Function() _random;

  // Oldest first, so the oldest is dropped when full.
  final LinkedHashMap<String, _Challenge> _challenges = LinkedHashMap();
  final LinkedHashMap<String, _Token> _tokens = LinkedHashMap();

  /// Stores the sender's commitment and returns a fresh nonce.
  String challenge(String commit) {
    _expire();
    final nonce = _random();
    _challenges[nonce] = _Challenge(commit, _clock());
    while (_challenges.length > maxChallenges) {
      _challenges.remove(_challenges.keys.first);
    }
    return nonce;
  }

  /// Checks [request] and returns a token. Each challenge is single-use,
  /// even when the check fails. Throws [AuthFailure].
  ({String token, AuthenticatedSender sender}) authenticate(
    AuthRequest request,
  ) {
    _expire();
    final challenge = _challenges.remove(request.nonce);
    if (challenge == null) throw const AuthFailure('unknown nonce');
    final PeerCertificate cert;
    try {
      cert = PeerCertificate.parse(request.certificate);
    } on FormatException catch (e) {
      throw AuthFailure('certificate: ${e.message}');
    }
    if (cert.fingerprint == ownFingerprint) {
      throw const AuthFailure('own certificate');
    }
    // The certificate must be the one committed to before our nonce went
    // out; otherwise it could have been chosen to steer the code (D-061).
    final expected = authCommitment(
      receiverFingerprint: ownFingerprint,
      senderFingerprint: cert.fingerprint,
      senderNonce: request.senderNonce,
    );
    if (expected != challenge.commit) {
      throw const AuthFailure('commitment mismatch');
    }
    final input = authSigningInput(
      receiverFingerprint: ownFingerprint,
      senderFingerprint: cert.fingerprint,
      receiverNonce: request.nonce,
      senderNonce: request.senderNonce,
    );
    if (!cert.verify(input, request.signature)) {
      throw const AuthFailure('bad signature');
    }
    final sender = AuthenticatedSender(
      fingerprint: cert.fingerprint,
      pairingCode: derivePairingCode(
        senderFingerprint: cert.fingerprint,
        receiverFingerprint: ownFingerprint,
        senderNonce: request.senderNonce,
        receiverNonce: request.nonce,
      ),
    );
    final token = _random();
    _tokens[token] = _Token(sender, _clock());
    while (_tokens.length > maxTokens) {
      _tokens.remove(_tokens.keys.first);
    }
    return (token: token, sender: sender);
  }

  /// The sender behind [token], or null if unknown or expired. Each use
  /// extends the token's life.
  AuthenticatedSender? lookup(String token) {
    final t = _tokens.remove(token);
    if (t == null) return null;
    final now = _clock();
    if (now.difference(t.lastUsed) > tokenTtl) return null;
    t.lastUsed = now;
    _tokens[token] = t;
    return t.sender;
  }

  void _expire() {
    final now = _clock();
    _challenges.removeWhere((_, c) => now.difference(c.created) > challengeTtl);
  }
}

class _Challenge {
  _Challenge(this.commit, this.created);
  final String commit;
  final DateTime created;
}

class _Token {
  _Token(this.sender, this.lastUsed);
  final AuthenticatedSender sender;
  DateTime lastUsed;
}
