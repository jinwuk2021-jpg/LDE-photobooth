import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:film_camera/film_camera.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

import '../config.dart';
import 'film_shader.dart';
import 'filters.dart';
import 'live_recorder.dart';
import 'skin_smooth.dart';

/// One photo of a guest's six: the raw still, its Live clip parts and the
/// cleaned-up picture every filter starts from.
class Shot {
  Shot(this.rawPath, this.clip);

  final String rawPath;

  /// Segments covering the [LIVE_WINDOW] before the shutter (pinned until [BoothCamera.release]).
  final List<ClipPart> clip;

  /// Skin smoothed, mirrored like the screen, cropped to the print cell, [PHOTO_LONG_SIDE] long.
  late final Future<ui.Image> base;
}

/// The front camera, always on (preview on every screen), with Lensly's Live
/// recorder running while a guest is shooting.
class BoothCamera {
  final FilmCamera cam = FilmCamera();
  PreviewInfo? preview;
  late final FilmShaders shaders;
  late final LiveRecorder live;
  late final Directory _tmp;
  StreamSubscription<CameraEvent>? _events;

  /// Opens the camera; false when the camera permission was refused.
  Future<bool> init(Directory tmp) async {
    _tmp = tmp;
    shaders = await FilmShaders.load();
    final perms = await cam.requestPermissions();
    if (!perms.camera) return false;
    final segments = Directory(p.join(tmp.path, 'segments'))..createSync(recursive: true);
    live = LiveRecorder(cam, segments)..wipe();
    _events = cam.events.listen((e) {
      if (e is SegmentClosed) live.onSegment(e.segment);
    });
    preview = await cam.open(CameraLens.front, landscape: true);
    // Photos access now, not in front of a guest: every session is copied into the Photos app.
    await cam.requestAlbumAccess().catchError((_) => LibraryAccess.denied);
    return true;
  }

  Future<void> dispose() async {
    await _events?.cancel();
    await cam.close();
  }

  /// Takes one photo with its Live clip and starts preparing its [Shot.base] in the background.
  Future<Shot> capture(int index, {required double cellAspect, required SkinSmooth skin}) async {
    final raw = p.join(_tmp.path, 'shot_${DateTime.now().microsecondsSinceEpoch}_$index.jpg');
    final still = await cam.takePicture(outPath: raw).timeout(const Duration(seconds: 10));
    final clip = await live.cut(still.shutterUs);
    return Shot(still.path, clip)..base = _prepare(still.path, cellAspect, skin);
  }

  Future<ui.Image> _prepare(String rawPath, double aspect, SkinSmooth skin) async {
    final bytes = await File(rawPath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    var src = (await codec.getNextFrame()).image;
    codec.dispose();
    // Skin first, on the raw photo the faces were found on (Lensly CapturePipeline.develop).
    if (skin != SkinSmooth.off) {
      final faces = await cam.detectFaces(rawPath);
      if (faces.isNotEmpty) {
        final smoothed = await smoothSkin(shaders.skin, src, faces, strength: skin.strength);
        src.dispose();
        src = smoothed;
      }
    }
    // Mirrored like the screen, centre crop to the print cell, downscaled.
    final crop = _centreCrop(src.width, src.height, aspect);
    final k = math.min(1.0, PHOTO_LONG_SIDE / math.max(crop.width, crop.height));
    final w = (crop.width * k).round(), h = (crop.height * k).round();
    final rec = ui.PictureRecorder();
    Canvas(rec)
      ..translate(w.toDouble(), 0)
      ..scale(-1, 1)
      ..drawImageRect(
        src,
        crop,
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
    final out = await rec.endRecording().toImage(w, h);
    src.dispose();
    return out;
  }

  static Rect _centreCrop(int w, int h, double aspect) {
    var cw = w.toDouble(), ch = cw / aspect;
    if (ch > h) {
      ch = h.toDouble();
      cw = ch * aspect;
    }
    return Rect.fromLTWH((w - cw) / 2, (h - ch) / 2, cw, ch);
  }

  /// [base] through [filter], same size.
  Future<ui.Image> develop(ui.Image base, BoothFilter filter, String seedId) {
    final size = Size(base.width.toDouble(), base.height.toDouble());
    return shaders.develop(base, filter, seed: seedFor(seedId), crop: Offset.zero & size, outSize: size);
  }

  /// JPEG of [img] at [outPath] (platform encoder, as in Lensly).
  Future<String> saveJpeg(ui.Image img, String outPath, {int quality = 92}) async {
    final data = await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    return cam.encodeJpeg(
      rgba: data!.buffer.asUint8List(),
      width: img.width,
      height: img.height,
      outPath: outPath,
      quality: quality,
    );
  }

  /// The shot's Live clip through [filter], mirrored like the photo. [seedId]: the one its
  /// photo was developed with ([develop]). Null when it failed.
  Future<String?> exportClip(Shot shot, BoothFilter filter, String outPath, {required String seedId}) {
    if (shot.clip.isEmpty) return Future.value(null);
    return live.export(
      [shot.clip],
      buildLut(filter, size: kClipLutSize),
      filter.look(seed: seedFor(seedId)),
      outPath,
      mirror: true,
    );
  }

  /// Frees the shots' clip segments and raw files.
  void release(List<Shot> shots) {
    live.release(shots.map((s) => s.clip));
    for (final s in shots) {
      try {
        File(s.rawPath).deleteSync();
      } catch (_) {}
    }
  }
}
