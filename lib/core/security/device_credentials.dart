import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';

import 'fingerprint.dart';

/// ECDSA with SHA-256 and a deterministic nonce (RFC 6979), so a signature
/// never depends on the random source. basic_utils defaults to SHA-1:
/// always pass this.
const String _signatureAlgorithm = 'SHA-256/DET-ECDSA';

/// Verification is the same for deterministic and random nonces.
const String _verifyAlgorithm = 'SHA-256/ECDSA';

/// Largest peer certificate accepted, in DER bytes. Ours are about 400.
const int maxCertificateBytes = 4096;

/// Certificates are pinned by fingerprint, so the validity period is never
/// checked; 20 years keeps the date in UTCTime (before 2050).
const int _validityDays = 7300;

/// This device's ECDSA P-256 key and self-signed certificate. The SHA-256
/// fingerprint of the certificate is the device identity
/// (ARCHITECTURE.md, "Device identity").
///
/// The private key is kept in secure storage ([CredentialRepository]), never
/// in a plain file or the database. It is in this process's memory while
/// the app runs, because Dart's TLS stack needs it as bytes.
class DeviceCredentials {
  DeviceCredentials._(
    this._privateKey, {
    required this.certificatePem,
    required this.privateKeyPem,
    required this.certificateDer,
  }) : fingerprint = certificateFingerprint(certificateDer);

  final String certificatePem;

  /// Never log this (CLAUDE.md hard rule 7).
  final String privateKeyPem;
  final Uint8List certificateDer;

  /// Lowercase hex SHA-256 of [certificateDer].
  final String fingerprint;
  final ECPrivateKey _privateKey;

  /// Creates a new key pair and certificate in a background isolate.
  static Future<DeviceCredentials> generate() async {
    final (cert, key) = await Isolate.run(_generatePem);
    return fromPem(certificatePem: cert, privateKeyPem: key);
  }

  static (String, String) _generatePem() {
    final pair = CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
    final privateKey = pair.privateKey as ECPrivateKey;
    final csr = X509Utils.generateEccCsrPem(
      // No device name or id: the certificate is sent to every peer.
      {'CN': 'CrossDrop'},
      privateKey,
      pair.publicKey as ECPublicKey,
    );
    final cert = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      _validityDays,
      serialNumber: '${DateTime.now().microsecondsSinceEpoch}',
    );
    return (cert, CryptoUtils.encodeEcPrivateKeyToPem(privateKey));
  }

  /// Loads stored credentials. Throws [FormatException] if either part is
  /// unreadable or the key does not belong to the certificate.
  static DeviceCredentials fromPem({
    required String certificatePem,
    required String privateKeyPem,
  }) {
    final ECPrivateKey key;
    final Uint8List der;
    try {
      key = CryptoUtils.ecPrivateKeyFromPem(privateKeyPem);
      der = CryptoUtils.getBytesFromPEMString(certificatePem);
    } on Object {
      throw const FormatException('unreadable credentials');
    }
    final creds = DeviceCredentials._(
      key,
      certificatePem: certificatePem,
      privateKeyPem: privateKeyPem,
      certificateDer: der,
    );
    final probe = Uint8List.fromList(utf8.encode('crossdrop-key-check'));
    if (!PeerCertificate.parse(der).verify(probe, creds.sign(probe))) {
      throw const FormatException('key does not match certificate');
    }
    return creds;
  }

  /// DER-encoded ECDSA P-256 / SHA-256 signature of [data].
  Uint8List sign(List<int> data) {
    final sig = CryptoUtils.ecSign(
      _privateKey,
      Uint8List.fromList(data),
      algorithmName: _signatureAlgorithm,
    );
    return base64.decode(CryptoUtils.ecSignatureToBase64(sig));
  }

  /// TLS context for the receive server: this certificate, TLS 1.3 only
  /// (both ends are CrossDrop, so 1.3 is always available).
  SecurityContext serverContext() => SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(certificatePem))
    ..usePrivateKeyBytes(utf8.encode(privateKeyPem))
    ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3;
}

/// Another device's certificate, as received during authentication.
class PeerCertificate {
  PeerCertificate._(this.der, this._publicKey)
    : fingerprint = certificateFingerprint(der);

  final Uint8List der;
  final String fingerprint;
  final ECPublicKey _publicKey;

  /// Throws [FormatException] unless [der] is an X.509 certificate with an
  /// ECDSA P-256 public key, at most [maxCertificateBytes] long.
  ///
  /// The certificate's own signature and dates are not checked: identity
  /// is the fingerprint, and the peer proves it holds the key by signing a
  /// challenge (see `peer_auth.dart`).
  static PeerCertificate parse(List<int> der) {
    if (der.isEmpty || der.length > maxCertificateBytes) {
      throw const FormatException('certificate size');
    }
    final bytes = Uint8List.fromList(der);
    try {
      final data = X509Utils.x509CertificateFromPem(
        X509Utils.formatKeyString(
          base64.encode(bytes),
          X509Utils.BEGIN_CERT,
          X509Utils.END_CERT,
        ),
      );
      final spki = data.tbsCertificate?.subjectPublicKeyInfo;
      final spkiHex = spki?.bytes;
      if (spki == null ||
          spkiHex == null ||
          spki.algorithm != '1.2.840.10045.2.1') {
        throw const FormatException('not an EC key');
      }
      final key = CryptoUtils.ecPublicKeyFromDerBytes(_hexBytes(spkiHex));
      if (key.parameters?.domainName != 'prime256v1') {
        throw const FormatException('not P-256');
      }
      return PeerCertificate._(bytes, key);
    } on FormatException {
      rethrow;
    } on Object {
      // The ASN.1 parser throws many error types on malformed input.
      throw const FormatException('unreadable certificate');
    }
  }

  /// True if [signature] (DER ECDSA) signs [data] with this key.
  bool verify(List<int> data, List<int> signature) {
    try {
      return CryptoUtils.ecVerify(
        _publicKey,
        Uint8List.fromList(data),
        CryptoUtils.ecSignatureFromDerBytes(Uint8List.fromList(signature)),
        algorithm: _verifyAlgorithm,
      );
    } on Object {
      return false;
    }
  }

  static Uint8List _hexBytes(String hex) {
    final h = hex.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    return Uint8List.fromList([
      for (var i = 0; i + 1 < h.length; i += 2)
        int.parse(h.substring(i, i + 2), radix: 16),
    ]);
  }
}
