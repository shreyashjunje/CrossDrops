import Flutter
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var localNetwork: LocalNetworkChannel?
  private var storage: StorageChannel?
  private var background: BackgroundTaskChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LocalNetworkChannel") {
      localNetwork = LocalNetworkChannel(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "StorageChannel") {
      storage = StorageChannel(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BackgroundTaskChannel") {
      background = BackgroundTaskChannel(messenger: registrar.messenger())
    }
  }
}

/// Platform channel `crossdrop/background` (Dart side:
/// lib/platform/keep_alive.dart).
///
/// - `begin`: asks iOS for a little time after the app leaves the screen
///   (about 30 s), so the transfer can finish its chunk and save progress.
/// - `end`: gives the time back.
/// - Native to Dart `expiring`: iOS wants the time back now; the task is
///   ended right after.
final class BackgroundTaskChannel {
  private let channel: FlutterMethodChannel
  private var task: UIBackgroundTaskIdentifier = .invalid

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "crossdrop/background", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "begin":
        self.begin()
        result(nil)
      case "end":
        self.end()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func begin() {
    guard task == .invalid else { return }
    task = UIApplication.shared.beginBackgroundTask(withName: "CrossDrop transfer") {
      [weak self] in
      guard let self else { return }
      self.channel.invokeMethod("expiring", arguments: nil)
      self.end()
    }
  }

  private func end() {
    guard task != .invalid else { return }
    UIApplication.shared.endBackgroundTask(task)
    task = .invalid
  }
}

/// Platform channel `crossdrop/storage` (Dart side:
/// lib/platform/free_space.dart).
///
/// - `freeBytes {path}` -> Int: space available for user-initiated saves on
///   the volume holding `path` (counts purgeable caches, like Files does).
final class StorageChannel {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "crossdrop/storage", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "freeBytes" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let path = (call.arguments as? [String: Any])?["path"] as? String else {
        result(FlutterError(code: "bad_args", message: "path missing", details: nil))
        return
      }
      // The folder may not exist yet; its nearest existing parent is on the
      // same volume.
      var url = URL(fileURLWithPath: path)
      while !FileManager.default.fileExists(atPath: url.path) && url.path != "/" {
        url.deleteLastPathComponent()
      }
      do {
        let values = try url.resourceValues(forKeys: [
          .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        ])
        if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
          result(NSNumber(value: important))
        } else if let plain = values.volumeAvailableCapacity {
          result(NSNumber(value: plain))
        } else {
          result(nil)
        }
      } catch {
        result(FlutterError(code: "query_failed", message: nil, details: nil))
      }
    }
  }
}

/// Platform channel `crossdrop/local_network` (Dart side:
/// lib/platform/local_network.dart).
///
/// - `probe` -> "granted" | "denied" | "unknown"
/// - `openSettings` opens this app's page in Settings.
///
/// iOS has no API to read the Local Network permission. The probe advertises
/// a short-lived Bonjour service and browses for it: seeing it proves the
/// permission is granted; a browser stuck in `.waiting(PolicyDenied)` until
/// the timeout means it is denied. bonsoir does not report this state.
final class LocalNetworkChannel {
  private let channel: FlutterMethodChannel
  private var probe: LocalNetworkProbe?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "crossdrop/local_network", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "probe":
      let timeout = (call.arguments as? [String: Any])?["timeoutMs"] as? Int ?? 8000
      // A probe still running answers "unknown" so its caller is not left
      // waiting.
      probe?.cancel()
      let p = LocalNetworkProbe(timeout: .milliseconds(timeout)) { status in
        result(status)
      }
      probe = p
      p.start()
    case "openSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

final class LocalNetworkProbe {
  private let queue = DispatchQueue(label: "crossdrop.localnetwork.probe")
  private let serviceType = "_crossdrop._tcp"
  private let serviceName = "CrossDrop-probe-" + UUID().uuidString.prefix(8)
  private let timeout: DispatchTimeInterval
  private let completion: (String) -> Void
  private var listener: NWListener?
  private var browser: NWBrowser?
  private var sawPolicyDenied = false
  private var done = false

  init(timeout: DispatchTimeInterval, completion: @escaping (String) -> Void) {
    self.timeout = timeout
    self.completion = completion
  }

  func start() {
    queue.async { self.begin() }
  }

  func cancel() {
    queue.async { self.finish("unknown") }
  }

  private func begin() {
    do {
      let listener = try NWListener(using: .tcp)
      listener.service = NWListener.Service(name: serviceName, type: serviceType)
      // Nobody should connect; refuse anything that does.
      listener.newConnectionHandler = { $0.cancel() }
      listener.stateUpdateHandler = { [weak self] state in
        if case .failed = state { self?.finish("unknown") }
      }
      self.listener = listener
      listener.start(queue: queue)
    } catch {
      finish("unknown")
      return
    }

    let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
    browser.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .waiting(let error), .failed(let error):
        // While the first-run prompt is showing the browser also waits with
        // PolicyDenied, so only conclude "denied" at the timeout.
        if case .dns(let code) = error, code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) {
          self.sawPolicyDenied = true
        }
      default:
        break
      }
    }
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      guard let self else { return }
      for r in results {
        if case .service(let name, _, _, _) = r.endpoint, name == self.serviceName {
          self.finish("granted")
          return
        }
      }
    }
    self.browser = browser
    browser.start(queue: queue)

    queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
      guard let self else { return }
      self.finish(self.sawPolicyDenied ? "denied" : "unknown")
    }
  }

  /// Runs on `queue`. Answers once.
  private func finish(_ status: String) {
    guard !done else { return }
    done = true
    browser?.cancel()
    listener?.cancel()
    browser = nil
    listener = nil
    DispatchQueue.main.async { self.completion(status) }
  }
}
