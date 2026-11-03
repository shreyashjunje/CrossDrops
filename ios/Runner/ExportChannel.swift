import Flutter
import ImageIO
import Photos
import UniformTypeIdentifiers

/// Platform channel `crossdrop/export` (Dart side: lib/platform/ios_export.dart).
///
/// Exports photo-library items to files that Dart then streams (D-038).
/// No file bytes cross this channel; only paths.
///
/// - `describe {ids}` -> list of `{id, kind, originalName?, isLivePhoto,
///   createdMs?}`. Missing items are left out.
/// - `export {id, dir, token, jpeg, pairedVideo}` -> `{originalName?,
///   createdMs?, files: [{role, path, resourceName, uti?, size,
///   converted}]}`. `role` is `still`, `video` or `paired`. Reads the
///   *current* version (edits applied) of the original resource, never a
///   resized copy, and downloads it from iCloud if needed.
/// - `cancel {token}`.
/// - Native to Dart `progress {token, fraction}` while downloading.
///
/// Errors: `not_found` (deleted, or hidden by Limited access), `icloud`
/// (download failed or stalled), `no_space`, `cancelled`, `io`.
final class ExportChannel {
  private let channel: FlutterMethodChannel
  private let queue = DispatchQueue(label: "crossdrop.export", qos: .userInitiated)
  private var jobs: [String: ExportJob] = [:]
  private let lock = NSLock()

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "crossdrop/export", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "describe":
      let ids = args["ids"] as? [String] ?? []
      queue.async {
        let list = Self.describe(ids)
        DispatchQueue.main.async { result(list) }
      }
    case "export":
      guard let id = args["id"] as? String, let dir = args["dir"] as? String,
        let token = args["token"] as? String
      else {
        result(FlutterError(code: "bad_args", message: nil, details: nil))
        return
      }
      let job = ExportJob(
        assetId: id,
        dir: URL(fileURLWithPath: dir, isDirectory: true),
        jpeg: args["jpeg"] as? Bool ?? false,
        pairedVideo: args["pairedVideo"] as? Bool ?? false,
        queue: queue,
        progress: { [weak self] fraction in
          DispatchQueue.main.async {
            self?.channel.invokeMethod("progress", arguments: ["token": token, "fraction": fraction])
          }
        })
      lock.lock()
      jobs[token] = job
      lock.unlock()
      job.run { [weak self] outcome in
        guard let self else { return }
        self.lock.lock()
        self.jobs[token] = nil
        self.lock.unlock()
        DispatchQueue.main.async {
          switch outcome {
          case .success(let value): result(value)
          case .failure(let error): result(FlutterError(code: error.code, message: nil, details: nil))
          }
        }
      }
    case "cancel":
      lock.lock()
      let job = (args["token"] as? String).flatMap { jobs[$0] }
      lock.unlock()
      job?.cancel()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func describe(_ ids: [String]) -> [[String: Any]] {
    guard !ids.isEmpty else { return [] }
    let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
    var out: [[String: Any]] = []
    fetched.enumerateObjects { asset, _, _ in
      var m: [String: Any] = [
        "id": asset.localIdentifier,
        "kind": asset.mediaType == .video ? "video" : "photo",
        "isLivePhoto": asset.mediaSubtypes.contains(.photoLive),
      ]
      if let name = originalResource(of: asset)?.originalFilename { m["originalName"] = name }
      if let date = asset.creationDate { m["createdMs"] = Int64(date.timeIntervalSince1970 * 1000) }
      out.append(m)
    }
    return out
  }

  /// The unedited original, for its file name.
  static func originalResource(of asset: PHAsset) -> PHAssetResource? {
    let resources = PHAssetResource.assetResources(for: asset)
    let wanted: [PHAssetResourceType] = asset.mediaType == .video ? [.video] : [.photo]
    return resources.first { wanted.contains($0.type) } ?? resources.first
  }
}

struct ExportError: Error {
  let code: String
}

/// Exports one asset: the still or video, and optionally a Live Photo's
/// video. Writes chunk by chunk to disk, so memory stays flat for any size.
final class ExportJob {
  private let assetId: String
  private let dir: URL
  private let jpeg: Bool
  private let pairedVideo: Bool
  private let queue: DispatchQueue
  private let progress: (Double) -> Void
  private let state = NSLock()
  private var cancelled = false
  private var request: PHAssetResourceDataRequestID?
  private var downloadSeen = false
  private var stallSeen = false
  private var watchdog: DispatchSourceTimer?

  /// No data or progress from iCloud for this long counts as a failure.
  private static let stallSeconds = 90

  init(
    assetId: String, dir: URL, jpeg: Bool, pairedVideo: Bool, queue: DispatchQueue,
    progress: @escaping (Double) -> Void
  ) {
    self.assetId = assetId
    self.dir = dir
    self.jpeg = jpeg
    self.pairedVideo = pairedVideo
    self.queue = queue
    self.progress = progress
  }

  func cancel() {
    state.lock()
    cancelled = true
    let r = request
    state.unlock()
    if let r { PHAssetResourceManager.default().cancelDataRequest(r) }
  }

  private var isCancelled: Bool {
    state.lock()
    defer { state.unlock() }
    return cancelled
  }

  func run(_ done: @escaping (Result<[String: Any], ExportError>) -> Void) {
    queue.async {
      guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [self.assetId], options: nil).firstObject
      else {
        done(.failure(ExportError(code: "not_found")))
        return
      }
      let resources = PHAssetResource.assetResources(for: asset)
      func pick(_ types: [PHAssetResourceType]) -> PHAssetResource? {
        for t in types { if let r = resources.first(where: { $0.type == t }) { return r } }
        return nil
      }
      let isVideo = asset.mediaType == .video
      // Edited items have a full-size render; send what the user sees.
      guard let main = isVideo ? pick([.fullSizeVideo, .video]) : pick([.fullSizePhoto, .photo])
      else {
        done(.failure(ExportError(code: "not_found")))
        return
      }
      var parts: [(PHAssetResource, String)] = [(main, isVideo ? "video" : "still")]
      if !isVideo && self.pairedVideo && asset.mediaSubtypes.contains(.photoLive),
        let paired = pick([.fullSizePairedVideo, .pairedVideo])
      {
        parts.append((paired, "paired"))
      }
      var meta: [String: Any] = [:]
      if let name = ExportChannel.originalResource(of: asset)?.originalFilename {
        meta["originalName"] = name
      }
      if let date = asset.creationDate {
        meta["createdMs"] = Int64(date.timeIntervalSince1970 * 1000)
      }
      do {
        try FileManager.default.createDirectory(at: self.dir, withIntermediateDirectories: true)
      } catch {
        done(.failure(ExportError(code: Self.code(for: error))))
        return
      }
      self.exportParts(parts, index: 0, files: []) { outcome in
        switch outcome {
        case .success(let files):
          meta["files"] = files
          done(.success(meta))
        case .failure(let e):
          done(.failure(e))
        }
      }
    }
  }

  private func exportParts(
    _ parts: [(PHAssetResource, String)], index: Int, files: [[String: Any]],
    done: @escaping (Result<[[String: Any]], ExportError>) -> Void
  ) {
    if index == parts.count {
      done(.success(files))
      return
    }
    let (resource, role) = parts[index]
    let ext = (resource.originalFilename as NSString).pathExtension
    let file = dir.appendingPathComponent(ext.isEmpty ? role : "\(role).\(ext.lowercased())")
    write(resource, to: file) { error in
      if let error {
        try? FileManager.default.removeItem(at: file)
        done(.failure(error))
        return
      }
      var url = file
      var uti = resource.uniformTypeIdentifier
      var converted = false
      if role == "still" && self.jpeg && Self.isHeif(uti) {
        let jpg = file.deletingPathExtension().appendingPathExtension("jpg")
        if let e = Self.convertToJpeg(from: file, to: jpg) {
          try? FileManager.default.removeItem(at: jpg)
          try? FileManager.default.removeItem(at: file)
          done(.failure(e))
          return
        }
        try? FileManager.default.removeItem(at: file)
        url = jpg
        uti = UTType.jpeg.identifier
        converted = true
      }
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      var next = files
      next.append([
        "role": role, "path": url.path, "resourceName": resource.originalFilename,
        "uti": uti, "size": size, "converted": converted,
      ])
      self.exportParts(parts, index: index + 1, files: next, done: done)
    }
  }

  private func write(_ resource: PHAssetResource, to url: URL, done: @escaping (ExportError?) -> Void) {
    if isCancelled {
      done(ExportError(code: "cancelled"))
      return
    }
    try? FileManager.default.removeItem(at: url)
    guard FileManager.default.createFile(atPath: url.path, contents: nil),
      let handle = try? FileHandle(forWritingTo: url)
    else {
      done(ExportError(code: "io"))
      return
    }
    let options = PHAssetResourceRequestOptions()
    options.isNetworkAccessAllowed = true
    options.progressHandler = { [weak self] fraction in
      guard let self else { return }
      // Progress is only reported while downloading from iCloud.
      self.state.lock()
      self.downloadSeen = true
      self.state.unlock()
      self.kickWatchdog()
      self.progress(fraction)
    }
    var writeError: Error?
    let finishOnce = OnceFlag()
    startWatchdog()
    let id = PHAssetResourceManager.default().requestData(
      for: resource, options: options,
      dataReceivedHandler: { [weak self] data in
        guard writeError == nil else { return }
        self?.kickWatchdog()
        do {
          try handle.write(contentsOf: data)
        } catch {
          writeError = error
          self?.cancel()
        }
      },
      completionHandler: { [weak self] error in
        guard let self, finishOnce.take() else { return }
        self.stopWatchdog()
        var failure: ExportError?
        if let writeError {
          failure = ExportError(code: Self.code(for: writeError))
        } else if self.isCancelled {
          failure = ExportError(code: self.stalled ? "icloud" : "cancelled")
        } else if let error {
          failure = ExportError(code: self.sawDownload ? "icloud" : Self.code(for: error))
        }
        do {
          if failure == nil { try handle.synchronize() }
          try handle.close()
        } catch {
          failure = failure ?? ExportError(code: Self.code(for: error))
        }
        done(failure)
      })
    state.lock()
    request = id
    state.unlock()
  }

  // MARK: iCloud stall watchdog

  private var sawDownload: Bool {
    state.lock()
    defer { state.unlock() }
    return downloadSeen
  }

  private var stalled: Bool {
    state.lock()
    defer { state.unlock() }
    return stallSeen
  }

  private func startWatchdog() {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + .seconds(Self.stallSeconds))
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      self.state.lock()
      self.stallSeen = true
      self.state.unlock()
      self.cancel()
    }
    state.lock()
    watchdog = timer
    state.unlock()
    timer.resume()
  }

  private func kickWatchdog() {
    state.lock()
    watchdog?.schedule(deadline: .now() + .seconds(Self.stallSeconds))
    state.unlock()
  }

  private func stopWatchdog() {
    state.lock()
    watchdog?.cancel()
    watchdog = nil
    state.unlock()
  }

  // MARK: HEIC to JPEG

  private static func isHeif(_ uti: String) -> Bool {
    guard let t = UTType(uti) else { return false }
    return t.conforms(to: .heic) || t.conforms(to: .heif)
  }

  /// Re-encodes at quality 0.92. ImageIO copies the metadata (EXIF date,
  /// GPS, orientation) and the color profile; an HDR gain map is lost.
  private static func convertToJpeg(from: URL, to: URL) -> ExportError? {
    return autoreleasepool {
      guard let src = CGImageSourceCreateWithURL(from as CFURL, nil),
        let dest = CGImageDestinationCreateWithURL(to as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
      else { return ExportError(code: "io") }
      let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92]
      CGImageDestinationAddImageFromSource(dest, src, 0, props as CFDictionary)
      if !CGImageDestinationFinalize(dest) {
        return ExportError(code: Self.freeBytes(at: to) < 64 * 1024 * 1024 ? "no_space" : "io")
      }
      return nil
    }
  }

  private static func freeBytes(at url: URL) -> Int64 {
    let values = try? url.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return values?.volumeAvailableCapacityForImportantUsage ?? Int64.max
  }

  static func code(for error: Error) -> String {
    let e = error as NSError
    if e.domain == NSCocoaErrorDomain && e.code == NSFileWriteOutOfSpaceError { return "no_space" }
    if e.domain == NSPOSIXErrorDomain && (e.code == Int(ENOSPC) || e.code == Int(EDQUOT)) { return "no_space" }
    if e.domain == NSURLErrorDomain || e.domain.contains("Cloud") { return "icloud" }
    if e.domain == PHPhotosErrorDomain && e.code == PHPhotosError.Code.networkAccessRequired.rawValue {
      return "icloud"
    }
    return "io"
  }
}

/// Lets exactly one caller through.
final class OnceFlag {
  private let lock = NSLock()
  private var used = false
  func take() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if used { return false }
    used = true
    return true
  }
}
