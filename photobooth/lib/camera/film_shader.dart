import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'filters.dart';
import 'grade.dart';

// From Lensly lib/camera/film_shader.dart: same shader, uniforms and develop
// pass; without the face-shape shader, the live preview filter and riverpod.

/// Loads `shaders/film.frag`, `shaders/skin.frag` and one LUT texture per filter.
class FilmShaders {
  FilmShaders._(this.program, this.luts, this.skin);

  final ui.FragmentProgram program;

  /// shaders/skin.frag (skin smoothing on stills).
  final ui.FragmentProgram skin;
  final Map<BoothFilter, ui.Image> luts;

  static Future<FilmShaders> load({PhotoGrade grade = PhotoGrade.none}) async {
    final program = await ui.FragmentProgram.fromAsset('shaders/film.frag');
    final skin = await ui.FragmentProgram.fromAsset('shaders/skin.frag');
    final luts = <BoothFilter, ui.Image>{};
    for (final f in BoothFilter.values) {
      luts[f] = await lutImage(f, grade);
    }
    return FilmShaders._(program, luts, skin).._grade = grade;
  }

  /// The filter's LUT (with [grade] under it) as the shader's strip texture.
  static Future<ui.Image> lutImage(BoothFilter f, PhotoGrade grade) async {
    final lut = buildLut(f, grade: grade);
    final buffer = await ui.ImmutableBuffer.fromUint8List(lutStripPixels(lut));
    final desc = ui.ImageDescriptor.raw(
      buffer,
      width: lut.size * lut.size,
      height: lut.size,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await desc.instantiateCodec();
    final img = (await codec.getNextFrame()).image;
    codec.dispose();
    desc.dispose();
    buffer.dispose();
    return img;
  }

  PhotoGrade _grade = PhotoGrade.none;
  PhotoGrade get grade => _grade;

  /// The staff saved a new grade: every filter's LUT is rebuilt with it.
  Future<void> setGrade(PhotoGrade g) async {
    if (g == _grade) return;
    _grade = g;
    for (final f in BoothFilter.values) {
      final old = luts[f];
      luts[f] = await lutImage(f, g);
      old?.dispose();
    }
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
    PhotoGrade? grade,
    ui.Image? lut,
  }) {
    final r = filter.recipe;
    final g = grade ?? _grade;
    return program.fragmentShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, kLutSize.toDouble())
      ..setFloat(3, r.grain)
      ..setFloat(4, r.grainSize * grainScale)
      ..setFloat(5, (r.vignette + g.vignette).clamp(0.0, 1.0))
      ..setFloat(6, r.halation)
      ..setFloat(7, r.leak)
      ..setFloat(8, seed)
      ..setFloat(9, r.mono ? 1 : 0)
      ..setFloat(10, 0)
      ..setImageSampler(0, input, filterQuality: FilterQuality.low)
      // Bilinear: a 17³ LUT sampled with nearest filtering bands visibly.
      ..setImageSampler(1, lut ?? luts[filter]!, filterQuality: FilterQuality.low);
  }

  /// Renders [src] (cropped to [crop]) through the filter at [outSize].
  Future<ui.Image> develop(
    ui.Image src,
    BoothFilter filter, {
    required double seed,
    required Rect crop,
    required Size outSize,
    PhotoGrade? grade,
  }) async {
    // 1. crop/scale into an intermediate so the shader samples 0..1 uv.
    final rec1 = ui.PictureRecorder();
    Canvas(rec1).drawImageRect(src, crop, Offset.zero & outSize, Paint()..filterQuality = FilterQuality.high);
    final scaled = await rec1.endRecording().toImage(outSize.width.round(), outSize.height.round());

    // 2. film pass. Grain is specified in preview pixels; scale it up so a
    // large image has the same visible grain as the ~400pt preview.
    final grainScale = (outSize.width / 640).clamp(1.0, 4.0);
    // A draft grade (Settings preview) gets its own LUT; the saved one uses [luts].
    final draft = grade != null && grade != _grade ? await lutImage(filter, grade) : null;
    final shader = configure(
      filter,
      seed: seed,
      size: outSize,
      input: scaled,
      grainScale: grainScale,
      grade: grade,
      lut: draft,
    );
    final rec2 = ui.PictureRecorder();
    Canvas(rec2).drawRect(Offset.zero & outSize, Paint()..shader = shader);
    final out = await rec2.endRecording().toImage(outSize.width.round(), outSize.height.round());
    scaled.dispose();
    shader.dispose();
    draft?.dispose();
    return out;
  }
}
