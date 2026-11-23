import Foundation
import ImageIO
import Vision

/// Faces for skin smoothing, via Apple Vision (built in, no model to ship).
/// Coordinates are normalised to 0..1 of the upright image, y down:
/// `box` [l, t, r, b], `oval` (empty: Vision only gives the jaw line, so the
/// Dart side draws an ellipse from the box), `holes` = eyes, brows, lips.
enum FaceFinder {
  static func detect(path: String) -> [[String: Any]] {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let src = CGImageSourceCreateWithURL(url, nil) else { return [] }
    // Downscale for speed; keep the EXIF orientation so results are upright.
    let thumbOpts: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: 1600,
      kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) else { return [] }
    let request = VNDetectFaceLandmarksRequest()
    let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return []
    }
    var out: [[String: Any]] = []
    for face in request.results ?? [] {
      let b = face.boundingBox  // normalised, origin bottom-left
      let box = [Double(b.minX), Double(1 - b.maxY), Double(b.maxX), Double(1 - b.minY)]
      var holes: [[[Double]]] = []
      if let lm = face.landmarks {
        for region in [lm.leftEye, lm.rightEye, lm.leftEyebrow, lm.rightEyebrow, lm.outerLips] {
          guard let region = region, region.pointCount >= 3 else { continue }
          // Landmark points are normalised to the face box.
          holes.append(region.normalizedPoints.map { p in
            [Double(b.minX + p.x * b.width), Double(1 - (b.minY + p.y * b.height))]
          })
        }
      }
      out.append(["box": box, "oval": [[Double]](), "holes": holes])
    }
    return out
  }
}
