import Flutter
import ImageCaptureCore
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // A booth never locks its screen.
    application.isIdleTimerDisabled = true
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BoothPrinter") {
      BoothPrinter.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BoothFiles") {
      BoothFiles.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BoothPtp") {
      BoothPtp.register(with: registrar)
    }
  }
}

/// AirPrint without any dialog (lib/services/printer.dart): the printer is picked once with
/// UIPrinterPickerController, then every job goes straight to UIPrinter(url:).
final class BoothPrinter: NSObject, FlutterPlugin, UIPrintInteractionControllerDelegate {
  /// 100 × 148 mm postcard in points (the SELPHY's paper; used when Dart sends no size).
  private static let postcard = CGSize(width: 283.5, height: 419.5)

  /// Paper asked for by the current job (Settings → Khổ giấy), portrait, in points.
  private var paperSize = BoothPrinter.postcard

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "booth/printer", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(BoothPrinter(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "pick":
      pick(result)
    case "print":
      // Paper in mm from Dart ("paperW", "paperH"), e.g. 127 × 178 for 2L.
      if let w = (args["paperW"] as? NSNumber)?.doubleValue, let h = (args["paperH"] as? NSNumber)?.doubleValue,
        w > 0, h > 0
      {
        paperSize = CGSize(width: min(w, h) * 72 / 25.4, height: max(w, h) * 72 / 25.4)
      } else {
        paperSize = Self.postcard
      }
      printFile(
        url: args["url"] as? String ?? "", path: args["path"] as? String ?? "", fill: args["fill"] as? Bool ?? true,
        result: result)
    case "reachable":
      guard let url = URL(string: args["url"] as? String ?? "") else { return result(false) }
      UIPrinter(url: url).contactPrinter { ok in result(ok) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// → ["url", "name"], or nil when cancelled.
  private func pick(_ result: @escaping FlutterResult) {
    guard let view = Self.topViewController()?.view else { return result(nil) }
    let picker = UIPrinterPickerController(initiallySelectedPrinter: nil)
    let anchor = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
    picker.present(from: anchor, in: view, animated: true) { controller, selected, _ in
      guard selected, let printer = controller.selectedPrinter else { return result(nil) }
      result(["url": printer.url.absoluteString, "name": printer.displayName])
    }
  }

  /// → nil when the job was handed to the printer, else an error message (Vietnamese, shown in admin).
  /// [fill]: the picture covers the whole sheet (borderless; the printer trims its edge),
  /// else it fits inside the printable area (a white border where the printer needs one).
  private func printFile(url: String, path: String, fill: Bool, result: @escaping FlutterResult) {
    guard let printerUrl = URL(string: url) else { return result("Địa chỉ máy in không hợp lệ") }
    guard let image = UIImage(contentsOfFile: path) else { return result("Không đọc được file ảnh in") }
    let info = UIPrintInfo.printInfo()
    info.outputType = .photo
    info.orientation = .portrait
    info.jobName = "Photobooth"
    let controller = UIPrintInteractionController.shared
    controller.printInfo = info
    // We draw the page ourselves so iOS never adds its own scaling or margins.
    controller.printingItem = nil
    controller.printPageRenderer = PhotoPageRenderer(image: image, fill: fill)
    controller.delegate = self
    controller.print(to: UIPrinter(url: printerUrl)) { _, completed, error in
      if let error = error {
        result(error.localizedDescription)
      } else if !completed {
        result("Máy in không nhận lệnh (tắt / mất kết nối?)")
      } else {
        result(nil)
      }
    }
  }

  func printInteractionController(
    _ printInteractionController: UIPrintInteractionController, choosePaper paperList: [UIPrintPaper]
  ) -> UIPrintPaper {
    UIPrintPaper.bestPaper(forPageSize: paperSize, withPapersFrom: paperList)
  }

  static func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    var vc = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? scene?.windows.first?.rootViewController
    while let presented = vc?.presentedViewController { vc = presented }
    return vc
  }
}

/// One page: the whole card on the sheet, whatever paper the printer reports.
/// - Turned a quarter when the sheet and the card point different ways (a printer may report 2L
///   as 178 × 127, i.e. landscape: filling that with a portrait card blew it up ~2× and cut it).
/// - [fill] (borderless) covers the sheet only when the sheet has the card's shape (within 3 %,
///   e.g. postcard on the SELPHY), where just the bleed is trimmed. Any other paper (2L, L) gets
///   the card fitted inside the printable area, centred, so nothing is cut off.
final class PhotoPageRenderer: UIPrintPageRenderer {
  private let image: UIImage
  private let fill: Bool

  init(image: UIImage, fill: Bool) {
    self.image = image
    self.fill = fill
    super.init()
  }

  override var numberOfPages: Int { 1 }

  override func drawPage(at pageIndex: Int, in printableRect: CGRect) {
    let size = image.size
    let sheet = paperRect
    guard size.width > 0, size.height > 0, sheet.width > 0, sheet.height > 0,
      let ctx = UIGraphicsGetCurrentContext()
    else { return }
    // The card as it lands on the sheet: turned when the two point different ways.
    let turn = (sheet.width > sheet.height) != (size.width > size.height)
    let cardW = turn ? size.height : size.width, cardH = turn ? size.width : size.height
    let sameShape = abs((sheet.width / sheet.height) / (cardW / cardH) - 1) < 0.03
    let useFill = fill && sameShape
    let target = useFill ? sheet : printableRect
    guard target.width > 0, target.height > 0 else { return }
    let scale = useFill
      ? max(target.width / cardW, target.height / cardH)
      : min(target.width / cardW, target.height / cardH)
    let w = size.width * scale, h = size.height * scale
    ctx.saveGState()
    ctx.translateBy(x: target.midX, y: target.midY)
    if turn { ctx.rotate(by: .pi / 2) }
    image.draw(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
    ctx.restoreGState()
  }
}


/// A camera on the USB-C port (Sony a6300 in "PC Remote"), as a plain PTP pipe: finds it with
/// ImageCaptureCore, opens the session and passes raw PTP commands through. The Sony protocol
/// itself is in Dart (lib/camera/sony_camera.dart), where it is unit tested.
///
/// Channel "booth/ptp": start → authorization status; send {code, params, out?} →
/// {code, params, data}. Events "booth/ptp/events": added / opened / removed / event.
final class BoothPtp: NSObject, FlutterPlugin, FlutterStreamHandler, ICDeviceBrowserDelegate,
  ICCameraDeviceDelegate
{
  private let browser = ICDeviceBrowser()
  private var camera: ICCameraDevice?
  private var sink: FlutterEventSink?
  private var transaction: UInt32 = 0
  private var started = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = BoothPtp()
    let channel = FlutterMethodChannel(name: "booth/ptp", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    FlutterEventChannel(name: "booth/ptp/events", binaryMessenger: registrar.messenger())
      .setStreamHandler(instance)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    // A camera already plugged in before Dart listened.
    if let cam = camera { emitAdded(cam) }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { self.sink?(event) }
  }

  private func emitAdded(_ cam: ICCameraDevice) {
    emit([
      "event": "added", "name": cam.name ?? "", "vendor": Int(cam.usbVendorID),
      "product": Int(cam.usbProductID), "open": cam.hasOpenSession,
    ])
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "start": start(result)
    case "send": send(args, result)
    case "reopen":
      guard let cam = camera else { return result(false) }
      if cam.hasOpenSession { cam.requestCloseSession() }
      cam.requestOpenSession()
      result(true)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func start(_ result: @escaping FlutterResult) {
    if started { return result("started") }
    started = true
    browser.delegate = self
    if #available(iOS 15.2, *),
      let mask = ICDeviceTypeMask(rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue)
    {
      browser.browsedDeviceTypeMask = mask
    }
    // Control (PTP commands) and contents (files) both need the user's OK once.
    browser.requestContentsAuthorization { contents in
      self.browser.requestControlAuthorization { control in
        DispatchQueue.main.async {
          self.browser.start()
          result("contents=\(contents.rawValue) control=\(control.rawValue)")
        }
      }
    }
  }

  private func send(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let cam = camera, cam.hasOpenSession else {
      return result(FlutterError(code: "closed", message: "Chưa kết nối máy ảnh", details: nil))
    }
    let code = UInt16(truncatingIfNeeded: args["code"] as? Int ?? 0)
    let params = (args["params"] as? [Int] ?? []).map { UInt32(truncatingIfNeeded: $0) }
    let out = (args["out"] as? FlutterStandardTypedData)?.data
    transaction &+= 1
    // PTP command container: length, type 1 (command), code, transaction id, parameters.
    var command = Data()
    func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { command.append(contentsOf: $0) } }
    func put16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { command.append(contentsOf: $0) } }
    put32(UInt32(12 + 4 * params.count))
    put16(1)
    put16(code)
    put32(transaction)
    params.forEach(put32)
    cam.requestSendPTPCommand(command, outData: out) { data, response, error in
      DispatchQueue.main.async {
        if let error = error {
          return result(FlutterError(code: "ptp", message: error.localizedDescription, details: nil))
        }
        // Response container: length, type 3, code, transaction id, parameters.
        let bytes = [UInt8](response)
        func u16(_ o: Int) -> Int { o + 1 < bytes.count ? Int(bytes[o]) | Int(bytes[o + 1]) << 8 : 0 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        var outParams: [Int] = []
        var o = 12
        while o + 3 < bytes.count {
          outParams.append(u32(o))
          o += 4
        }
        result([
          "code": bytes.count >= 8 ? u16(6) : 0, "params": outParams,
          "data": FlutterStandardTypedData(bytes: data),
        ])
      }
    }
  }

  // MARK: ICDeviceBrowserDelegate

  func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
    guard let cam = device as? ICCameraDevice else { return }
    camera = cam
    cam.delegate = self
    cam.ptpEventHandler = { [weak self] data in self?.ptpEvent(data) }
    emitAdded(cam)
    cam.requestOpenSession()
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
    gone(device)
  }

  private func gone(_ device: ICDevice) {
    guard device === camera else { return }
    camera = nil
    emit(["event": "removed"])
  }

  private func ptpEvent(_ data: Data) {
    let b = [UInt8](data)
    guard b.count >= 12 else { return }
    let code = Int(b[6]) | Int(b[7]) << 8
    var params: [Int] = []
    var o = 12
    while o + 3 < b.count {
      params.append(Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24)
      o += 4
    }
    emit(["event": "event", "code": code, "params": params])
  }

  // MARK: ICDeviceDelegate

  func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
    emit(["event": "opened", "error": error?.localizedDescription as Any])
  }

  func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
    emit(["event": "closed"])
  }

  func didRemove(_ device: ICDevice) { gone(device) }

  // MARK: ICCameraDeviceDelegate (files are not used: the photo comes over PTP)

  func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {}
  func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
  func cameraDevice(
    _ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?
  ) {}
  func cameraDevice(
    _ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem,
    error: Error?
  ) {}
  func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
  func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
  func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) { ptpEvent(eventData) }
  func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {}
  func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}
  func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}
}


/// Picks a PNG from the Files app (frame PNGs keep their transparency; the Photos picker may not).
/// Channel "booth/files": pickPng → a copy's path in the temporary folder, or nil when cancelled.
final class BoothFiles: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  private var pending: FlutterResult?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "booth/files", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(BoothFiles(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "pickPng" else { return result(FlutterMethodNotImplemented) }
    guard pending == nil, let top = BoothPrinter.topViewController() else { return result(nil) }
    pending = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.png], asCopy: true)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    top.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else { return finish(nil) }
    let dest = FileManager.default.temporaryDirectory
      .appendingPathComponent("frame-\(Int(Date().timeIntervalSince1970 * 1000))-\(url.lastPathComponent)")
    do {
      try FileManager.default.copyItem(at: url, to: dest)
      finish(dest.path)
    } catch {
      finish(nil)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(nil) }

  private func finish(_ path: String?) {
    pending?(path)
    pending = nil
  }
}
