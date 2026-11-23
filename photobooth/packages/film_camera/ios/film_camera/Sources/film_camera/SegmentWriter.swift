import AVFoundation

struct SegmentInfo {
  let path: String
  let startUs: Int64
  let endUs: Int64
}

/// Writes the Live stream as a chain of ~1 s MP4 files. Every method must be
/// called on the camera's data queue. Old files are deleted by the Dart
/// `RingBuffer`, which receives each closed segment as an event.
final class SegmentWriter {
  private let dir: String
  private let segmentUs: Int64
  private let audio: Bool
  private let outputSize: CGSize
  private let onClosed: (SegmentInfo) -> Void

  private var writer: AVAssetWriter?
  private var videoIn: AVAssetWriterInput?
  private var audioIn: AVAssetWriterInput?
  private var path = ""
  private var startPts = CMTime.invalid
  private var lastVideoEnd = CMTime.invalid
  private var counter = 0

  init(dir: String, segmentUs: Int64, audio: Bool, sourceSize: CGSize, onClosed: @escaping (SegmentInfo) -> Void) {
    self.dir = dir
    self.segmentUs = segmentUs
    self.audio = audio
    // 720p, keep orientation of the source (portrait).
    let longSide: CGFloat = 1280
    let scale = longSide / max(sourceSize.width, sourceSize.height)
    self.outputSize = CGSize(
      width: (sourceSize.width * scale / 2).rounded() * 2, height: (sourceSize.height * scale / 2).rounded() * 2)
    self.onClosed = onClosed
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
  }

  private func begin(at pts: CMTime) {
    counter += 1
    path = (dir as NSString).appendingPathComponent("seg_\(Int(Date().timeIntervalSince1970 * 1000))_\(counter).mp4")
    guard let w = try? AVAssetWriter(outputURL: URL(fileURLWithPath: path), fileType: .mp4) else { return }
    let v = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: outputSize.width,
        AVVideoHeightKey: outputSize.height,
        AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
        AVVideoCompressionPropertiesKey: [
          AVVideoAverageBitRateKey: 4_000_000,
          AVVideoMaxKeyFrameIntervalKey: 30,
        ],
      ])
    v.expectsMediaDataInRealTime = true
    w.add(v)
    if audio {
      let a = AVAssetWriterInput(
        mediaType: .audio,
        outputSettings: [
          AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 1, AVSampleRateKey: 44_100,
          AVEncoderBitRateKey: 64_000,
        ])
      a.expectsMediaDataInRealTime = true
      if w.canAdd(a) {
        w.add(a)
        audioIn = a
      }
    }
    // A writer that cannot start must never reach startSession: it would
    // raise "Cannot call method when status is 3" and kill the app.
    guard w.startWriting() else {
      try? FileManager.default.removeItem(atPath: path)
      return
    }
    w.startSession(atSourceTime: pts)
    writer = w
    videoIn = v
    startPts = pts
  }

  func appendVideo(_ sb: CMSampleBuffer) {
    let pts = CMSampleBufferGetPresentationTimeStamp(sb)
    // A writer that failed (backgrounded, media services reset, disk full)
    // is dropped; the next frame starts a fresh file.
    if let w = writer, w.status == .failed || w.status == .cancelled {
      try? FileManager.default.removeItem(atPath: path)
      writer = nil
      videoIn = nil
      audioIn = nil
      lastVideoEnd = .invalid
    }
    if writer == nil {
      begin(at: pts)
      // Could not create a writer: no file this frame (and no NaN maths on
      // an invalid start time).
      if writer == nil { return }
    }
    if Self.us(pts - startPts) >= segmentUs {
      close(then: nil)
      begin(at: pts)
    }
    guard let v = videoIn, v.isReadyForMoreMediaData, writer?.status == .writing else { return }
    if v.append(sb) {
      let dur = CMSampleBufferGetDuration(sb)
      lastVideoEnd = pts + (dur.isValid && dur.seconds > 0 ? dur : CMTime(value: 1, timescale: 30))
    }
  }

  func appendAudio(_ sb: CMSampleBuffer) {
    guard writer != nil, let a = audioIn, a.isReadyForMoreMediaData, writer?.status == .writing else { return }
    if CMSampleBufferGetPresentationTimeStamp(sb) < startPts { return }
    a.append(sb)
  }

  /// Closes the current file right now (covering the shutter moment). The next
  /// video frame opens a new one.
  func rotateNow(completion: @escaping (SegmentInfo?) -> Void) {
    guard writer != nil else { return completion(nil) }
    close(then: completion)
  }

  func finish(completion: @escaping (SegmentInfo?) -> Void) {
    guard writer != nil else { return completion(nil) }
    close(then: completion)
  }

  private func close(then completion: ((SegmentInfo?) -> Void)?) {
    guard let w = writer else {
      completion?(nil)
      return
    }
    let info: SegmentInfo? =
      lastVideoEnd.isValid && lastVideoEnd > startPts
      ? SegmentInfo(path: path, startUs: Self.us(startPts), endUs: Self.us(lastVideoEnd)) : nil
    let filePath = path
    writer = nil
    videoIn = nil
    audioIn = nil
    lastVideoEnd = .invalid
    // endSession / finishWriting on a failed writer raise and kill the app.
    guard w.status == .writing else {
      try? FileManager.default.removeItem(atPath: filePath)
      completion?(nil)
      return
    }
    if let end = info.map({ CMTime(value: $0.endUs, timescale: 1_000_000) }) { w.endSession(atSourceTime: end) }
    w.finishWriting { [onClosed] in
      if w.status == .completed, let info = info {
        onClosed(info)
        completion?(info)
      } else {
        try? FileManager.default.removeItem(atPath: filePath)
        completion?(nil)
      }
    }
  }

  static func us(_ t: CMTime) -> Int64 { Int64(CMTimeGetSeconds(t) * 1_000_000) }
}
