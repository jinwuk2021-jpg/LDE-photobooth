import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:film_camera/film_camera.dart' show DetectedFace;
import 'package:flutter/painting.dart';

/// "Mịn da" setting. Persisted by name; never rename an entry.
enum SkinSmooth {
  off(0),
  light(0.55),
  medium(0.85);

  const SkinSmooth(this.strength);

  /// Blend amount of the smoothed skin (0..1).
  final double strength;

  String get label => switch (this) {
    off => 'Tắt',
    light => 'Nhẹ',
    medium => 'Vừa',
  };

  static SkinSmooth byName(String? n) => values.firstWhere((v) => v.name == n, orElse: () => light);
}

/// Longest side of the mask texture; it is soft anyway, the shader samples it bilinearly.
const int kSkinMaskSide = 512;

/// Gaussian sigma in photo pixels for the biggest face: ~1/40 of its width,
/// so pores go but features stay, whatever the distance.
double skinRadiusFor(List<DetectedFace> faces, int width) {
  final w = faces.map((f) => (f.box.$3 - f.box.$1) * width).fold<double>(0, math.max);
  return (w / 40).clamp(2.0, 16.0);
}

/// Draws the face-skin mask (white = smooth) at [size]: each face outline
/// (or an ellipse from its box, taller to include the forehead), minus its
/// eyes / brows / lips (slightly enlarged), feathered so edges never show.
void paintSkinMask(Canvas canvas, Size size, List<DetectedFace> faces) {
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF000000));
  for (final f in faces) {
    final (l, t, r, b) = f.box;
    final fw = (r - l) * size.width;
    final feather = math.max(1.0, fw * 0.05);
    Offset pt((double, double) p) => Offset(p.$1 * size.width, p.$2 * size.height);
    final face = Path();
    if (f.oval.length >= 3) {
      face.addPolygon([for (final p in f.oval) pt(p)], true);
    } else {
      // Vision / landmark-only boxes stop at the brows: add the forehead.
      final h = b - t;
      face.addOval(Rect.fromLTRB(l * size.width, (t - h * 0.22) * size.height, r * size.width, b * size.height));
    }
    final soft = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, feather);
    canvas.drawPath(face, soft);
    final hole = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, feather * 0.6);
    final grow = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = fw * 0.035
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, feather * 0.6);
    for (final h in f.holes) {
      if (h.length < 3) continue;
      final p = Path()..addPolygon([for (final q in h) pt(q)], true);
      canvas.drawPath(p, hole);
      canvas.drawPath(p, grow);
    }
  }
}

/// Mask image for a [width]×[height] photo.
Future<ui.Image> renderSkinMask(List<DetectedFace> faces, int width, int height) {
  final k = kSkinMaskSide / math.max(width, height);
  final size = Size((width * k).roundToDouble(), (height * k).roundToDouble());
  final rec = ui.PictureRecorder();
  paintSkinMask(Canvas(rec), size, faces);
  return rec.endRecording().toImage(size.width.toInt(), size.height.toInt());
}

/// [src] with smoothed skin (shaders/skin.frag), same size. Caller owns
/// both images.
Future<ui.Image> smoothSkin(
  ui.FragmentProgram program,
  ui.Image src,
  List<DetectedFace> faces, {
  required double strength,
}) async {
  final mask = await renderSkinMask(faces, src.width, src.height);
  final size = Size(src.width.toDouble(), src.height.toDouble());
  final sigma = skinRadiusFor(faces, src.width);
  final blurRec = ui.PictureRecorder();
  Canvas(blurRec).drawImage(
    src,
    Offset.zero,
    Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
  );
  final blurred = await blurRec.endRecording().toImage(src.width, src.height);
  final shader = program.fragmentShader()
    ..setFloat(0, size.width)
    ..setFloat(1, size.height)
    ..setFloat(2, strength)
    ..setImageSampler(0, src, filterQuality: FilterQuality.low)
    ..setImageSampler(1, blurred, filterQuality: FilterQuality.low)
    ..setImageSampler(2, mask, filterQuality: FilterQuality.low);
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(Offset.zero & size, Paint()..shader = shader);
  final out = await rec.endRecording().toImage(src.width, src.height);
  shader.dispose();
  mask.dispose();
  blurred.dispose();
  return out;
}
