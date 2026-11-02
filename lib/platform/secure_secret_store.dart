import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/security/secret_store.dart';

/// [SecretStore] backed by flutter_secure_storage (D-030).
///
/// - iOS: Keychain, readable after the first unlock, this device only (not
///   synced to iCloud, not moved to a new phone by a backup).
/// - Android: values encrypted with AES-GCM under a key held in the
///   Android Keystore. App backup is off (AndroidManifest), so a reinstall
///   or a new phone gets a new identity.
class SecureSecretStore implements SecretStore {
  SecureSecretStore()
    : _storage = const FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
        aOptions: AndroidOptions(),
      );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
