import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Sender authentication and the 6-digit pairing code (D-027, D-029).
///
/// dart:io cannot accept a self-signed client certificate it does not
/// already trust, so the sender proves its identity inside the TLS
/// connection instead (ARCHITECTURE.md, "Connection security"):
///
/// 1. The sender pins the receiver's certificate, picks a random
///    `senderNonce` and sends [authCommitment] (both fingerprints and
///    `senderNonce`) to `POST /v1/auth/challenge`.
/// 2. The receiver answers with a random `nonce`.
/// 3. The sender sends its certificate, `senderNonce` and an ECDSA P-256
///    signature over [authSigningInput] to `POST /v1/auth`.
/// 4. The receiver checks the commitment against the certificate it got,
///    then the signature, and returns a token for the following requests.
///
/// The signature covers the receiver's fingerprint, so it is useless at
/// any other receiver. Both sides then derive the same pairing code from
/// both fingerprints and both nonces ([derivePairingCode]).

/// Random bytes in a nonce.
const int nonceBytes = 32;

final RegExp _noncePattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

/// 32 random bytes, base64url without padding (43 characters).
String newNonce([Random? random]) {
  final r = random ?? Random.secure();
  final bytes = Uint8List.fromList([
    for (var i = 0; i < nonceBytes; i++) r.nextInt(256),
  ]);
  return base64Url.encode(bytes).replaceAll('=', '');
}

bool isValidNonce(String value) => _noncePattern.hasMatch(value);

/// The sender's commitment, sent before it sees the receiver's nonce:
/// `SHA-256("crossdrop-commit-v2\n" + receiverFp + "\n" + senderFp + "\n"
/// + senderNonce)`, lowercase hex.
///
/// It fixes the sender's certificate as well as its nonce before the
/// receiver's nonce is known. Committing to the nonce alone (v1) let a man
/// in the middle pick its certificate after both nonces were known and
/// vary it until the two pairing codes matched (D-061).
String authCommitment({
  required String receiverFingerprint,
  required String senderFingerprint,
  required String senderNonce,
}) => sha256
    .convert(
      utf8.encode(
        'crossdrop-commit-v2\n'
        '$receiverFingerprint\n'
        '$senderFingerprint\n'
        '$senderNonce',
      ),
    )
    .toString();

/// The bytes the sender signs. Every field has a fixed format (hex or
/// base64url), so joining with newlines is unambiguous.
List<int> authSigningInput({
  required String receiverFingerprint,
  required String senderFingerprint,
  required String receiverNonce,
  required String senderNonce,
}) => utf8.encode(
  'crossdrop-auth-v1\n'
  '$receiverFingerprint\n'
  '$senderFingerprint\n'
  '$receiverNonce\n'
  '$senderNonce',
);

/// The 6-digit code both phones show when the receiver does not trust the
/// sender yet (ARCHITECTURE.md, "Pairing").
///
/// `SHA-256("crossdrop-code-v1\n" + senderFp + "\n" + receiverFp + "\n" +
/// senderNonce + "\n" + receiverNonce)`; the first 6 bytes as a big-endian
/// number, modulo 1,000,000, zero-padded to 6 digits.
///
/// The nonces stop a man in the middle from trying keys until the codes on
/// both sides match: every sender commits to its certificate and nonce
/// before it sees the receiver's nonce ([authCommitment]), so each attempt
/// has one chance in a million.
String derivePairingCode({
  required String senderFingerprint,
  required String receiverFingerprint,
  required String senderNonce,
  required String receiverNonce,
}) {
  final digest = sha256
      .convert(
        utf8.encode(
          'crossdrop-code-v1\n'
          '$senderFingerprint\n'
          '$receiverFingerprint\n'
          '$senderNonce\n'
          '$receiverNonce',
        ),
      )
      .bytes;
  var n = 0;
  for (var i = 0; i < 6; i++) {
    n = (n << 8) | digest[i];
  }
  return (n % 1000000).toString().padLeft(6, '0');
}

/// `123456` as `123 456`, easier to compare by eye.
String formatPairingCode(String code) =>
    '${code.substring(0, 3)} ${code.substring(3)}';
