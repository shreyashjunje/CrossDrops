/// A local-only Wi-Fi hotspot started by CrossDrop on Android
/// (ARCHITECTURE.md, scenario 4). Phase 6 builds the screens against this
/// interface; Phase 7 adds the LocalOnlyHotspot implementation.
abstract interface class HotspotService {
  /// Whether this phone can start a hotspot from the app.
  Future<HotspotSupport> support();

  /// Starts the hotspot. Throws [HotspotException].
  Future<HotspotInfo> start();

  Future<void> stop();
}

enum HotspotSupport {
  available,

  /// Not built yet (Phase 6): the screens explain the manual way.
  notYet,

  /// This platform cannot (iPhone: apps cannot create a hotspot).
  unsupported,
}

/// The network the other phone joins. Never logged (CLAUDE.md hard rule
/// 7).
class HotspotInfo {
  const HotspotInfo({
    required this.ssid,
    required this.password,
    required this.qrPayload,
  });

  final String ssid;
  final String password;

  /// The `crossdrop://connect` payload with the Wi-Fi name and password
  /// (ARCHITECTURE.md, "QR code payload"); its format is Phase 7's.
  final String qrPayload;
}

class HotspotException implements Exception {
  const HotspotException(this.code);

  /// `permission`, `wifi_off`, `tethering_on`, `failed`.
  final String code;

  @override
  String toString() => 'HotspotException($code)';
}

/// Until Phase 7: no hotspot from the app.
class NoHotspot implements HotspotService {
  const NoHotspot({required this.isAndroid});

  final bool isAndroid;

  @override
  Future<HotspotSupport> support() async =>
      isAndroid ? HotspotSupport.notYet : HotspotSupport.unsupported;

  @override
  Future<HotspotInfo> start() async => throw const HotspotException('failed');

  @override
  Future<void> stop() async {}
}
