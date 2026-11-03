import Flutter
import UIKit

extension Notification.Name {
  /// Posted when `crossdrop://share` opens the app (from the Share Extension).
  static let crossDropShareArrived = Notification.Name("CrossDropShareArrived")
}

/// Platform channel `crossdrop/share` (Dart side: lib/platform/share_inbox.dart).
///
/// - `containerPath` -> the App Group folder the Share Extension writes
///   to, or nil if this installation has no App Group (D-045).
/// - Native to Dart `arrived` when the extension opened the app.
///
/// Dart reads, checks and moves the shared files itself.
final class ShareInboxChannel {
  private let channel: FlutterMethodChannel
  private var observer: NSObjectProtocol?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "crossdrop/share", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "containerPath":
        guard let id = Bundle.main.object(forInfoDictionaryKey: "CrossDropAppGroup") as? String,
          let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
        else {
          result(nil)
          return
        }
        result(url.path)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    observer = NotificationCenter.default.addObserver(
      forName: .crossDropShareArrived, object: nil, queue: .main
    ) { [weak self] _ in
      self?.channel.invokeMethod("arrived", arguments: nil)
    }
  }

  deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }
}
