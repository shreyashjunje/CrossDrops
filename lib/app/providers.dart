import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/device_identity.dart';
import '../core/storage/database.dart';

/// The app's database, open for the app's lifetime.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final identityProvider =
    AsyncNotifierProvider<IdentityNotifier, DeviceIdentity>(
      IdentityNotifier.new,
    );

/// This device's id and name, created on first launch.
class IdentityNotifier extends AsyncNotifier<DeviceIdentity> {
  IdentityRepository get _repo =>
      IdentityRepository(ref.read(databaseProvider));

  @override
  Future<DeviceIdentity> build() => _repo.loadOrCreate();

  /// Throws [ArgumentError] if the name is empty after sanitizing.
  Future<void> rename(String name) async {
    state = AsyncData(await _repo.rename(name));
  }
}
