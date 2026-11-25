import CoreImage

/// Film texture for exported video, mirroring shaders/film.frag:
/// halation before the LUT, then light leak, vignette and grain after it.
struct FilmLook {
  let grain: Double
  let grainSize: Double
  let vignette: Double
  let halation: Double
  let leak: Double
  let seed: Double

  init(args: [String: Any]) {
    let m = args["look"] as? [String: Any] ?? [:]
    grain = (m["grain"] as? NSNumber)?.doubleValue ?? 0
    grainSize = (m["grainSize"] as? NSNumber)?.doubleValue ?? 1.5
    vignette = (m["vignette"] as? NSNumber)?.doubleValue ?? 0
    halation = (m["halation"] as? NSNumber)?.doubleValue ?? 0
    leak = (m["leak"] as? NSNumber)?.doubleValue ?? 0
    seed = (m["seed"] as? NSNumber)?.doubleValue ?? 0
  }

  /// The shader's light leak: a warm wash (+0.55, +0.22, +0.05) from one edge, fading out over
  /// 0.75 of the frame (in uv, so an ellipse on a wide frame), added in gamma space like the
  /// shader. [mirrored]: the frame is flipped afterwards, so the edge is flipped here to land where
  /// it is on the (already mirrored) photo.
  func leakWash(_ img: CIImage, extent: CGRect, mirrored: Bool) -> CIImage {
    guard leak > 0, extent.width > 0, extent.height > 0 else { return img }
    func fract(_ v: Double) -> Double { v - v.rounded(.down) }
    var ox = fract(seed * 0.37) < 0.5 ? 0.0 : 1.0
    if mirrored { ox = 1 - ox }
    let oy = fract(seed * 0.71)  // from the top, as uv in the shader
    let unit: CGFloat = 1000
    let wash = CIFilter(name: "CIRadialGradient", parameters: [
      "inputCenter": CIVector(x: CGFloat(ox) * unit, y: CGFloat(1 - oy) * unit),
      "inputRadius0": 0,
      "inputRadius1": 0.75 * unit,
      "inputColor0": CIColor(red: CGFloat(0.55 * leak), green: CGFloat(0.22 * leak), blue: CGFloat(0.05 * leak), alpha: 1),
      "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 1),
    ])!.outputImage!
      .cropped(to: CGRect(x: 0, y: 0, width: unit, height: unit))
      .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY)
        .scaledBy(x: extent.width / unit, y: extent.height / unit))
    return wash
      // Linear dodge = plain addition of colour over an opaque frame, alpha stays 1.
      .applyingFilter("CILinearDodgeBlendMode", parameters: [
        kCIInputBackgroundImageKey: img.applyingFilter("CILinearToSRGBToneCurve"),
      ])
      .applyingFilter("CISRGBToneCurveToLinear")
      .cropped(to: extent)
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
