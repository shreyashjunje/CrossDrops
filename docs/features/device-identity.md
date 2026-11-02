# Feature: Device identity

- Phase: 4
- Status: Built, awaiting device tests
- Last updated: 2026-11-03

## Summary

Every phone has its own ECDSA P-256 key and self-signed certificate, made on first launch. The SHA-256 fingerprint of the certificate is the phone's identity: pinning, trust, session ownership and the pairing code are all based on it. The private key lives in the iOS Keychain or in Android Keystore-protected storage, never in a plain file or the database. Reinstalling the app gives a new identity, so other phones must pair again.

## Scope

**In scope**

- Key pair and certificate on first launch, in a background isolate.
- Private key in secure storage; certificate in the `identity` row.
- A new identity when the database is gone (reinstall), the key is gone, or the key does not match the certificate.
- No backup or device-to-device copy of the identity on Android.
- Settings shows the first 16 characters of the fingerprint ("Security key").

**Out of scope** (and which phase picks it up)

- Exporting, importing or rotating keys by hand: not planned for v1.
- Hardware-backed (non-exportable) keys: Dart's TLS stack needs the key as bytes (D-028).

## Design

ARCHITECTURE.md, "Security model", "Device identity". Specific to this feature:

- `DeviceCredentials.generate()` creates the key and a certificate with subject `CN=CrossDrop` (no personal data), 20-year validity, ECDSA-with-SHA-256, in an isolate (about 30 ms on the dev PC). `fromPem` checks that the key signs something the certificate's public key verifies.
- `CredentialRepository.loadOrCreate()`:
  1. Makes sure the identity row exists (device UUID and name, as before).
  2. If the row has a certificate and the secret store has a matching key, uses them.
  3. Otherwise makes a new pair, **writes the key first**, then the certificate. If the app dies between the two, the next launch still sees no matching pair and starts over.
- The identity row is the source of truth. iOS keeps Keychain items after an app is deleted. A reinstall has an empty database, so the old key is replaced, not reused.
- `SecretStore` is a Dart interface (hard rule 9). `SecureSecretStore` uses `flutter_secure_storage`: iOS `first_unlock_this_device`; Android AES-GCM under a Keystore-wrapped key (D-030). Tests use `MemorySecretStore`.
- Android: `allowBackup="false"`, `fullBackupContent="false"`, and `data_extraction_rules.xml` excludes everything from cloud backup and device transfer.
- The Home screen starts `credentialsProvider`, so the key exists before the user opens Receive or Send.
- The same certificate is the TLS server certificate (TLS 1.3 minimum) and the sender's certificate in `/v1/auth`.
- Logs show at most the first 8 characters of a fingerprint, never a key (hard rule 7).

Package choice: D-028 (`basic_utils`), D-030 (`flutter_secure_storage`).

## Code

| Path | Purpose |
| --- | --- |
| `lib/core/security/device_credentials.dart` | `DeviceCredentials` (key, certificate, sign, TLS context), `PeerCertificate` (parse, verify) |
| `lib/core/security/fingerprint.dart` | Fingerprint calculation, validation, comparison, short form |
| `lib/core/security/device_identity.dart` | `CredentialRepository` next to the existing `IdentityRepository` |
| `lib/core/security/secret_store.dart` | `SecretStore` interface and `MemorySecretStore` |
| `lib/platform/secure_secret_store.dart` | Keychain / Keystore implementation |
| `lib/app/providers.dart` | `secretStoreProvider`, `credentialsProvider` |
| `android/app/src/main/res/xml/data_extraction_rules.xml` | No backup, no device transfer |

## Protocol and API

- The TLS certificate of the receive server is the device certificate; the QR `fp` and TXT `fp` hint now stay the same across launches.
- The sender's certificate (base64 DER) is sent in `POST /v1/auth` ([pairing-and-trust.md](pairing-and-trust.md)).

## Tests

**Unit tests (no phones)**

- `test/core/security/device_credentials_test.dart`:
  - The fingerprint is the SHA-256 of the DER, with a known answer.
  - The key is P-256, the signature is ECDSA-SHA256, and the subject is only `CN=CrossDrop`.
  - Sign and verify work with the right key only.
  - `fromPem` round-trips and refuses a mismatched or broken key.
  - Garbage and oversized certificates are refused.
  - The repository creates once and reloads the same identity. The key is in the secret store and not in the database. A wiped database (reinstall, with the old key still in the Keychain), a lost key and a mismatched key each give a new identity.
- `test/core/security/pinning_test.dart`: the server context refuses TLS below 1.3.

**Device checks**

Listed in [DEVICE_TESTS.md](../DEVICE_TESTS.md), section "Phase 4": P4-6 (reinstall), and the "Security key" line used in every check.

## Known limits and risks

- The key is in the app's memory while it runs, because `dart:io` TLS needs it as bytes.
- iOS: if the device has no passcode, Keychain items are still stored, but with weaker protection. That is the OS default.
- An iOS backup restored to a new iPhone carries the database but not the key; that phone gets a new identity, so its old trust records no longer match. That is intended.
- `flutter_secure_storage` on Android resets its storage if the Keystore key becomes unusable (for example after some OS updates). The app then makes a new identity, and peers see a lookalike warning.

## Open questions

- None.
