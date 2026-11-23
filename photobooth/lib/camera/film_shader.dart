import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'filters.dart';

// From Lensly lib/camera/film_shader.dart: same shader, uniforms and develop
// pass; without the face-shape shader, the live preview filter and riverpod.

/// Loads `shaders/film.frag`, `shaders/skin.frag` and one LUT texture per filter.
class FilmShaders {
  FilmShaders._(this.program, this.luts, this.skin);

  final ui.FragmentProgram program;

  /// shaders/skin.frag (skin smoothing on stills).
  final ui.FragmentProgram skin;
  final Map<BoothFilter, ui.Image> luts;

  static Future<FilmShaders> load() async {
    final program = await ui.FragmentProgram.fromAsset('shaders/film.frag');
    final skin = await ui.FragmentProgram.fromAsset('shaders/skin.frag');
    final luts = <BoothFilter, ui.Image>{};
    for (final f in BoothFilter.values) {
      final lut = buildLut(f);
      final px = lutStripPixels(lut);
      final buffer = await ui.ImmutableBuffer.fromUint8List(px);
      final desc = ui.ImageDescriptor.raw(
        buffer,
        width: lut.size * lut.size,
        height: lut.size,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await desc.instantiateCodec();
      luts[f] = (await codec.getNextFrame()).image;
    }
    return FilmShaders._(program, luts, skin);
  }

  /// Uniform layout (floats): 0,1 uSize · 2 lutSize · 3 grain · 4 grainSize ·
  /// 5 vignette · 6 halation · 7 leak · 8 seed · 9 mono · 10 fast.
  /// Samplers: 0 input, 1 LUT.
  ui.FragmentShader configure(
    BoothFilter filter, {
    required double seed,
    required Size size,
    required ui.Image input,
    double grainScale = 1,
  }) {
    final r = filter.recipe;
    return program.fragmentShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, kLutSize.toDouble())
      ..setFloat(3, r.grain)
      ..setFloat(4, r.grainSize * grainScale)
      ..setFloat(5, r.vignette)
      ..setFloat(6, r.halation)
      ..setFloat(7, r.leak)
      ..setFloat(8, seed)
      ..setFloat(9, r.mono ? 1 : 0)
      ..setFloat(10, 0)
      ..setImageSampler(0, input, filterQuality: FilterQuality.low)
      // Bilinear: a 17³ LUT sampled with nearest filtering bands visibly.
      ..setImageSampler(1, luts[filter]!, filterQuality: FilterQuality.low);
  }

  /// Renders [src] (cropped to [crop]) through the filter at [outSize].
  Future<ui.Image> develop(
    ui.Image src,
    BoothFilter filter, {
    required double seed,
    required Rect crop,
    required Size outSize,
  }) async {
    // 1. crop/scale into an intermediate so the shader samples 0..1 uv.
    final rec1 = ui.PictureRecorder();
    Canvas(rec1).drawImageRect(src, crop, Offset.zero & outSize, Paint()..filterQuality = FilterQuality.high);
    final scaled = await rec1.endRecording().toImage(outSize.width.round(), outSize.height.round());

    // 2. film pass. Grain is specified in preview pixels; scale it up so a
    // large image has the same visible grain as the ~400pt preview.
    final grainScale = (outSize.width / 640).clamp(1.0, 4.0);
    final shader = configure(filter, seed: seed, size: outSize, input: scaled, grainScale: grainScale);
    final rec2 = ui.PictureRecorder();
    Canvas(rec2).drawRect(Offset.zero & outSize, Paint()..shader = shader);
    final out = await rec2.endRecording().toImage(outSize.width.round(), outSize.height.round());
    scaled.dispose();
    shader.dispose();
    return out;
  }
}
