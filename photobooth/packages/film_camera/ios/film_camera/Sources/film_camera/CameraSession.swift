import AVFoundation
import CoreImage
import ImageIO
import Flutter
import UIKit

/// Owns the AVCaptureSession, the preview texture and the Live segment writer.
final class CameraSession: NSObject, FlutterTexture, AVCaptureVideoDataOutputSampleBufferDelegate,
  AVCaptureAudioDataOutputSampleBufferDelegate
{
  private let textures: FlutterTextureRegistry
  private let emit: ([String: Any]) -> Void
  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "film_camera.session")
  /// Video and audio samples arrive on the same serial queue so the segment
  /// writer never needs locking.
  private let dataQueue = DispatchQueue(label: "film_camera.data")
  private let videoOutput = AVCaptureVideoDataOutput()
  private let audioOutput = AVCaptureAudioDataOutput()
  private let photoOutput = AVCapturePhotoOutput()
  private var videoInput: AVCaptureDeviceInput?
  private var audioInput: AVCaptureDeviceInput?
  private var textureId: Int64 = 0
  private var latestBuffer: CVPixelBuffer?
  private let bufferLock = NSLock()
  private var photoDelegates: [Int64: PhotoDelegate] = [:]
  private var writer: SegmentWriter?
  /// Display zoom of the ultra-wide lens at its own factor 1 ("0.5×").
  private static let ultraZoom: CGFloat = 0.5
  /// Back ultra-wide lens, switched to only while the zoom is below 1×.
  private var ultraDevice: AVCaptureDevice?
  private var front = false
  /// Photobooth iPad: frames are landscape, rotated so the horizon stays level for the camera in use (the
  /// front camera of an iPad Pro M4 sits on the long edge). Lensly itself is always portrait.
  private var landscape = false
  /// iOS 17 AVCaptureDevice.RotationCoordinator for [landscape] (typed AnyObject for older iOS).
  private var rotationCoordinator: AnyObject?
  private var rotationObservation: NSKeyValueObservation?
  /// Last landscape angle seen (0 or 180); kept while the iPad lies flat or is briefly held upright.
  private var landscapeAngle: CGFloat = 0
  /// A landscape frame arrived although the connections should rotate to portrait: re-orient once (data queue flag).
  private var reorientPending = false
  /// At most a few self-heals per session (a device that cannot rotate would otherwise reconfigure every frame).
  private var reorientTries = 0
  private var observers: [NSObjectProtocol] = []

  init(textures: FlutterTextureRegistry, emit: @escaping ([String: Any]) -> Void) {
    self.textures = textures
    self.emit = emit
    super.init()
    textureId = textures.register(self)
    // Coming back from Settings after granting the camera, or after an interruption, the video connection can start
    // in the sensor's landscape orientation (owner 2026-10-21: preview sideways after deny -> allow in Settings).
    let nc = NotificationCenter.default
    for name in [Notification.Name.AVCaptureSessionDidStartRunning, .AVCaptureSessionInterruptionEnded] {
      observers.append(nc.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
        self?.sessionQueue.async { self?.reorient() }
      })
    }
  }

  deinit { observers.forEach(NotificationCenter.default.removeObserver) }

  /// [orientConnections] inside its own configuration (safe while running).
  private func reorient() {
    session.beginConfiguration()
    orientConnections()
    session.commitConfiguration()
  }

  // MARK: clock

  static func hostNowUs() -> Int64 {
    Int64(CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock())) * 1_000_000)
  }

  /// Now, expressed on the clock sample buffers are stamped with.
  func nowUs() -> Int64 {
    let host = CMClockGetTime(CMClockGetHostTimeClock())
    if #available(iOS 15.4, *), let clock = session.synchronizationClock {
      return Int64(CMTimeGetSeconds(CMSyncConvertTime(host, from: CMClockGetHostTimeClock(), to: clock)) * 1_000_000)
    }
    return Int64(CMTimeGetSeconds(host) * 1_000_000)
  }

  // MARK: lifecycle

  func open(front: Bool, landscape: Bool = false, completion: @escaping (Result<[String: Any], Error>) -> Void) {
    sessionQueue.async {
      do {
        self.landscape = landscape
        try self.configure(front: front)
        if !self.session.isRunning { self.session.startRunning() }
        // The connections exist for sure once the configuration is committed and the session runs.
        self.reorient()
        let dims = self.videoDims()
        DispatchQueue.main.async {
          completion(.success([
            "textureId": self.textureId, "width": dims.0, "height": dims.1, "rotation": 0,
          ]))
        }
      } catch {
        DispatchQueue.main.async { completion(.failure(error)) }
      }
    }
  }

  /// The plain wide lens, front or back. The multi-lens virtual camera (triple / dual-wide) kept every lens
  /// streaming so it could switch over smoothly, which heated the phone (owner 2026-10-16, iPhone 15 Pro Max):
  /// the back camera now runs one lens and swaps to the ultra-wide only for 0.5× ([setZoom]).
  private static func pickDevice(front: Bool) -> AVCaptureDevice? {
    AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back)
      ?? AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: front ? .front : .back
      ).devices.first
  }

  // MARK: zoom ("1×" = the wide lens, "0.5×" = the ultra-wide)

  private var onUltra: Bool { videoInput?.device.deviceType == .builtInUltraWideCamera }

  /// Display zoom of the device's current factor.
  private func displayZoom(_ d: AVCaptureDevice) -> Double {
    Double(onUltra ? d.videoZoomFactor * Self.ultraZoom : d.videoZoomFactor)
  }

  func zoomRange() -> [String: Double] {
    guard let d = videoInput?.device else { return ["min": 1, "max": 1, "zoom": 1] }
    let maxWide = onUltra ? 10 : Double(min(d.maxAvailableVideoZoomFactor, 10))
    return [
      "min": ultraDevice != nil ? Double(Self.ultraZoom) : Double(d.minAvailableVideoZoomFactor),
      "max": maxWide,
      "zoom": displayZoom(d),
    ]
  }

  func setZoom(_ zoom: Double, completion: @escaping (Double) -> Void) {
    sessionQueue.async {
      let wantUltra = !self.front && self.ultraDevice != nil && CGFloat(zoom) < 1
      if wantUltra != self.onUltra {
        let next = wantUltra ? self.ultraDevice : Self.pickDevice(front: false)
        if let next = next, let input = try? AVCaptureDeviceInput(device: next) {
          self.session.beginConfiguration()
          if let old = self.videoInput { self.session.removeInput(old) }
          if self.session.canAddInput(input) {
            self.session.addInput(input)
            self.videoInput = input
          } else if let old = self.videoInput, self.session.canAddInput(old) {
            self.session.addInput(old)
          }
          self.orientConnections()
          self.session.commitConfiguration()
        }
      }
      guard let d = self.videoInput?.device, (try? d.lockForConfiguration()) != nil else {
        DispatchQueue.main.async { completion(1) }
        return
      }
      let factor = self.onUltra ? CGFloat(zoom) / Self.ultraZoom : CGFloat(zoom)
      d.videoZoomFactor = min(max(factor, d.minAvailableVideoZoomFactor), d.maxAvailableVideoZoomFactor)
      d.unlockForConfiguration()
      let applied = self.displayZoom(d)
      DispatchQueue.main.async { completion(applied) }
    }
  }

  private func videoDims() -> (Int, Int) {
    // Frames are rotated to portrait (landscape for the photobooth) by the connection.
    guard let f = videoInput?.device.activeFormat else { return landscape ? (1920, 1080) : (1080, 1920) }
    let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
    let short = Int(min(d.width, d.height)), long = Int(max(d.width, d.height))
    return landscape ? (long, short) : (short, long)
  }

  private func configure(front: Bool) throws {
    // iPad front cameras: Center Stage follows faces with a digital zoom (a softer, cropped picture).
    // The app takes control and keeps it off; the booth frames the guests itself.
    if front, #available(iOS 14.5, *) {
      AVCaptureDevice.centerStageControlMode = .app
      AVCaptureDevice.isCenterStageEnabled = false
    }
    session.beginConfiguration()
    defer { session.commitConfiguration() }
    session.sessionPreset = .high

    if let old = videoInput { session.removeInput(old) }
    guard let device = Self.pickDevice(front: front)
    else { throw NSError(domain: "film_camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "no camera"]) }
    let input = try AVCaptureDeviceInput(device: device)
    if session.canAddInput(input) { session.addInput(input) }
    videoInput = input
    self.front = front
    watchRotation(device)
    ultraDevice = front ? nil : AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)

    // Live clips are video only: no microphone input is ever added.

    if !session.outputs.contains(videoOutput) {
      videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
      videoOutput.alwaysDiscardsLateVideoFrames = true
      videoOutput.setSampleBufferDelegate(self, queue: dataQueue)
      if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
    }
    if audioInput != nil, !session.outputs.contains(audioOutput) {
      audioOutput.setSampleBufferDelegate(self, queue: dataQueue)
      if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
    }
    if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
      session.addOutput(photoOutput)
    }
    // Stills at the format's biggest size (2304 × 1296 on the iPad Pro M4 front camera, not 1920 × 1080), with iOS's
    // multi-frame noise reduction ("balanced"): the photobooth's front camera looked soft before.
    photoOutput.maxPhotoQualityPrioritization = .balanced
    if #available(iOS 16.0, *) {
      let sizes = device.activeFormat.supportedMaxPhotoDimensions
      if let biggest = sizes.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
        photoOutput.maxPhotoDimensions = biggest
      }
    }

    orientConnections()
  }

  /// Landscape only: follows the device's rotation coordinator and re-orients when the angle changes.
  private func watchRotation(_ device: AVCaptureDevice) {
    rotationObservation = nil
    rotationCoordinator = nil
    guard landscape, #available(iOS 17.0, *) else { return }
    let rc = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
    rotationCoordinator = rc
    rotationObservation = rc.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] _, _ in
      self?.sessionQueue.async { self?.reorient() }
    }
  }

  /// Rotation for the video and photo connections: 90 (portrait) for Lensly, 0 / 180 for the photobooth.
  private func wantedAngle() -> CGFloat {
    guard landscape else { return 90 }
    if #available(iOS 17.0, *), let rc = rotationCoordinator as? AVCaptureDevice.RotationCoordinator {
      let a = rc.videoRotationAngleForHorizonLevelCapture
      // Only level landscape angles count: flat on a table or held upright keeps the last one.
      if a == 0 || a == 180 { landscapeAngle = a }
    }
    return landscapeAngle
  }

  /// Portrait, never mirrored (preview mirroring is done in Flutter). Connections are rebuilt whenever the
  /// input changes (lens swap), so this runs after every input change.
  private func orientConnections() {
    for conn in [videoOutput.connection(with: .video), photoOutput.connection(with: .video)] {
      guard let c = conn else { continue }
      if #available(iOS 17.0, *) {
        let angle = wantedAngle()
        if c.isVideoRotationAngleSupported(angle) { c.videoRotationAngle = angle }
      } else if c.isVideoOrientationSupported {
        c.videoOrientation = landscape ? .landscapeRight : .portrait
      }
      if c.isVideoMirroringSupported {
        c.automaticallyAdjustsVideoMirroring = false
        c.isVideoMirrored = false
      }
    }
  }

  func close() {
    dataQueue.sync {
      writer?.finish { _ in }
      writer = nil
    }
    sessionQueue.sync {
      if session.isRunning { session.stopRunning() }
    }
    textures.unregisterTexture(textureId)
    bufferLock.lock()
    latestBuffer = nil
    bufferLock.unlock()
  }

  // MARK: FlutterTexture

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    bufferLock.lock()
    defer { bufferLock.unlock() }
    guard let b = latestBuffer else { return nil }
    return Unmanaged.passRetained(b)
  }

  // MARK: samples

  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
  ) {
    if output === videoOutput {
      if let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
        // Frames must be portrait (taller than wide), or landscape for the photobooth. Anything else means the
        // rotation was lost: fix it once.
        if (CVPixelBufferGetWidth(pb) > CVPixelBufferGetHeight(pb)) != landscape {
          if !reorientPending && reorientTries < 3 {
            reorientPending = true
            reorientTries += 1
            sessionQueue.async { [weak self] in
              self?.reorient()
              self?.dataQueue.async { self?.reorientPending = false }
            }
          }
        }
        bufferLock.lock()
        latestBuffer = pb
        bufferLock.unlock()
        textures.textureFrameAvailable(textureId)
      }
      writer?.appendVideo(sampleBuffer)
    } else if output === audioOutput {
      writer?.appendAudio(sampleBuffer)
    }
  }

  // MARK: Live segments

  func startSegments(dir: String, segmentMs: Int, audio: Bool) {
    dataQueue.async {
      self.writer?.finish { _ in }
      let dims = self.videoDims()
      self.writer = SegmentWriter(
        dir: dir, segmentUs: Int64(segmentMs) * 1000, audio: false,
        sourceSize: CGSize(width: dims.0, height: dims.1)
      ) { [weak self] info in
        self?.emit(["type": "segment", "path": info.path, "startUs": info.startUs, "endUs": info.endUs])
      }
    }
  }

  func stopSegments(done: @escaping () -> Void) {
    dataQueue.async {
      guard let w = self.writer else { return DispatchQueue.main.async(execute: done) }
      self.writer = nil
      w.finish { _ in DispatchQueue.main.async(execute: done) }
    }
  }

  func flushSegment(completion: @escaping ([String: Any]?) -> Void) {
    dataQueue.async {
      guard let w = self.writer else { return DispatchQueue.main.async { completion(nil) } }
      w.rotateNow { info in
        DispatchQueue.main.async {
          completion(info.map { ["path": $0.path, "startUs": $0.startUs, "endUs": $0.endUs] })
        }
      }
    }
  }

  // MARK: stills

  private static let ciContext = CIContext(options: [.cacheIntermediates: false])

  /// A light unsharp mask (front camera only): eyes, hair and clothes crisper. Skin smoothing runs
  /// after this in Dart, so faces stay soft. Nil when Core Image fails (the plain JPEG is used).
  private static func sharpened(_ image: UIImage, quality: CGFloat) -> Data? {
    guard let ci = CIImage(image: image), let filter = CIFilter(name: "CIUnsharpMask") else { return nil }
    filter.setValue(ci, forKey: kCIInputImageKey)
    filter.setValue(1.6, forKey: kCIInputRadiusKey)
    filter.setValue(0.55, forKey: kCIInputIntensityKey)
    guard let out = filter.outputImage?.cropped(to: ci.extent),
      let space = CGColorSpace(name: CGColorSpace.sRGB)
    else { return nil }
    return ciContext.jpegRepresentation(
      of: out, colorSpace: space,
      options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality])
  }


  func takePicture(outPath: String, flash: Bool, completion: @escaping (Result<[String: Any], Error>) -> Void) {
    let shutterUs = nowUs()
    let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
    if flash, photoOutput.supportedFlashModes.contains(.on) { settings.flashMode = .on }
    settings.photoQualityPrioritization = .balanced
    if #available(iOS 16.0, *) { settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions }
    let sharpen = front
    let id = settings.uniqueID
    let delegate = PhotoDelegate { [weak self] data, error in
      self?.photoDelegates[id] = nil
      guard let data = data else {
        return completion(.failure(error ?? NSError(domain: "film_camera", code: 2)))
      }
      DispatchQueue.global(qos: .userInitiated).async {
        // Bake EXIF orientation into pixels and cap the size.
        guard let img = UIImage(data: data) else {
          return DispatchQueue.main.async { completion(.failure(NSError(domain: "film_camera", code: 3))) }
        }
        let maxSide: CGFloat = 2400
        let scale = min(1, maxSide / max(img.size.width, img.size.height))
        let size = CGSize(width: floor(img.size.width * scale), height: floor(img.size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
          img.draw(in: CGRect(origin: .zero, size: size))
        }
        do {
          let jpeg = (sharpen ? Self.sharpened(upright, quality: 0.95) : nil)
            ?? upright.jpegData(compressionQuality: 0.95)!
          try jpeg.write(to: URL(fileURLWithPath: outPath))
          DispatchQueue.main.async {
            completion(.success([
              "path": outPath, "width": Int(size.width), "height": Int(size.height), "shutterUs": shutterUs,
            ]))
          }
        } catch {
          DispatchQueue.main.async { completion(.failure(error)) }
        }
      }
    }
    photoDelegates[id] = delegate
    sessionQueue.async {
      // No live video connection (interrupted by a call, not running yet):
      // capturePhoto would raise NSInvalidArgumentException.
      guard let c = self.photoOutput.connection(with: .video), c.isActive, c.isEnabled else {
        return delegate.fail(NSError(domain: "film_camera", code: 4))
      }
      self.photoOutput.capturePhoto(with: settings, delegate: delegate)
    }
  }
}

/// Answers exactly once: with the photo, or with an error when the capture
/// is aborted (only didFinishCaptureFor fires then, and Dart waited forever).
private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
  private let done: (Data?, Error?) -> Void
  private var fired = false
  init(done: @escaping (Data?, Error?) -> Void) { self.done = done }

  private func finish(_ data: Data?, _ error: Error?) {
    DispatchQueue.main.async {
      guard !self.fired else { return }
      self.fired = true
      self.done(data, error)
    }
  }

  func fail(_ error: Error) { finish(nil, error) }

  func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
    finish(photo.fileDataRepresentation(), error)
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?
  ) {
    finish(nil, error ?? NSError(domain: "film_camera", code: 5))
  }
}
