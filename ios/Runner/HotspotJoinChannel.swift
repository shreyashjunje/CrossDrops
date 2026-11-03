import Flutter
import Foundation
import NetworkExtension

/// Platform channel `crossdrop/hotspot_join` (Dart side:
/// lib/platform/hotspot.dart).
///
/// Joins the Android phone's hotspot from the app with
/// NEHotspotConfiguration (D-055). Needs the Hotspot Configuration
/// capability (`com.apple.developer.networking.HotspotConfiguration`), which
/// Apple gives to paid Developer Program accounts only; free Apple ID builds
/// answer `canJoin` false and the user joins in Settings.
///
/// - `canJoin` -> Bool: the provisioning profile grants the entitlement.
///   Builds without an embedded profile (App Store) answer true; a missing
///   entitlement then shows up as `notAvailable` from `join`.
/// - `join {ssid, password}` -> "requested" | "alreadyJoined" |
///   "userDenied" | "notAvailable" | "invalid" | "failed". `joinOnce` is
///   off: with it, iOS drops the network 15 s after the app leaves the
///   screen or when the phone sleeps, which would break resume.
/// - `forget {ssid}` removes the network CrossDrop added.
///
/// The name and password are never logged.
final class HotspotJoinChannel {
  private let channel: FlutterMethodChannel
  private static let entitlement = "com.apple.developer.networking.HotspotConfiguration"

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "crossdrop/hotspot_join", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "canJoin":
      result(Self.profileAllowsJoin())
    case "join":
      guard let ssid = args["ssid"] as? String, let password = args["password"] as? String else {
        result(FlutterError(code: "bad_args", message: nil, details: nil))
        return
      }
      join(ssid: ssid, password: password, result: result)
    case "forget":
      if let ssid = args["ssid"] as? String {
        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func join(ssid: String, password: String, result: @escaping FlutterResult) {
    let manager = NEHotspotConfigurationManager.shared
    // Networks from earlier sessions: remove them, so iOS does not keep a
    // list of old CrossDrop networks. All configurations this app sees are
    // its own.
    manager.getConfiguredSSIDs { configured in
      for old in configured where old != ssid {
        manager.removeConfiguration(forSSID: old)
      }
      let config = NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
      config.joinOnce = false
      manager.apply(config) { error in
        DispatchQueue.main.async { result(Self.outcome(error)) }
      }
    }
  }

  private static func outcome(_ error: Error?) -> String {
    guard let error = error as NSError? else { return "requested" }
    guard error.domain == NEHotspotConfigurationErrorDomain else { return "failed" }
    switch NEHotspotConfigurationError(rawValue: error.code) {
    case .alreadyAssociated:
      return "alreadyJoined"
    case .userDenied:
      return "userDenied"
    case .invalid, .invalidSSID, .invalidWPAPassphrase, .invalidSSIDPrefix:
      return "invalid"
    case .pending, .applicationIsNotInForeground:
      return "failed"
    default:
      // `internal` is what iOS returns without the entitlement; newer
      // codes (system denied, unauthorized) also mean "join in Settings".
      return "notAvailable"
    }
  }

  /// Reads this app's own embedded provisioning profile: a signed plist
  /// whose `Entitlements` lists what the signature allows.
  private static func profileAllowsJoin() -> Bool {
    guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
      let data = try? Data(contentsOf: url)
    else {
      return true  // No profile: App Store build; try, and fall back.
    }
    guard let start = data.range(of: Data("<?xml".utf8)),
      let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
    else {
      return false
    }
    let xml = data.subdata(in: start.lowerBound..<end.upperBound)
    guard
      let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil)
        as? [String: Any],
      let entitlements = plist["Entitlements"] as? [String: Any]
    else {
      return false
    }
    return (entitlements[entitlement] as? Bool) == true
  }
}

/// Platform channel `crossdrop/network` (Dart side:
/// lib/platform/network.dart), iOS part.
///
/// - `interfaces` -> list of `{name, ip, prefix}` for every IPv4 address,
///   from getifaddrs. Personal Hotspot shows as `bridge100`.
///
/// `wifiState` and `bind` are Android only: iOS sends local subnet traffic
/// over Wi-Fi even when that Wi-Fi has no internet.
final class NetworkInfoChannel {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "crossdrop/network", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "interfaces":
        result(Self.interfaces())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func interfaces() -> [[String: Any]] {
    var out: [[String: Any]] = []
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0, let first = head else { return out }
    defer { freeifaddrs(head) }
    for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let ifa = ptr.pointee
      guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
        let mask = ifa.ifa_netmask
      else { continue }
      let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
      let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
        $0.pointee.sin_addr.s_addr
      }
      var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
      var ipCopy = ip
      guard inet_ntop(AF_INET, &ipCopy, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
        continue
      }
      out.append([
        "name": String(cString: ifa.ifa_name),
        "ip": String(cString: buffer),
        "prefix": UInt32(bigEndian: netmask).nonzeroBitCount,
      ])
    }
    return out
  }
}
