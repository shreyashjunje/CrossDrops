import 'dart:convert';

import '../security/device_credentials.dart';
import '../security/peer_auth.dart';
import 'models.dart';

/// Messages of `POST /v1/auth/challenge` and `POST /v1/auth`
/// (ARCHITECTURE.md, "Protocol spec"; flow in `peer_auth.dart`).

final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

/// Body of `POST /v1/auth/challenge`.
class AuthChallengeRequest {
  const AuthChallengeRequest({required this.commit});

  /// [authCommitment] of both fingerprints and the sender's nonce.
  final String commit;

  Map<String, Object?> toJson() => {'commit': commit};

  factory AuthChallengeRequest.fromJson(Object? json) {
    if (json is! Map<String, Object?>) throw FormatError('not an object');
    final commit = json['commit'];
    if (commit is! String || !_hex64.hasMatch(commit)) {
      throw FormatError('invalid commit');
    }
    return AuthChallengeRequest(commit: commit);
  }
}

/// Reply to `POST /v1/auth/challenge`.
class AuthChallenge {
  const AuthChallenge({required this.nonce});

  final String nonce;

  Map<String, Object?> toJson() => {'nonce': nonce};

  factory AuthChallenge.fromJson(Object? json) {
    if (json is! Map<String, Object?>) throw FormatError('not an object');
    final nonce = json['nonce'];
    if (nonce is! String || !isValidNonce(nonce)) {
      throw FormatError('invalid nonce');
    }
    return AuthChallenge(nonce: nonce);
  }
}

/// Body of `POST /v1/auth`.
class AuthRequest {
  const AuthRequest({
    required this.certificate,
    required this.nonce,
    required this.senderNonce,
    required this.signature,
  });

  /// The sender's certificate, DER.
  final List<int> certificate;

  /// The receiver's nonce from the challenge.
  final String nonce;
  final String senderNonce;

  /// DER ECDSA signature over [authSigningInput].
  final List<int> signature;

  Map<String, Object?> toJson() => {
    'certificate': base64.encode(certificate),
    'nonce': nonce,
    'senderNonce': senderNonce,
    'signature': base64.encode(signature),
  };

  factory AuthRequest.fromJson(Object? json) {
    if (json is! Map<String, Object?>) throw FormatError('not an object');
    final cert = json['certificate'];
    final nonce = json['nonce'];
    final senderNonce = json['senderNonce'];
    final signature = json['signature'];
    if (nonce is! String || !isValidNonce(nonce)) {
      throw FormatError('invalid nonce');
    }
    if (senderNonce is! String || !isValidNonce(senderNonce)) {
      throw FormatError('invalid senderNonce');
    }
    // Base64 is 4/3 of the bytes; refuse before decoding anything large.
    if (cert is! String || cert.length > maxCertificateBytes * 2) {
      throw FormatError('invalid certificate');
    }
    if (signature is! String || signature.length > 256) {
      throw FormatError('invalid signature');
    }
    try {
      return AuthRequest(
        certificate: base64.decode(cert),
        nonce: nonce,
        senderNonce: senderNonce,
        signature: base64.decode(signature),
      );
    } on FormatException {
      throw FormatError('invalid base64');
    }
  }
}

/// Reply to `POST /v1/auth`.
class AuthGranted {
  const AuthGranted({required this.token, required this.expiresIn});

  /// Sent as `Authorization: Bearer <token>` on every other request.
  final String token;

  /// Seconds until the token expires if unused.
  final int expiresIn;

  Map<String, Object?> toJson() => {'token': token, 'expiresIn': expiresIn};

  factory AuthGranted.fromJson(Object? json) {
    if (json is! Map<String, Object?>) throw FormatError('not an object');
    final token = json['token'];
    final expiresIn = json['expiresIn'];
    if (token is! String || !isValidNonce(token) || expiresIn is! int) {
      throw FormatError('invalid auth reply');
    }
    return AuthGranted(token: token, expiresIn: expiresIn);
  }
}
