import Flutter
import QuickLook
import UIKit

/// Platform channel `crossdrop/open` (Dart side: lib/platform/open_file.dart).
///
/// - `open {location}` -> true if something was shown (D-051).
///   - `photos:<id>`: opens the Photos app. It cannot jump to one photo.
///   - A path: previewed with Quick Look, only if it is inside Documents,
///     where received files are saved. Anything else is refused.
final class OpenFileChannel: NSObject, QLPreviewControllerDataSource {
  private let channel: FlutterMethodChannel
  private var previewURL: URL?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "crossdrop/open", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "open" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let args = call.arguments as? [String: Any] ?? [:]
    guard let location = args["location"] as? String else {
      result(FlutterError(code: "bad_args", message: nil, details: nil))
      return
    }
    if location.hasPrefix("photos:") {
      // Undocumented but long-standing URL scheme of the Photos app.
      guard let url = URL(string: "photos-redirect://") else {
        result(false)
        return
      }
      UIApplication.shared.open(url, options: [:]) { ok in result(ok) }
      return
    }
    guard let url = Self.insideDocuments(location), let top = Self.topViewController() else {
      result(false)
      return
    }
    previewURL = url
    let preview = QLPreviewController()
    preview.dataSource = self
    top.present(preview, animated: true)
    result(true)
  }

  /// The file at [path] if it exists inside Documents, after resolving
  /// `..` and links.
  private static func insideDocuments(_ path: String) -> URL? {
    guard
      let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else { return nil }
    let root = docs.standardizedFileURL.resolvingSymlinksInPath().path
    let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    guard url.path.hasPrefix(root + "/"), FileManager.default.fileExists(atPath: url.path)
    else { return nil }
    return url
  }

  private static func topViewController() -> UIViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
    previewURL == nil ? 0 : 1
  }

  func previewController(_ controller: QLPreviewController, previewItemAt index: Int)
    -> QLPreviewItem
  {
    (previewURL ?? URL(fileURLWithPath: "/")) as NSURL
  }
}
