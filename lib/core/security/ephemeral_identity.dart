import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

/// A throwaway ECDSA P-256 key and self-signed certificate, created in
/// memory for each app launch.
///
/// Phase 1 only. TODO(phase4): replace with the persistent device identity
/// (key in Keychain / Keystore, fingerprint = device identity) described in
/// ARCHITECTURE.md, "Security model".
class EphemeralIdentity {
  const EphemeralIdentity._({
    required this.certificatePem,
    required this.privateKeyPem,
    required this.fingerprint,
  });

  final String certificatePem;

  /// Never log this (CLAUDE.md hard rule 7).
  final String privateKeyPem;

  /// Lowercase hex SHA-256 of the certificate DER.
  final String fingerprint;

  /// Generates the key pair and certificate in a background isolate.
  static Future<EphemeralIdentity> generate() => Isolate.run(_generate);

  static EphemeralIdentity _generate() {
    final pair = CryptoUtils.generateEcKeyPair();
    final privateKey = pair.privateKey as ECPrivateKey;
    final publicKey = pair.publicKey as ECPublicKey;
    final csr = X509Utils.generateEccCsrPem(
      {'CN': 'crossdrop'},
      privateKey,
      publicKey,
    );
    final cert = X509Utils.generateSelfSignedCertificate(privateKey, csr, 365);
    final der = CryptoUtils.getBytesFromPEMString(cert);
    return EphemeralIdentity._(
      certificatePem: cert,
      privateKeyPem: CryptoUtils.encodeEcPrivateKeyToPem(privateKey),
      fingerprint: sha256.convert(der).toString(),
    );
  }

  /// TLS context for the receive server.
  SecurityContext serverContext() => SecurityContext()
    ..useCertificateChainBytes(utf8.encode(certificatePem))
    ..usePrivateKeyBytes(utf8.encode(privateKeyPem));
}
