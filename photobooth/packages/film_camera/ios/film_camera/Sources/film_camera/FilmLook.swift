import CoreImage

/// Film texture for exported video, mirroring shaders/film.frag:
/// halation before the LUT, vignette and grain after it.
struct FilmLook {
  let grain: Double
  let grainSize: Double
  let vignette: Double
  let halation: Double

  init(args: [String: Any]) {
    let m = args["look"] as? [String: Any] ?? [:]
    grain = (m["grain"] as? NSNumber)?.doubleValue ?? 0
    grainSize = (m["grainSize"] as? NSNumber)?.doubleValue ?? 1.5
    vignette = (m["vignette"] as? NSNumber)?.doubleValue ?? 0
    halation = (m["halation"] as? NSNumber)?.doubleValue ?? 0
  }

  /// Red-orange bloom bleeding from bright light sources.
  func halate(_ img: CIImage, extent: CGRect) -> CIImage {
    guard halation > 0 else { return img }
    let radius = max(extent.width, extent.height) * 0.012
    let glow = img
      // Keep only the highlights (> ~0.78), like the preview shader.
      .applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
        "inputBiasVector": CIVector(x: -0.78, y: -0.78, z: -0.78, w: 0),
      ])
      .applyingFilter("CIColorClamp")
      .clampedToExtent()
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius * 2])
      .cropped(to: extent)
      // Tint red-orange and scale by strength (×3.2 as in the shader).
      .applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: 0.299 * 3.2 * halation, y: 0.587 * 3.2 * halation, z: 0.114 * 3.2 * halation, w: 0),
        "inputGVector": CIVector(x: 0.299 * 1.0 * halation, y: 0.587 * 1.0 * halation, z: 0.114 * 1.0 * halation, w: 0),
        "inputBVector": CIVector(x: 0.299 * 0.4 * halation, y: 0.587 * 0.4 * halation, z: 0.114 * 0.4 * halation, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
      ])
    return glow.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: img])
  }

  func finish(_ img: CIImage, extent: CGRect, time: Double) -> CIImage {
    var out = img
    if vignette > 0 {
      out = out.applyingFilter("CIVignette", parameters: [
        kCIInputIntensityKey: vignette * 1.6,
        kCIInputRadiusKey: 1.6,
      ])
    }
    if grain > 0 {
      // Fresh noise every frame (offset by time), scaled to the grain size,
      // soft-light blended so it is strongest in the mid-tones.
      let shift = CGFloat((time * 7919).truncatingRemainder(dividingBy: 512))
      let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
        .transformed(by: CGAffineTransform(translationX: shift, y: shift * 0.618))
        .transformed(by: CGAffineTransform(scaleX: CGFloat(grainSize), y: CGFloat(grainSize)))
        .applyingFilter("CIColorMatrix", parameters: [
          "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
          "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(min(1, grain * 0.9))),
        ])
        .cropped(to: extent)
      out = noise.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: out])
    }
    return out.cropped(to: extent)
  }
}
