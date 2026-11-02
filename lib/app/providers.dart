import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/keep_alive.dart';
import 'keep_alive.dart';

import '../core/discovery/bonsoir_backend.dart';
import '../core/discovery/mdns_backend.dart';
import '../core/security/device_credentials.dart';
import '../core/security/device_identity.dart';
import '../core/security/secret_store.dart';
import '../core/storage/database.dart';
import '../core/storage/settings_repository.dart';
import '../core/storage/transfer_repository.dart';
import '../core/storage/trust_repository.dart';
import '../platform/free_space.dart';
import '../platform/local_network.dart';
import '../platform/secure_secret_store.dart';

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

/// iOS Keychain / Android Keystore-backed storage for the private key.
final secretStoreProvider = Provider<SecretStore>((ref) => SecureSecretStore());

/// This device's key and certificate; the fingerprint is its identity.
/// Created on first launch (ARCHITECTURE.md, "Device identity").
final credentialsProvider = FutureProvider<DeviceCredentials>(
  (ref) => CredentialRepository(
    ref.read(databaseProvider),
    ref.read(secretStoreProvider),
  ).loadOrCreate(),
);

final trustRepositoryProvider = Provider<TrustRepository>(
  (ref) => TrustRepository(ref.watch(databaseProvider)),
);

/// Trusted devices, most recently seen first.
final trustedDevicesProvider = StreamProvider<List<TrustedDevice>>(
  (ref) => ref.watch(trustRepositoryProvider).watchAll(),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);

/// The global "Receiving" switch (D-031).
final receivingEnabledProvider = StreamProvider<bool>(
  (ref) => ref.watch(settingsRepositoryProvider).watchReceivingEnabled(),
);

/// mDNS browsing and advertising (bonsoir on the phones).
final mdnsBackendProvider = Provider<MdnsBackend>((ref) => BonsoirBackend());

/// A fresh mDNS backend for one-off lookups, such as finding a receiver
/// again by id. bonsoir runs one browse per backend.
final mdnsBackendFactoryProvider = Provider<MdnsBackend Function()>(
  (ref) => BonsoirBackend.new,
);

/// Keeps transfers alive: screen on, Android foreground service, iOS
/// background task when the app is hidden.
final keepAliveProvider = Provider<KeepAliveCoordinator>((ref) {
  final c = KeepAliveCoordinator(
    PlatformKeepAlive(),
    pauseInBackground: Platform.isIOS,
  );
  final lifecycle = AppLifecycleListener(
    onHide: () => unawaited(c.appBackgrounded()),
    onShow: c.appResumed,
  );
  ref.onDispose(lifecycle.dispose);
  return c;
});

/// Local Network permission probe and the system settings link.
final localNetworkProvider = Provider<LocalNetwork>(
  (ref) => ChannelLocalNetwork(),
);

/// One event per OS connectivity change (Wi-Fi joined, left or switched).
final connectivityEventsProvider = Provider<Stream<void>>(
  (ref) => Connectivity().onConnectivityChanged.map((_) {}),
);
