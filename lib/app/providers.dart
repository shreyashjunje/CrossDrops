import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/discovery/bonsoir_backend.dart';
import '../core/discovery/mdns_backend.dart';
import '../core/security/device_identity.dart';
import '../core/storage/database.dart';
import '../core/storage/transfer_repository.dart';
import '../platform/free_space.dart';
import '../platform/local_network.dart';

/// The app's database, open for the app's lifetime.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final transferRepositoryProvider = Provider<TransferRepository>(
  (ref) => TransferRepository(ref.watch(databaseProvider)),
);

/// Free bytes on a volume, for the check before accepting an offer.
final freeSpaceProvider = Provider<FreeSpace>((ref) => ChannelFreeSpace());

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

/// mDNS browsing and advertising (bonsoir on the phones).
final mdnsBackendProvider = Provider<MdnsBackend>((ref) => BonsoirBackend());

/// Local Network permission probe and the system settings link.
final localNetworkProvider = Provider<LocalNetwork>(
  (ref) => ChannelLocalNetwork(),
);

/// One event per OS connectivity change (Wi-Fi joined, left or switched).
final connectivityEventsProvider = Provider<Stream<void>>(
  (ref) => Connectivity().onConnectivityChanged.map((_) {}),
);
