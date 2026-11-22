import Flutter
import Photos
import UniformTypeIdentifiers

/// Platform channel `crossdrop/photos` (Dart side: lib/platform/ios_photos.dart).
///
/// Adds received photos and videos to the Photos library, moving the file
/// rather than copying it (D-043). Uses add-only access: CrossDrop never
/// needs to read the library to save into it.
///
/// - `requestAddOnly` -> `authorized` | `limited` | `denied` | `restricted`.
///   Shows the system prompt only the first time.
/// - `save {path, kind, name, createdMs?}` -> the new asset's local
///   identifier. The file is gone afterwards (moved into the library).
///   Errors: `permission`, `unsupported` (Photos refused the file; it is
///   still at `path`), `no_space`, `io`.
///
/// Saves that arrive while one is running are grouped into the next
/// `performChanges`, up to [maxBatch] (D-072): Photos takes changes one at
/// a time, and one change per photo made it the limit when receiving
/// hundreds. A group Photos refuses is saved again one by one, so a bad
/// file fails alone.
final class PhotosSaveChannel {
  private let channel: FlutterMethodChannel
  private let lock = NSLock()
  private var pending: [PendingSave] = []
  private var saving = false
  private static let maxBatch = 20

  private struct PendingSave {
    let url: URL
    let video: Bool
    let name: String?
    let created: Date?
    let done: (Result<String, ExportError>) -> Void
  }

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "crossdrop/photos", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "requestAddOnly":
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        DispatchQueue.main.async { result(Self.name(status)) }
      }
    case "save":
      guard let path = args["path"] as? String, let kind = args["kind"] as? String else {
        result(FlutterError(code: "bad_args", message: nil, details: nil))
        return
      }
      let created = (args["createdMs"] as? NSNumber).map {
        Date(timeIntervalSince1970: $0.doubleValue / 1000)
      }
      save(
        url: URL(fileURLWithPath: path), video: kind == "video",
        name: args["name"] as? String, created: created
      ) { outcome in
        DispatchQueue.main.async {
          switch outcome {
          case .success(let id): result(id)
          case .failure(let e): result(FlutterError(code: e.code, message: nil, details: nil))
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func save(
    url: URL, video: Bool, name: String?, created: Date?,
    done: @escaping (Result<String, ExportError>) -> Void
  ) {
    switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
    case .denied, .restricted:
      done(.failure(ExportError(code: "permission")))
      return
    default:
      break
    }
    lock.lock()
    pending.append(PendingSave(url: url, video: video, name: name, created: created, done: done))
    let start = !saving
    saving = true
    lock.unlock()
    if start { flush() }
  }

  /// Saves what is waiting, a group at a time, until nothing is.
  private func flush() {
    lock.lock()
    let batch = Array(pending.prefix(Self.maxBatch))
    pending.removeFirst(batch.count)
    if batch.isEmpty { saving = false }
    lock.unlock()
    if batch.isEmpty { return }
    perform(batch) { [weak self] in self?.flush() }
  }

  private func perform(_ batch: [PendingSave], then next: @escaping () -> Void) {
    var placeholders: [PHObjectPlaceholder?] = []
    PHPhotoLibrary.shared().performChanges({
      placeholders = batch.map(Self.creationRequest)
    }) { [weak self] success, error in
      if success {
        for (item, placeholder) in zip(batch, placeholders) {
          if let id = placeholder?.localIdentifier {
            item.done(.success(id))
          } else {
            item.done(.failure(ExportError(code: "unsupported")))
          }
        }
        next()
      } else if batch.count == 1 {
        batch[0].done(.failure(ExportError(code: Self.code(for: error))))
        next()
      } else if let self {
        // One refused file fails the whole change: try each alone.
        self.performEach(batch[...], then: next)
      } else {
        for item in batch { item.done(.failure(ExportError(code: Self.code(for: error)))) }
      }
    }
  }

  private func performEach(_ rest: ArraySlice<PendingSave>, then next: @escaping () -> Void) {
    guard let first = rest.first else {
      next()
      return
    }
    perform([first]) { [weak self] in self?.performEach(rest.dropFirst(), then: next) }
  }

  private static func creationRequest(_ item: PendingSave) -> PHObjectPlaceholder? {
    let request = PHAssetCreationRequest.forAsset()
    let options = PHAssetResourceCreationOptions()
    // Move, not copy: a 4 GB video must not need 8 GB.
    options.shouldMoveFile = true
    if let name = item.name {
      options.originalFilename = name
      // Do not let Photos guess the type.
      let ext = (name as NSString).pathExtension
      if let type = UTType(filenameExtension: ext) {
        options.uniformTypeIdentifier = type.identifier
      }
    }
    request.addResource(with: item.video ? .video : .photo, fileURL: item.url, options: options)
    if let created = item.created { request.creationDate = created }
    return request.placeholderForCreatedAsset
  }

  private static func code(for error: Error?) -> String {
    guard let e = error as NSError? else { return "unsupported" }
    if e.domain == PHPhotosErrorDomain {
      switch PHPhotosError.Code(rawValue: e.code) {
      case .accessUserDenied, .accessRestricted: return "permission"
      case .notEnoughSpace: return "no_space"
      default: break
      }
    }
    if e.domain == NSCocoaErrorDomain && e.code == NSFileWriteOutOfSpaceError { return "no_space" }
    // Anything else (invalid or unsupported resource, "operation could
    // not be completed"): Files will take it.
    return "unsupported"
  }

  private static func name(_ status: PHAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "authorized"
    case .limited: return "limited"
    case .denied: return "denied"
    case .restricted: return "restricted"
    default: return "notDetermined"
    }
  }
}
