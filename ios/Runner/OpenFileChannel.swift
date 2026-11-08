import CryptoKit
import Flutter
import QuickLook
import QuickLookThumbnailing
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

/// Platform channel `crossdrop/thumbnail` (Dart side:
/// lib/platform/thumbnails.dart).
///
/// - `thumbnail {ref, px, kind}` -> path of a small JPEG in Caches, or nil
///   when QuickLook cannot preview the file. `ref` is a file path (an
///   exported photo, a picked document, a received file). Only the path of
///   the preview crosses the channel, never file bytes (CLAUDE.md hard
///   rule 2). Photo-library items are previewed on the Dart side.
///
/// Previews are keyed by the path, size and date of the file. iOS empties
/// Caches when it needs space. References are never logged (hard rule 7).
final class ThumbnailChannel {
  private let channel: FlutterMethodChannel
  private let dir: URL? = FileManager.default
    .urls(for: .cachesDirectory, in: .userDomainMask).first?
    .appendingPathComponent("crossdrop_thumbs", isDirectory: true)

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "crossdrop/thumbnail", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "thumbnail" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let args = call.arguments as? [String: Any] ?? [:]
    guard let ref = args["ref"] as? String else {
      result(FlutterError(code: "bad_args", message: nil, details: nil))
      return
    }
    let px = min(max((args["px"] as? NSNumber)?.intValue ?? 192, 32), 1024)
    let url = URL(fileURLWithPath: ref)
    guard let dir,
      let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
      (attrs[.type] as? FileAttributeType) == .typeRegular
    else {
      result(nil)
      return
    }
    let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
    let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    let key = Self.sha256("\(ref)|\(px)|\(size)|\(modified)")
    let out = dir.appendingPathComponent("\(key).jpg")
    if FileManager.default.fileExists(atPath: out.path) {
      result(out.path)
      return
    }
    let request = QLThumbnailGenerator.Request(
      fileAt: url, size: CGSize(width: px, height: px), scale: 1,
      representationTypes: .thumbnail)
    QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
      var path: String?
      if let data = rep?.uiImage.jpegData(compressionQuality: 0.8) {
        do {
          try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
          try data.write(to: out, options: .atomic)
          path = out.path
        } catch {
          path = nil
        }
      }
      DispatchQueue.main.async { result(path) }
    }
  }

  private static func sha256(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
