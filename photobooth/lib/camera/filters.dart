import 'dart:math' as math;
import 'dart:typed_data';

import 'package:film_camera/film_camera.dart' show FilmLook, LutData;

// Copied from Lensly lib/camera/film_stock.dart: the recipe, gradeColor and the
// LUT helpers are unchanged; only the six bright / pink stocks are kept.

/// Colour recipe for one filter. The 3D LUT is generated from these numbers so
/// the still shader and the native clip export share one source of truth.
class FilmRecipe {
  const FilmRecipe({
    this.temperature = 0,
    this.tint = 0,
    this.saturation = 1,
    this.contrast = 1,
    this.fade = 0,
    this.shadowTint = const [0, 0, 0],
    this.highlightTint = const [0, 0, 0],
    this.mono = false,
    this.grain = 0.25,
    this.grainSize = 1.6,
    this.halation = 0,
    this.vignette = 0.35,
    this.leak = 0.12,
    this.channelMix,
    this.exposure = 0,
  });

  /// Brightness push before the curve (+0.1 ≈ a third of a stop brighter).
  final double exposure;

  /// Optional 3×3 row-major channel mixer applied first.
  final List<double>? channelMix;

  /// + warm / − cool (shifts R up, B down).
  final double temperature;

  /// + green / − magenta.
  final double tint;
  final double saturation;
  final double contrast;

  /// Lifts the blacks (matte, faded print).
  final double fade;
  final List<double> shadowTint;
  final List<double> highlightTint;
  final bool mono;

  final double grain;
  final double grainSize;
  final double halation;
  final double vignette;
  final double leak;
}

/// The six filters guests pick from (Lensly names in brackets).
enum BoothFilter {
  airy(
    'Trong veo',
    FilmRecipe(
      exposure: 0.12,
      temperature: -0.01,
      saturation: 0.92,
      contrast: 0.86,
      fade: 0.08,
      grain: 0.1,
      vignette: 0.1,
      leak: 0.05,
    ),
  ),
  softMorning(
    'Nắng sớm',
    FilmRecipe(
      exposure: 0.07,
      temperature: 0.04,
      saturation: 0.85,
      contrast: 0.86,
      fade: 0.08,
      highlightTint: [0.04, 0.03, 0.01],
      grain: 0.1,
      vignette: 0.12,
      leak: 0.2,
    ),
  ),
  peachy(
    'Hồng đào',
    FilmRecipe(
      exposure: 0.05,
      temperature: 0.05,
      tint: -0.04,
      saturation: 0.92,
      contrast: 0.92,
      fade: 0.06,
      highlightTint: [0.05, 0.01, 0.02],
      grain: 0.1,
      vignette: 0.12,
    ),
  ),
  pinkDream(
    'Hồng mơ',
    FilmRecipe(
      temperature: 0.03,
      tint: -0.06,
      saturation: 0.95,
      contrast: 0.94,
      fade: 0.08,
      shadowTint: [0.03, 0.0, 0.03],
      highlightTint: [0.05, 0.02, 0.03],
      grain: 0.16,
    ),
  ),
  sakuraPink(
    'Hồng anh đào',
    FilmRecipe(
      exposure: 0.04,
      temperature: 0.02,
      tint: 0.06,
      saturation: 1.02,
      contrast: 0.96,
      fade: 0.08,
      shadowTint: [0.02, 0.0, 0.03],
      highlightTint: [0.06, 0.02, 0.04],
      grain: 0.12,
      halation: 0.2,
    ),
  ),
  softGlow(
    'Mờ mộng',
    FilmRecipe(
      exposure: 0.08,
      temperature: 0.03,
      saturation: 0.9,
      contrast: 0.86,
      fade: 0.1,
      highlightTint: [0.04, 0.03, 0.02],
      grain: 0.12,
      halation: 0.5,
      vignette: 0.16,
    ),
  );

  const BoothFilter(this.label, this.recipe);

  final String label;
  final FilmRecipe recipe;

  /// Grain / vignette / halation / light leak for the native clip export. [seed]: the one the
  /// still was developed with ([seedFor]), so the leak lands on the same edge.
  FilmLook look({double seed = 0}) => FilmLook(
    grain: recipe.grain,
    grainSize: recipe.grainSize,
    vignette: recipe.vignette,
    halation: recipe.halation,
    leak: recipe.leak,
    seed: seed,
  );
}

/// Default LUT resolution. 17 is plenty for these soft curves.
const int kLutSize = 17;

/// LUT resolution for the clip export (Core Image's colour cube): a power of two, which every
/// iOS version takes. A cube it refuses leaves the clip in plain camera colours.
const int kClipLutSize = 32;

double _smooth(double x) => x * x * (3 - 2 * x);

/// Applies [r] to one colour (all 0..1). Pure function.
List<double> gradeColor(FilmRecipe r, double red, double green, double blue) {
  var c = [red, green, blue];
  final mix = r.channelMix;
  if (mix != null) {
    c = [for (var row = 0; row < 3; row++) mix[row * 3] * red + mix[row * 3 + 1] * green + mix[row * 3 + 2] * blue];
  }
  if (r.exposure != 0) c = [for (final v in c) v * (1 + r.exposure)];
  // White balance.
  c[0] += r.temperature * 0.5;
  c[2] -= r.temperature * 0.5;
  c[1] += r.tint * 0.5;
  // Contrast around mid grey, blended with an S-curve for a filmic toe.
  for (var i = 0; i < 3; i++) {
    final v = c[i].clamp(0.0, 1.0);
    final linear = (v - 0.5) * r.contrast + 0.5;
    final s = _smooth(v);
    c[i] = linear * 0.7 + s * 0.3 * r.contrast + (1 - r.contrast) * 0.15;
  }
  // Saturation.
  final l = 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2];
  final sat = r.mono ? 0.0 : r.saturation;
  for (var i = 0; i < 3; i++) {
    c[i] = l + (c[i] - l) * sat;
  }
  // Split toning.
  final lum = l.clamp(0.0, 1.0);
  for (var i = 0; i < 3; i++) {
    c[i] += r.shadowTint[i] * (1 - lum) + r.highlightTint[i] * lum;
  }
  // Fade: lift blacks, roll off whites.
  for (var i = 0; i < 3; i++) {
    c[i] = r.fade + c[i].clamp(0.0, 1.0) * (1 - r.fade * 1.6);
    c[i] = c[i].clamp(0.0, 1.0);
  }
  return c;
}

/// size³ RGB entries, red fastest.
LutData buildLut(BoothFilter filter, {int size = kLutSize}) {
  final out = Float32List(size * size * size * 3);
  var k = 0;
  for (var b = 0; b < size; b++) {
    for (var g = 0; g < size; g++) {
      for (var r = 0; r < size; r++) {
        final c = gradeColor(filter.recipe, r / (size - 1), g / (size - 1), b / (size - 1));
        out[k++] = c[0];
        out[k++] = c[1];
        out[k++] = c[2];
      }
    }
  }
  return LutData(size: size, rgb: out);
}

/// LUT as RGBA8 pixels for the shader strip: width size², height size,
/// pixel (r + b·size, g).
Uint8List lutStripPixels(LutData lut) {
  final n = lut.size;
  final px = Uint8List(n * n * n * 4);
  for (var b = 0; b < n; b++) {
    for (var g = 0; g < n; g++) {
      for (var r = 0; r < n; r++) {
        final src = (r + g * n + b * n * n) * 3;
        final x = r + b * n;
        final dst = (g * n * n + x) * 4;
        for (var i = 0; i < 3; i++) {
          px[dst + i] = (lut.rgb[src + i].clamp(0.0, 1.0) * 255).round();
        }
        px[dst + 3] = 255;
      }
    }
  }
  return px;
}

/// Seed for grain/leak, varied per photo but stable for re-export.
double seedFor(String id) => (id.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0xFFFFF) % 997) / 97.0 + math.e;
