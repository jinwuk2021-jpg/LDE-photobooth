import AVFoundation
import Flutter
import Photos
import UIKit

public class FilmCameraPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let textures: FlutterTextureRegistry
  private var session: CameraSession?
  private var eventSink: FlutterEventSink?
  private var thermalObserver: NSObjectProtocol?

  init(textures: FlutterTextureRegistry) {
    self.textures = textures
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FilmCameraPlugin(textures: registrar.textures())
    let channel = FlutterMethodChannel(name: "film_camera", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    let events = FlutterEventChannel(name: "film_camera/events", binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
  }

  // MARK: events

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    thermalObserver = NotificationCenter.default.addObserver(
      forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.emit(["type": "thermal", "state": FilmCameraPlugin.thermalName()])
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    if let o = thermalObserver { NotificationCenter.default.removeObserver(o) }
    thermalObserver = nil
    return nil
  }

  func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { self.eventSink?(event) }
  }

  static func thermalName() -> String {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: return "nominal"
    case .fair: return "fair"
    case .serious: return "serious"
    case .critical: return "critical"
    @unknown default: return "nominal"
    }
  }

  // MARK: methods

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "requestPermissions":
      requestPermissions(microphone: args["microphone"] as? Bool ?? false, result: result)
    case "open":
      let front = (args["lens"] as? String) == "front"
      if session == nil {
        session = CameraSession(textures: textures) { [weak self] e in self?.emit(e) }
      }
      session!.open(front: front, landscape: args["landscape"] as? Bool ?? false) { res in
        switch res {
        case .success(let info): result(info)
        case .failure(let err): result(FlutterError(code: "open", message: err.localizedDescription, details: nil))
        }
      }
    case "zoomRange":
      result(session?.zoomRange() ?? ["min": 1.0, "max": 1.0, "zoom": 1.0])
    case "setZoom":
      guard let s = session else { return result(1.0) }
      s.setZoom(args["zoom"] as? Double ?? 1) { result($0) }
    case "close":
      session?.close()
      session = nil
      result(nil)
    case "takePicture":
      guard let s = session else { return result(FlutterError(code: "closed", message: nil, details: nil)) }
      s.takePicture(outPath: args["outPath"] as! String, flash: (args["flash"] as? String) == "on") { res in
        switch res {
        case .success(let info): result(info)
        case .failure(let err): result(FlutterError(code: "capture", message: err.localizedDescription, details: nil))
        }
      }
    case "nowUs":
      result(session?.nowUs() ?? CameraSession.hostNowUs())
    case "startSegments":
      guard let s = session else { return result(FlutterError(code: "closed", message: nil, details: nil)) }
      s.startSegments(
        dir: args["dir"] as! String,
        segmentMs: args["segmentMs"] as? Int ?? 1000,
        audio: args["audio"] as? Bool ?? true)
      result(nil)
    case "stopSegments":
      if let s = session { s.stopSegments { result(nil) } } else { result(nil) }
    case "flushSegment":
      guard let s = session else { return result(nil) }
      s.flushSegment { info in result(info) }
    case "exportVideo":
      ClipExporter.export(args: args) { res in
        switch res {
        case .success(let path): result(path)
        case .failure(let err): result(FlutterError(code: "export", message: err.localizedDescription, details: nil))
        }
      }
    case "encodeJpeg":
      encodeJpeg(args: args, result: result)
    case "detectFaces":
      let path = args["path"] as? String ?? ""
      DispatchQueue.global(qos: .userInitiated).async {
        let faces = FaceFinder.detect(path: path)
        DispatchQueue.main.async { result(faces) }
      }
    case "openAppSettings":
      // The way out after a denied permission: the app's page in Settings.
      guard let url = URL(string: UIApplication.openSettingsURLString) else { return result(false) }
      UIApplication.shared.open(url) { ok in result(ok) }
    case "libraryAccess":
      LibrarySaver.access(request: args["request"] as? Bool ?? false, result: result)
    case "requestAlbumAccess":
      LibrarySaver.requestAlbumAccess(result: result)
    case "saveToLibrary":
      LibrarySaver.save(
        path: args["path"] as! String,
        isVideo: args["isVideo"] as? Bool ?? false,
        album: args["album"] as? String ?? "Lensly",
        result: result)
    case "excludeFromBackup":
      // Re-downloadable folders (packs, shop cache, exports) stay out of the
      // iCloud backup (iOS Data Storage Guidelines, QA-009).
      for path in args["paths"] as? [String] ?? [] {
        var url = URL(fileURLWithPath: path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
      }
      result(true)
    case "thermalState":
      result(FilmCameraPlugin.thermalName())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestPermissions(microphone: Bool, result: @escaping FlutterResult) {
    AVCaptureDevice.requestAccess(for: .video) { cam in
      guard microphone else {
        DispatchQueue.main.async { result(["camera": cam, "microphone": false]) }
        return
      }
      AVCaptureDevice.requestAccess(for: .audio) { mic in
        DispatchQueue.main.async { result(["camera": cam, "microphone": mic]) }
      }
    }
  }

  private func encodeJpeg(args: [String: Any], result: @escaping FlutterResult) {
    guard let data = args["rgba"] as? FlutterStandardTypedData,
      let w = args["width"] as? Int, let h = args["height"] as? Int,
      let out = args["outPath"] as? String
    else { return result(FlutterError(code: "args", message: nil, details: nil)) }
    let quality = CGFloat(args["quality"] as? Int ?? 92) / 100
    DispatchQueue.global(qos: .userInitiated).async {
      let provider = CGDataProvider(data: data.data as CFData)!
      let cg = CGImage(
        width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
      guard let image = cg, let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: quality) else {
        DispatchQueue.main.async { result(FlutterError(code: "encode", message: nil, details: nil)) }
        return
      }
      do {
        try jpeg.write(to: URL(fileURLWithPath: out), options: .atomic)
        DispatchQueue.main.async { result(out) }
      } catch {
        DispatchQueue.main.async { result(FlutterError(code: "write", message: error.localizedDescription, details: nil)) }
      }
    }
  }
}
