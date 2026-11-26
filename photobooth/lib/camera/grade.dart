import 'dart:convert';
import 'dart:math' as math;

/// The staff's colour grade (Cài đặt → Màu ảnh), set before the event and applied to every
/// photo and Live clip taken afterwards, under the guest's filter. Guests never see it.
///
/// The colour part is baked into the filters' 3D LUTs (still shader and clip export alike), so a
/// grade costs nothing per photo. [vignette] adds to the filter's own; [corner] rounds the photo
/// windows on the print.
class PhotoGrade {
  const PhotoGrade({
    this.exposure = 0,
    this.brightness = 0,
    this.contrast = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.temperature = 0,
    this.tint = 0,
    this.saturation = 0,
    this.vibrance = 0,
    this.vignette = 0,
    this.corner = 0,
  });

  /// All in −1 … +1 (sliders show −100 … +100), except [vignette] 0 … 1 and [corner] 0 … [maxCorner].
  final double exposure;
  final double brightness;
  final double contrast;
  final double highlights;
  final double shadows;

  /// + warm (amber) / − cool (blue).
  final double temperature;

  /// + magenta (pink) / − green.
  final double tint;
  final double saturation;

  /// Saturation that spares colours already strong (and skin): muted colours gain most.
  final double vibrance;
  final double vignette;

  /// Photo window corner radius on the print, in card pixels (1200 × 1776 card).
  final double corner;

  static const none = PhotoGrade();
  static const double maxCorner = 80;

  bool get isNeutral => colourNeutral && vignette == 0 && corner == 0;

  /// No change to the colours (the LUTs stay the filters' own).
  bool get colourNeutral =>
      exposure == 0 &&
      brightness == 0 &&
      contrast == 0 &&
      highlights == 0 &&
      shadows == 0 &&
      temperature == 0 &&
      tint == 0 &&
      saturation == 0 &&
      vibrance == 0;

  PhotoGrade copyWith({
    double? exposure,
    double? brightness,
    double? contrast,
    double? highlights,
    double? shadows,
    double? temperature,
    double? tint,
    double? saturation,
    double? vibrance,
    double? vignette,
    double? corner,
  }) => PhotoGrade(
    exposure: exposure ?? this.exposure,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    highlights: highlights ?? this.highlights,
    shadows: shadows ?? this.shadows,
    temperature: temperature ?? this.temperature,
    tint: tint ?? this.tint,
    saturation: saturation ?? this.saturation,
    vibrance: vibrance ?? this.vibrance,
    vignette: vignette ?? this.vignette,
    corner: corner ?? this.corner,
  );

  Map<String, double> toJson() => {
    'exposure': exposure,
    'brightness': brightness,
    'contrast': contrast,
    'highlights': highlights,
    'shadows': shadows,
    'temperature': temperature,
    'tint': tint,
    'saturation': saturation,
    'vibrance': vibrance,
    'vignette': vignette,
    'corner': corner,
  };

  static PhotoGrade fromJson(Map<String, Object?> j) {
    double v(String k, [double lo = -1, double hi = 1]) => ((j[k] as num?)?.toDouble() ?? 0).clamp(lo, hi);
    return PhotoGrade(
      exposure: v('exposure'),
      brightness: v('brightness'),
      contrast: v('contrast'),
      highlights: v('highlights'),
      shadows: v('shadows'),
      temperature: v('temperature'),
      tint: v('tint'),
      saturation: v('saturation'),
      vibrance: v('vibrance'),
      vignette: v('vignette', 0, 1),
      corner: v('corner', 0, maxCorner),
    );
  }

  String encode() => jsonEncode(toJson());

  static PhotoGrade decode(String? s) {
    if (s == null) return none;
    try {
      return fromJson((jsonDecode(s) as Map).cast<String, Object?>());
    } catch (_) {
      return none;
    }
  }

  @override
  bool operator ==(Object other) => other is PhotoGrade && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;

  /// The grade on one colour (0 … 1 each), before the filter. Pure function.
  List<double> apply(double r, double g, double b) {
    var c = [r, g, b];
    // Exposure: ±1 stop.
    if (exposure != 0) {
      final k = math.pow(2, exposure).toDouble();
      c = [for (final v in c) v * k];
    }
    // White balance (multiplicative: black stays black).
    if (temperature != 0) {
      c[0] *= 1 + temperature * 0.14;
      c[1] *= 1 + temperature * 0.03;
      c[2] *= 1 - temperature * 0.16;
    }
    if (tint != 0) {
      c[0] *= 1 + tint * 0.05;
      c[1] *= 1 - tint * 0.1;
      c[2] *= 1 + tint * 0.05;
    }
    c = [for (final v in c) v.clamp(0.0, 1.0)];
    // Brightness: lifts / lowers the mid-tones, black and white stay put.
    if (brightness != 0) {
      final gamma = math.pow(2, -brightness * 0.9).toDouble();
      c = [for (final v in c) math.pow(v, gamma).toDouble()];
    }
    // Contrast around mid grey.
    if (contrast != 0) {
      final k = 1 + contrast * (contrast > 0 ? 0.6 : 0.5);
      c = [for (final v in c) (v - 0.5) * k + 0.5];
    }
    // Highlights / shadows: shift the bright / dark tones only.
    if (highlights != 0 || shadows != 0) {
      final l = _luma(c).clamp(0.0, 1.0);
      final hw = _smoothstep(0.45, 1.0, l);
      final sw = 1 - _smoothstep(0.0, 0.55, l);
      final d = highlights * 0.22 * hw + shadows * 0.22 * sw;
      c = [for (final v in c) v + d];
    }
    c = [for (final v in c) v.clamp(0.0, 1.0)];
    // Saturation, then vibrance (weighted by how grey the colour still is).
    if (saturation != 0 || vibrance != 0) {
      final l = _luma(c);
      final mx = c.reduce(math.max), mn = c.reduce(math.min);
      final amount = (1 + saturation) * (1 + vibrance * (1 - (mx - mn)) * (vibrance > 0 ? 0.9 : 1));
      c = [for (final v in c) l + (v - l) * amount];
    }
    return [for (final v in c) v.clamp(0.0, 1.0)];
  }

  static double _luma(List<double> c) => 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2];

  static double _smoothstep(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}
