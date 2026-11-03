import Flutter
import Photos

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
final class PhotosSaveChannel {
  private let channel: FlutterMethodChannel

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
    var placeholder: PHObjectPlaceholder?
    PHPhotoLibrary.shared().performChanges({
      let request = PHAssetCreationRequest.forAsset()
      let options = PHAssetResourceCreationOptions()
      // Move, not copy: a 4 GB video must not need 8 GB.
      options.shouldMoveFile = true
      if let name { options.originalFilename = name }
      request.addResource(with: video ? .video : .photo, fileURL: url, options: options)
      if let created { request.creationDate = created }
      placeholder = request.placeholderForCreatedAsset
    }) { success, error in
      if success, let id = placeholder?.localIdentifier {
        done(.success(id))
        return
      }
      done(.failure(ExportError(code: Self.code(for: error))))
    }
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
