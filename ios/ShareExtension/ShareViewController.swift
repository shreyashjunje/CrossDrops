import UIKit
import UniformTypeIdentifiers

/// CrossDrop's Share Extension (D-045).
///
/// Extensions have a tight memory limit (about 120 MB), so this one never
/// loads a file into memory and never sends anything. It clones each
/// shared file into the App Group inbox, writes a manifest last, and opens
/// the main app, which does the transfer. If the app cannot be opened
/// from here, the files wait in the inbox until CrossDrop is opened.
///
/// Inbox layout: `<group>/Inbox/<uuid>/<n>/<name>` plus
/// `<group>/Inbox/<uuid>/manifest.json`:
/// `{"v":1, "items":[{"file":"0/IMG_1.HEIC", "name":"IMG_1.HEIC",
///   "uti":"public.heic", "kind":"photo"}], "failed":0}`.
final class ShareViewController: UIViewController {
  private let label = UILabel()
  private let progress = UIProgressView(progressViewStyle: .default)
  private let button = UIButton(type: .system)
  private var cancelled = false
  private var finished = false
  private var started = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    label.text = "Preparing files for CrossDrop…"
    label.numberOfLines = 0
    label.textAlignment = .center
    button.setTitle("Cancel", for: .normal)
    button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
    let stack = UIStackView(arrangedSubviews: [label, progress, button])
    stack.axis = .vertical
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !started else { return }
    started = true
    collect()
  }

  @objc private func tapped() {
    if finished {
      extensionContext?.completeRequest(returningItems: nil)
    } else {
      cancelled = true
      extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
  }

  private func show(_ text: String, done: Bool) {
    DispatchQueue.main.async {
      self.label.text = text
      if done {
        self.finished = true
        self.progress.isHidden = true
        self.button.setTitle("Done", for: .normal)
      }
    }
  }

  private func collect() {
    guard let groupId = Bundle.main.object(forInfoDictionaryKey: "CrossDropAppGroup") as? String,
      let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId)
    else {
      show(
        "Sharing to CrossDrop is not available in this installation. Open CrossDrop and use Send instead.",
        done: true)
      return
    }
    let id = UUID().uuidString
    let dir = group.appendingPathComponent("Inbox", isDirectory: true).appendingPathComponent(id, isDirectory: true)
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      .flatMap { $0.attachments ?? [] }
    if providers.isEmpty {
      show("Nothing to send.", done: true)
      return
    }
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
      show("Could not prepare the files: not enough space?", done: true)
      return
    }

    var items: [[String: Any]?] = Array(repeating: nil, count: providers.count)
    var failed = 0
    var textOnly = 0
    let lock = NSLock()
    let groupWait = DispatchGroup()
    var completed = 0
    for (n, provider) in providers.enumerated() {
      guard let (type, kind) = Self.pickType(provider) else {
        lock.lock()
        textOnly += 1
        lock.unlock()
        continue
      }
      groupWait.enter()
      let slot = dir.appendingPathComponent("\(n)", isDirectory: true)
      Self.copy(provider, type: type, into: slot) { name in
        lock.lock()
        if let name {
          items[n] = ["file": "\(n)/\(name)", "name": name, "uti": type.identifier, "kind": kind]
        } else {
          failed += 1
        }
        completed += 1
        let fraction = Float(completed) / Float(providers.count)
        lock.unlock()
        DispatchQueue.main.async { self.progress.setProgress(fraction, animated: true) }
        groupWait.leave()
      }
    }
    groupWait.notify(queue: .main) {
      if self.cancelled {
        try? FileManager.default.removeItem(at: dir)
        return
      }
      let list = items.compactMap { $0 }
      if list.isEmpty {
        try? FileManager.default.removeItem(at: dir)
        self.show(
          textOnly > 0 && failed == 0
            ? "CrossDrop sends files. Share a photo, video or file instead."
            : "These items could not be read.",
          done: true)
        return
      }
      let manifest: [String: Any] = ["v": 1, "items": list, "failed": failed + textOnly]
      do {
        let data = try JSONSerialization.data(withJSONObject: manifest)
        // Written last and atomically: the app only takes complete shares.
        try data.write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
      } catch {
        try? FileManager.default.removeItem(at: dir)
        self.show("Could not prepare the files: not enough space?", done: true)
        return
      }
      if self.openApp(URL(string: "crossdrop://share?id=\(id)")!) {
        self.extensionContext?.completeRequest(returningItems: nil)
      } else {
        let n = list.count
        self.show(
          "\(n) \(n == 1 ? "file is" : "files are") ready. Open CrossDrop to choose the phone to send to.",
          done: true)
      }
    }
  }

  /// The type to load: a movie or image in its own format (HEIC stays
  /// HEIC), else any file. Plain text and web links are not files.
  private static func pickType(_ p: NSItemProvider) -> (UTType, String)? {
    let types = p.registeredTypeIdentifiers.compactMap(UTType.init)
    if let t = types.first(where: { $0.conforms(to: .movie) }) { return (t, "video") }
    if let t = types.first(where: { $0.conforms(to: .image) && $0 != .image }) { return (t, "photo") }
    if types.contains(.image) { return (.image, "photo") }
    if let t = types.first(where: {
      ($0.conforms(to: .data) || $0.conforms(to: .package)) && !$0.conforms(to: .text) && !$0.conforms(to: .url)
    }) {
      return (t, "file")
    }
    if types.contains(.fileURL) { return (.item, "file") }
    return nil
  }

  /// Clones the provider's file into [slot]. Calls back with the saved
  /// name, or nil.
  private static func copy(
    _ p: NSItemProvider, type: UTType, into slot: URL, done: @escaping (String?) -> Void
  ) {
    p.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
      // The file at url is deleted when this closure returns.
      if let url {
        let name = safeName(url.lastPathComponent, fallback: p.suggestedName, type: type)
        do {
          try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
          try FileManager.default.copyItem(at: url, to: slot.appendingPathComponent(name))
          done(name)
        } catch {
          done(nil)
        }
        return
      }
      // Some apps offer images only as data (a Markup screenshot). Small,
      // so loading it is fine.
      guard type.conforms(to: .image) else {
        done(nil)
        return
      }
      _ = p.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
        guard let data, data.count < 64 * 1024 * 1024 else {
          done(nil)
          return
        }
        let name = safeName(nil, fallback: p.suggestedName, type: type)
        do {
          try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
          try data.write(to: slot.appendingPathComponent(name))
          done(name)
        } catch {
          done(nil)
        }
      }
    }
  }

  /// A file name without folders, with an extension for its type.
  private static func safeName(_ name: String?, fallback: String?, type: UTType) -> String {
    var base = (name ?? fallback ?? "").components(separatedBy: "/").last ?? ""
    base = base.trimmingCharacters(in: .whitespacesAndNewlines)
    if base.isEmpty || base.hasPrefix(".") { base = "file" }
    if (base as NSString).pathExtension.isEmpty, let ext = type.preferredFilenameExtension {
      base += ".\(ext)"
    }
    return String(base.prefix(200))
  }

  /// Share extensions may not open URLs officially. The responder chain
  /// reaches the host UIApplication, whose open method works (iOS 15 to
  /// 18). False if not found; the files then wait for the next launch.
  private func openApp(_ url: URL) -> Bool {
    let selector = NSSelectorFromString("openURL:options:completionHandler:")
    var responder: UIResponder? = self
    while let r = responder {
      if let app = r as? UIApplication, app.responds(to: selector) {
        typealias Open = @convention(c) (
          AnyObject, Selector, URL, [UIApplication.OpenExternalURLOptionsKey: Any], ((Bool) -> Void)?
        ) -> Void
        let open = unsafeBitCast(app.method(for: selector), to: Open.self)
        open(app, selector, url, [:], nil)
        return true
      }
      responder = r.next
    }
    return false
  }
}
