import AVFoundation
import CoreImage
import Flutter

/// Stitches segment slices into one 480p MP4 (light enough to share by QR)
/// with the film look applied.
enum ClipExporter {
  static let flashUs: Double = 0.12

  static func export(args: [String: Any], completion: @escaping (Result<String, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let (comp, boundaries, path) = try build(args: args)
        exportSession(comp: comp, boundaries: boundaries, path: path, args: args, completion: completion)
      } catch {
        DispatchQueue.main.async { completion(.failure(error)) }
      }
    }
  }

  private static func build(args: [String: Any]) throws -> (AVMutableComposition, [CMTime], String) {
    guard let clips = args["clips"] as? [[[String: Any]]], let out = args["outPath"] as? String else {
      throw NSError(domain: "film_camera", code: 10, userInfo: [NSLocalizedDescriptionKey: "bad args"])
    }
    let comp = AVMutableComposition()
    guard let vTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else { throw NSError(domain: "film_camera", code: 11) }
    var cursor = CMTime.zero
    var boundaries: [CMTime] = []
    for clip in clips {
      for part in clip {
        let asset = AVURLAsset(url: URL(fileURLWithPath: part["path"] as! String))
        let start = CMTime(value: (part["inUs"] as! NSNumber).int64Value, timescale: 1_000_000)
        let end = CMTime(value: (part["outUs"] as! NSNumber).int64Value, timescale: 1_000_000)
        guard let src = asset.tracks(withMediaType: .video).first else { continue }
        let range = CMTimeRange(start: start, end: min(end, src.timeRange.end))
        guard range.duration > .zero else { continue }
        // Live clips are silent: only the video track is used.
        try vTrack.insertTimeRange(range, of: src, at: cursor)
        cursor = cursor + range.duration
      }
      boundaries.append(cursor)
    }
    guard cursor > .zero else { throw NSError(domain: "film_camera", code: 12, userInfo: [NSLocalizedDescriptionKey: "empty clip"]) }
    try? FileManager.default.removeItem(atPath: out)
    return (comp, Array(boundaries.dropLast()), out)
  }

  private static func lutFilter(args: [String: Any]) -> CIFilter? {
    guard let size = args["lutSize"] as? Int, let lut = args["lut"] as? FlutterStandardTypedData else { return nil }
    let rgb = lut.data.withUnsafeBytes { Array($0.bindMemory(to: Float32.self)) }
    // A short table would index out of range (a trap); export without LUT.
    guard size > 0, rgb.count >= size * size * size * 3 else { return nil }
    var rgba = [Float32](repeating: 1, count: size * size * size * 4)
    for i in 0..<(size * size * size) {
      rgba[i * 4] = rgb[i * 3]
      rgba[i * 4 + 1] = rgb[i * 3 + 1]
      rgba[i * 4 + 2] = rgb[i * 3 + 2]
    }
    let f = CIFilter(name: "CIColorCubeWithColorSpace")
    f?.setValue(size, forKey: "inputCubeDimension")
    f?.setValue(Data(bytes: rgba, count: rgba.count * 4), forKey: "inputCubeData")
    f?.setValue(CGColorSpace(name: CGColorSpace.sRGB), forKey: "inputColorSpace")
    return f
  }

  private static func exportSession(
    comp: AVMutableComposition, boundaries: [CMTime], path: String, args: [String: Any],
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    let flash = args["flashBetween"] as? Bool ?? false
    let mirror = args["mirror"] as? Bool ?? false
    let lut = lutFilter(args: args)
    let look = FilmLook(args: args)
    let lock = NSLock()
    // Set once the cube fails (frames are rendered off the main thread; guarded by [lock]).
    final class Flag { var on = false }
    let lutFailed = Flag()
    // Output: short side 480 px.
    let natural = AVMutableVideoComposition(propertiesOf: comp).renderSize
    let shortSide = min(natural.width, natural.height)
    let outScale: CGFloat = shortSide > 480 ? 480 / shortSide : 1
    let vc = AVMutableVideoComposition(asset: comp) { request in
      let extent = request.sourceImage.extent
      var img = look.halate(request.sourceImage, extent: extent)
      lock.lock()
      if let f = lut {
        f.setValue(img, forKey: kCIInputImageKey)
        if let out = f.outputImage {
          img = out
        } else if !lutFailed.on {
          // The clip goes out in plain camera colours: say so once instead of failing silently.
          lutFailed.on = true
          NSLog("film_camera: colour cube gave no output, clip exported without the filter")
        }
      }
      lock.unlock()
      img = look.leakWash(img, extent: extent, mirrored: mirror)
      img = look.finish(img, extent: extent, time: request.compositionTime.seconds)
      if mirror {
        img = img.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -extent.width, y: 0))
      }
      if flash {
        let t = request.compositionTime.seconds
        let k = boundaries.map { max(0, 1 - abs(t - $0.seconds) / flashUs) }.max() ?? 0
        if k > 0 {
          let white = CIImage(color: CIColor(red: 1, green: 0.98, blue: 0.94, alpha: CGFloat(k))).cropped(to: extent)
          img = white.composited(over: img)
        }
      }
      let out = img.cropped(to: extent).transformed(by: CGAffineTransform(scaleX: outScale, y: outScale))
      request.finish(with: out.cropped(to: CGRect(origin: out.extent.origin, size: request.renderSize)), context: nil)
    }
    vc.renderSize = CGSize(
      width: (vc.renderSize.width * outScale / 2).rounded() * 2, height: (vc.renderSize.height * outScale / 2).rounded() * 2)
    guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPreset960x540) else {
      return DispatchQueue.main.async { completion(.failure(NSError(domain: "film_camera", code: 13))) }
    }
    export.videoComposition = vc
    export.outputURL = URL(fileURLWithPath: path)
    export.outputFileType = .mp4
    export.shouldOptimizeForNetworkUse = true
    export.exportAsynchronously {
      DispatchQueue.main.async {
        if export.status == .completed {
          completion(.success(path))
        } else {
          completion(.failure(export.error ?? NSError(domain: "film_camera", code: 14)))
        }
      }
    }
  }
}
