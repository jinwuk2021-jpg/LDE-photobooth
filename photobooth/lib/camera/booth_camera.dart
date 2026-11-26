import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:film_camera/film_camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

import '../config.dart';
import 'film_shader.dart';
import 'grade.dart';
import 'filters.dart';
import 'live_recorder.dart';
import 'ptp.dart';
import 'skin_smooth.dart';
import 'sony_camera.dart';

/// One photo of a guest's six: the raw still, its Live clip parts and the
/// cleaned-up picture every filter starts from.
class Shot {
  Shot(this.rawPath, this.clip, {this.fromSony = false});

  final String rawPath;

  /// Taken by the Sony camera (else the iPad's front camera).
  final bool fromSony;

  /// Segments covering the [LIVE_WINDOW] before the shutter (pinned until [BoothCamera.release]).
  final List<ClipPart> clip;

  /// Skin smoothed, mirrored like the screen, cropped to the print cell, [PHOTO_LONG_SIDE] long.
  late final Future<ui.Image> base;
}

/// The front camera, always on (preview on every screen), with Lensly's Live
/// recorder running while a guest is shooting. With a Sony camera on the USB-C port the
/// photos come from it; the iPad camera still records the Live clips and stands in for
/// any picture the Sony does not deliver.
class BoothCamera {
  BoothCamera({PtpTransport? ptp}) : sony = SonyCamera(ptp ?? ChannelPtpTransport());

  final FilmCamera cam = FilmCamera();
  final SonyCamera sony;

  /// Pictures the Sony delivered, and those the iPad camera had to take instead (this run).
  int sonyShots = 0, sonyMisses = 0;
  /// The open camera's preview texture; null while it sleeps (start screen, photo picker).
  final ValueNotifier<PreviewInfo?> previewInfo = ValueNotifier(null);
  PreviewInfo? get preview => previewInfo.value;
  late final FilmShaders shaders;
  late final LiveRecorder live;
  late final Directory _tmp;
  StreamSubscription<CameraEvent>? _events;

  /// Gets the camera ready (permissions, shaders, Live recorder) without turning it on; false when
  /// the camera permission was refused. The camera itself runs only around a guest's shooting
  /// ([wake] / [sleep]): left on at the start screen it heated the iPad.
  Future<bool> init(Directory tmp) async {
    _tmp = tmp;
    shaders = await FilmShaders.load(grade: _grade);
    _shadersReady = true;
    // Changed while the shaders loaded.
    if (shaders.grade != _grade) await shaders.setGrade(_grade);
    final perms = await cam.requestPermissions();
    if (!perms.camera) return false;
    final segments = Directory(p.join(tmp.path, 'segments'))..createSync(recursive: true);
    live = LiveRecorder(cam, segments)..wipe();
    _events = cam.events.listen((e) {
      if (e is SegmentClosed) live.onSegment(e.segment);
    });
    // Photos access now, not in front of a guest: every session is copied into the Photos app.
    await cam.requestAlbumAccess().catchError((_) => LibraryAccess.denied);
    unawaited(sony.start());
    return true;
  }

  Future<void> dispose() async {
    await _events?.cancel();
    await sleep();
  }

  /// Turns the front camera on (the guest pressed Start). Safe to call again while it is on.
  /// Throws when the camera cannot open.
  Future<void> wake() {
    _wantOn = true;
    return _settle();
  }

  /// Turns it off (photo picker, start screen). Clips already cut are files: they are kept.
  Future<void> sleep() {
    _wantOn = false;
    return _settle().catchError((Object _) {});
  }

  // On / off requests run one after the other; each brings the camera to the latest wanted state.
  bool _wantOn = false;
  Future<void> _switching = Future.value();

  Future<void> _settle() => _switching = _switching.catchError((Object _) {}).then((_) async {
    if (_wantOn && previewInfo.value == null) {
      previewInfo.value = await cam.open(CameraLens.front, landscape: true);
    } else if (!_wantOn && previewInfo.value != null) {
      await live.stop();
      previewInfo.value = null;
      await cam.close();
    }
  });

  /// Takes one photo with its Live clip and starts preparing its [Shot.base] in the background.
  /// [external]: the Sony takes the photo when it is ready; the iPad's own still (taken at the
  /// same moment, it times the Live clip) is used when the Sony fails.
  Future<Shot> capture(int index, {required double cellAspect, required SkinSmooth skin, bool external = false}) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final raw = p.join(_tmp.path, 'shot_${stamp}_$index.jpg');
    final sonyJpeg = external && sony.ready
        ? sony.capture().then<Uint8List?>((v) => v, onError: (Object e) => null)
        : null;
    final still = await cam.takePicture(outPath: raw).timeout(const Duration(seconds: 10));
    final clip = await live.cut(still.shutterUs);
    var path = still.path;
    var fromSony = false;
    if (sonyJpeg != null) {
      final jpeg = await sonyJpeg;
      if (jpeg != null) {
        path = p.join(_tmp.path, 'sony_${stamp}_$index.jpg');
        await File(path).writeAsBytes(jpeg, flush: true);
        File(still.path).delete().ignore();
        fromSony = true;
        sonyShots++;
      } else {
        sonyMisses++;
      }
    }
    return Shot(path, clip, fromSony: fromSony)..base = _prepare(path, cellAspect, skin);
  }

  Future<ui.Image> _prepare(String rawPath, double aspect, SkinSmooth skin) async {
    final bytes = await File(rawPath).readAsBytes();
    // A camera photo (24 MP) is decoded at most [_decodeLong] long: the print needs far less.
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    final long = math.max(desc.width, desc.height);
    final scale = long > _decodeLong ? _decodeLong / long : 1.0;
    final codec = await desc.instantiateCodec(
      targetWidth: scale < 1 ? (desc.width * scale).round() : null,
      targetHeight: scale < 1 ? (desc.height * scale).round() : null,
    );
    var src = (await codec.getNextFrame()).image;
    codec.dispose();
    desc.dispose();
    buffer.dispose();
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

  static const _decodeLong = 3200;

  static Rect _centreCrop(int w, int h, double aspect) {
    var cw = w.toDouble(), ch = cw / aspect;
    if (ch > h) {
      ch = h.toDouble();
      cw = ch * aspect;
    }
    return Rect.fromLTWH((w - cw) / 2, (h - ch) / 2, cw, ch);
  }

  // The staff's colour grade (Cài đặt → Màu ảnh); set by Booth from the settings.
  PhotoGrade _grade = PhotoGrade.none;
  bool _shadersReady = false;
  PhotoGrade get grade => _grade;

  /// New photos and clips from now on use [g] (the guest's filter goes on top of it).
  Future<void> setGrade(PhotoGrade g) async {
    _grade = g;
    if (_shadersReady) await shaders.setGrade(g);
  }

  /// [base] through [filter], same size. [grade]: a draft to preview instead of the saved one.
  Future<ui.Image> develop(ui.Image base, BoothFilter filter, String seedId, {PhotoGrade? grade}) {
    final size = Size(base.width.toDouble(), base.height.toDouble());
    return shaders.develop(
      base,
      filter,
      seed: seedFor(seedId),
      crop: Offset.zero & size,
      outSize: size,
      grade: grade,
    );
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
      buildLut(filter, size: kClipLutSize, grade: _grade),
      filter.look(seed: seedFor(seedId), grade: _grade),
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
