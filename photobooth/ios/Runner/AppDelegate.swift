import Flutter
import UIKit

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
  }
}

/// AirPrint without any dialog (lib/services/printer.dart): the printer is picked once with
/// UIPrinterPickerController, then every job goes straight to UIPrinter(url:).
final class BoothPrinter: NSObject, FlutterPlugin, UIPrintInteractionControllerDelegate {
  /// 100 × 148 mm postcard in points.
  private static let postcard = CGSize(width: 283.5, height: 419.5)

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
      printFile(url: args["url"] as? String ?? "", path: args["path"] as? String ?? "", result: result)
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
  private func printFile(url: String, path: String, result: @escaping FlutterResult) {
    guard let printerUrl = URL(string: url) else { return result("Địa chỉ máy in không hợp lệ") }
    let info = UIPrintInfo.printInfo()
    info.outputType = .photo
    info.orientation = .portrait
    info.jobName = "Photobooth"
    let controller = UIPrintInteractionController.shared
    controller.printInfo = info
    controller.printingItem = URL(fileURLWithPath: path)
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
    UIPrintPaper.bestPaper(forPageSize: Self.postcard, withPapersFrom: paperList)
  }

  private static func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    var vc = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? scene?.windows.first?.rootViewController
    while let presented = vc?.presentedViewController { vc = presented }
    return vc
  }
}
