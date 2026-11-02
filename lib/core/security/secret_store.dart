/// Key-value storage for secrets: the iOS Keychain or Android
/// Keystore-protected storage on the phones (`lib/platform/`), memory in
/// tests (CLAUDE.md hard rule 9).
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
