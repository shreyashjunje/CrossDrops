import CryptoKit
import Flutter
import QuickLook
import QuickLookThumbnailing
import UIKit
import UniformTypeIdentifiers

/// Platform channel `crossdrop/open` (Dart side: lib/platform/open_file.dart).
///
/// - `open {location}` -> true if something was shown (D-051).
///   - `photos:<id>`: opens the Photos app. It cannot jump to one photo.
///   - A path: previewed with Quick Look, only if it is inside Documents,
///     where received files are saved. Anything else is refused.
/// - `pickFolder {staging}` -> `{files: [{path, name, size, modifiedMs,
///   folder}], skipped}` or nil if the user backed out (D-075). The folder's
///   files (subfolders included, hidden files left out) are cloned into
///   `staging`, which keeps them readable for a resume after a restart and
///   costs no space on APFS. `folder` starts with the folder's own name.
///   iCloud files not on the phone, files that fail to copy and files past
///   10,000 are counted in `skipped`.
final class OpenFileChannel: NSObject, QLPreviewControllerDataSource,
  UIDocumentPickerDelegate
{
  private let channel: FlutterMethodChannel
  private var previewURL: URL?
  private var folderResult: FlutterResult?
  private var folderStaging: URL?

  /// The protocol's limit per offer (maxFilesPerOffer).
  private static let maxFolderFiles = 10000

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "crossdrop/open", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "pickFolder" {
      pickFolder(call.arguments as? [String: Any] ?? [:], result: result)
      return
    }
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

  // MARK: Folder picking (D-075)

  private func pickFolder(_ args: [String: Any], result: @escaping FlutterResult) {
    guard folderResult == nil else {
      result(FlutterError(code: "busy", message: nil, details: nil))
      return
    }
    guard let staging = args["staging"] as? String, let top = Self.topViewController() else {
      result(FlutterError(code: "bad_args", message: nil, details: nil))
      return
    }
    folderResult = result
    folderStaging = URL(fileURLWithPath: staging, isDirectory: true)
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
    picker.delegate = self
    top.present(picker, animated: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishFolder(nil)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
  ) {
    guard let root = urls.first, let staging = folderStaging else {
      finishFolder(nil)
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let picked = Self.cloneFolder(root, into: staging)
      DispatchQueue.main.async { self.finishFolder(picked) }
    }
  }

  private func finishFolder(_ value: Any?) {
    let result = folderResult
    folderResult = nil
    folderStaging = nil
    result?(value)
  }

  /// Clones every visible file under [root] into [staging], keeping the
  /// folder structure. Names are never logged (hard rule 7).
  private static func cloneFolder(_ root: URL, into staging: URL) -> [String: Any] {
    let scoped = root.startAccessingSecurityScopedResource()
    defer { if scoped { root.stopAccessingSecurityScopedResource() } }
    let fm = FileManager.default
    let rootName = root.lastPathComponent
    let keys: [URLResourceKey] = [
      .isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
    ]
    var files: [[String: Any]] = []
    var skipped = 0
    var coordinationError: NSError?
    NSFileCoordinator().coordinate(readingItemAt: root, options: [], error: &coordinationError) {
      readable in
      guard
        let walk = fm.enumerator(
          at: readable, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants])
      else { return }
      let base = readable.standardizedFileURL.pathComponents
      for case let url as URL in walk {
        let name = url.lastPathComponent
        if name.hasPrefix(".") {
          // An iCloud file not downloaded is a hidden ".name.icloud".
          if name.hasSuffix(".icloud") { skipped += 1 }
          if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            walk.skipDescendants()
          }
          continue
        }
        guard let values = try? url.resourceValues(forKeys: Set(keys)),
          values.isRegularFile == true
        else { continue }
        if files.count >= maxFolderFiles {
          skipped += 1
          continue
        }
        let parts = Array(url.standardizedFileURL.pathComponents.dropFirst(base.count).dropLast())
        let folder = ([rootName] + parts).joined(separator: "/")
        let dest = staging.appendingPathComponent("\(files.count)", isDirectory: true)
          .appendingPathComponent(name)
        do {
          try fm.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
          try fm.copyItem(at: url, to: dest)
        } catch {
          skipped += 1
          continue
        }
        var file: [String: Any] = [
          "path": dest.path, "name": name, "size": values.fileSize ?? -1, "folder": folder,
        ]
        if let modified = values.contentModificationDate {
          file["modifiedMs"] = Int(modified.timeIntervalSince1970 * 1000)
        }
        files.append(file)
      }
    }
    return ["files": files, "skipped": skipped]
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
