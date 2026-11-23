/// Thin native camera layer for Lensly.
///
/// Everything here is a direct mapping onto the `film_camera` method/event
/// channels. Policy (ring buffer eviction, clip planning, photobooth timing)
/// lives in the app so it can be unit tested without a device.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

enum CameraLens { back, front }

enum FlashMode { off, on }

enum ThermalState { nominal, fair, serious, critical }

enum LibraryAccess { granted, denied, limited }

class CameraPermissions {
  const CameraPermissions({required this.camera, required this.microphone});
  final bool camera;
  final bool microphone;
}

class PreviewInfo {
  const PreviewInfo({
    required this.textureId,
    required this.width,
    required this.height,
    required this.sensorRotation,
    this.mirrored = false,
  });

  final int textureId;

  /// Size of the frames delivered to the texture, already rotated upright.
  final int width;
  final int height;

  /// Degrees the texture must be rotated clockwise to display upright.
  /// iOS rotates natively so this is 0 there; on Android it is the sensor
  /// rotation unless the texture applies it itself (SurfaceTexture backend).
  final int sensorRotation;

  /// The texture already shows the front camera as a mirror (Android's
  /// SurfaceTexture backend flips it); Flutter must not flip it again.
  final bool mirrored;
}

class CapturedStill {
  const CapturedStill({
    required this.path,
    required this.width,
    required this.height,
    required this.shutterUs,
  });

  /// Unmirrored JPEG written by the platform, EXIF orientation already
  /// applied to the pixels.
  final String path;
  final int width;
  final int height;

  /// Moment the shutter fired on the shared monotonic clock.
  final int shutterUs;
}

/// One closed file of the rolling Live buffer.
class SegmentInfo {
  const SegmentInfo({
    required this.path,
    required this.startUs,
    required this.endUs,
  });

  factory SegmentInfo.fromMap(Map<Object?, Object?> m) => SegmentInfo(
        path: m['path']! as String,
        startUs: (m['startUs']! as num).toInt(),
        endUs: (m['endUs']! as num).toInt(),
      );

  final String path;
  final int startUs;
  final int endUs;

  int get durationUs => endUs - startUs;

  @override
  String toString() => 'Segment($path $startUs..$endUs)';
}

/// A slice of one segment file. `inUs`/`outUs` are relative to the start of
/// the file (file time 0 == [SegmentInfo.startUs]).
class ClipPart {
  const ClipPart({required this.path, required this.inUs, required this.outUs});
  final String path;
  final int inUs;
  final int outUs;

  int get durationUs => outUs - inUs;

  Map<String, Object> toMap() => {'path': path, 'inUs': inUs, 'outUs': outUs};

  @override
  bool operator ==(Object other) =>
      other is ClipPart &&
      other.path == path &&
      other.inUs == inUs &&
      other.outUs == outUs;

  @override
  int get hashCode => Object.hash(path, inUs, outUs);

  @override
  String toString() => 'ClipPart($path $inUs..$outUs)';
}

/// A colour lookup table: `size`³ RGB entries, red varying fastest, values in
/// 0..1. This is the layout both CoreImage (`CIColorCube`) and Media3
/// (`SingleColorLut`, after conversion) expect.
class LutData {
  const LutData({required this.size, required this.rgb});
  final int size;
  final Float32List rgb;
}

/// Film texture applied on top of the LUT when exporting video — the same
/// knobs the still/preview shader uses.
class FilmLook {
  const FilmLook({this.grain = 0, this.grainSize = 1.5, this.vignette = 0, this.halation = 0});
  final double grain;
  final double grainSize;
  final double vignette;
  final double halation;

  Map<String, double> toMap() => {
        'grain': grain,
        'grainSize': grainSize,
        'vignette': vignette,
        'halation': halation,
      };
}

sealed class CameraEvent {
  const CameraEvent();
}

class SegmentClosed extends CameraEvent {
  const SegmentClosed(this.segment);
  final SegmentInfo segment;
}

class ThermalChanged extends CameraEvent {
  const ThermalChanged(this.state);
  final ThermalState state;
}

class CameraError extends CameraEvent {
  const CameraError(this.message);
  final String message;
}

class DetectedFace {
  const DetectedFace({required this.box, this.oval = const [], this.holes = const []});

  factory DetectedFace.fromMap(Map<String, Object?> m) {
    List<(double, double)> pts(Object? v) => [
          for (final p in (v as List?) ?? const [])
            ((((p as List)[0]) as num).toDouble(), (p[1] as num).toDouble()),
        ];
    final b = [for (final v in (m['box'] as List? ?? const [0, 0, 0, 0])) (v as num).toDouble()];
    return DetectedFace(
      box: (b[0], b[1], b[2], b[3]),
      oval: pts(m['oval']),
      holes: [for (final h in (m['holes'] as List?) ?? const []) pts(h)],
    );
  }

  /// left, top, right, bottom (0..1, y down).
  final (double, double, double, double) box;

  /// Face outline (may be empty: then an ellipse is drawn from [box]).
  final List<(double, double)> oval;

  /// Eyes, brows, lips: kept sharp.
  final List<List<(double, double)>> holes;
}

class ZoomRange {
  const ZoomRange({required this.min, required this.max, required this.zoom});
  final double min;
  final double max;
  final double zoom;
}

class FilmCamera {
  FilmCamera({MethodChannel? channel, EventChannel? events})
      : _channel = channel ?? const MethodChannel('film_camera'),
        _events = events ?? const EventChannel('film_camera/events');

  final MethodChannel _channel;
  final EventChannel _events;
  Stream<CameraEvent>? _eventStream;

  Stream<CameraEvent> get events => _eventStream ??= _events
      .receiveBroadcastStream()
      .map((e) => _decodeEvent(e as Map<Object?, Object?>))
      .where((e) => e != null)
      .cast<CameraEvent>();

  static CameraEvent? _decodeEvent(Map<Object?, Object?> e) {
    switch (e['type']) {
      case 'segment':
        return SegmentClosed(SegmentInfo.fromMap(e));
      case 'thermal':
        return ThermalChanged(_thermal(e['state'] as String?));
      case 'error':
        return CameraError(e['message'] as String? ?? 'unknown');
    }
    return null;
  }

  static ThermalState _thermal(String? s) => ThermalState.values.firstWhere(
        (t) => t.name == s,
        orElse: () => ThermalState.nominal,
      );

  Future<CameraPermissions> requestPermissions({bool microphone = false}) async {
    final r = await _channel.invokeMapMethod<String, Object?>(
      'requestPermissions',
      {'microphone': microphone},
    );
    return CameraPermissions(
      camera: r?['camera'] == true,
      microphone: r?['microphone'] == true,
    );
  }

  /// [landscape]: frames come out landscape (photobooth iPad) instead of portrait.
  Future<PreviewInfo> open(CameraLens lens, {bool landscape = false}) async {
    final r = await _channel.invokeMapMethod<String, Object?>(
      'open',
      {'lens': lens.name, 'landscape': landscape},
    );
    return PreviewInfo(
      textureId: (r!['textureId']! as num).toInt(),
      width: (r['width']! as num).toInt(),
      height: (r['height']! as num).toInt(),
      sensorRotation: (r['rotation'] as num?)?.toInt() ?? 0,
      mirrored: r['mirrored'] == true,
    );
  }

  Future<void> close() => _channel.invokeMethod('close');

  /// Faces in the photo at [path] for skin smoothing (Vision on iOS, ML Kit
  /// on Android). Normalised, upright, y down. Empty when none / unavailable.
  Future<List<DetectedFace>> detectFaces(String path) async {
    final r = await _channel.invokeListMethod<Object?>('detectFaces', {'path': path});
    return [for (final f in r ?? const []) DetectedFace.fromMap((f! as Map).cast<String, Object?>())];
  }

  /// Zoom the open camera supports, as multiples of the main lens
  /// (min < 1 when there is an ultra-wide).
  Future<ZoomRange> zoomRange() async {
    final r = await _channel.invokeMapMethod<String, Object?>('zoomRange');
    double v(String k) => (r?[k] as num?)?.toDouble() ?? 1;
    return ZoomRange(min: v('min'), max: v('max'), zoom: v('zoom'));
  }

  /// Sets the zoom (clamped natively); returns what was applied.
  Future<double> setZoom(double zoom) async =>
      ((await _channel.invokeMethod<num>('setZoom', {'zoom': zoom})) ?? 1).toDouble();

  Future<CapturedStill> takePicture({
    required String outPath,
    FlashMode flash = FlashMode.off,
  }) async {
    final r = await _channel.invokeMapMethod<String, Object?>(
      'takePicture',
      {'outPath': outPath, 'flash': flash.name},
    );
    return CapturedStill(
      path: r!['path']! as String,
      width: (r['width']! as num).toInt(),
      height: (r['height']! as num).toInt(),
      shutterUs: (r['shutterUs']! as num).toInt(),
    );
  }

  /// Current value of the shared monotonic clock.
  Future<int> nowUs() async =>
      ((await _channel.invokeMethod<num>('nowUs')) ?? 0).toInt();

  /// Starts writing ~[segmentMs] files into [dir]. Each closed file is
  /// reported as a [SegmentClosed] event. Deleting old files is the caller's
  /// job (see the app's `RingBuffer`).
  Future<void> startSegments({
    required String dir,
    int segmentMs = 1000,
    bool audio = true,
  }) =>
      _channel.invokeMethod('startSegments', {
        'dir': dir,
        'segmentMs': segmentMs,
        'audio': audio,
      });

  /// Stops recording; the last open segment is finalized and reported.
  Future<void> stopSegments() => _channel.invokeMethod('stopSegments');

  /// Closes the segment currently being written (so it covers the shutter
  /// moment) and returns it. Recording continues in a fresh file.
  Future<SegmentInfo?> flushSegment() async {
    final r = await _channel.invokeMapMethod<Object?, Object?>('flushSegment');
    return r == null ? null : SegmentInfo.fromMap(r);
  }

  /// Exports [clips] back to back into one 720p MP4 with [lut] applied.
  /// When [flashBetween] is set a short white flash separates clips.
  Future<String> exportVideo({
    required List<List<ClipPart>> clips,
    required LutData lut,
    required String outPath,
    FilmLook look = const FilmLook(),
    bool flashBetween = false,
    bool mirror = false,
  }) async {
    final r = await _channel.invokeMethod<String>('exportVideo', {
      'clips': [
        for (final c in clips) [for (final p in c) p.toMap()],
      ],
      'lutSize': lut.size,
      'lut': lut.rgb,
      'outPath': outPath,
      'look': look.toMap(),
      'flashBetween': flashBetween,
      'mirror': mirror,
    });
    return r!;
  }

  /// Encodes straight RGBA pixels to JPEG using the platform codec.
  Future<String> encodeJpeg({
    required Uint8List rgba,
    required int width,
    required int height,
    required String outPath,
    int quality = 92,
  }) async {
    final r = await _channel.invokeMethod<String>('encodeJpeg', {
      'rgba': rgba,
      'width': width,
      'height': height,
      'outPath': outPath,
      'quality': quality,
    });
    return r!;
  }

  /// Opens this app's page in the system Settings (camera / photos access
  /// after the user said no, when the system no longer asks).
  Future<bool> openAppSettings() async => await _channel.invokeMethod<bool>('openAppSettings') ?? false;

  Future<LibraryAccess> libraryAccess({bool request = false}) async {
    final r = await _channel.invokeMethod<String>(
      'libraryAccess',
      {'request': request},
    );
    return LibraryAccess.values.firstWhere(
      (a) => a.name == r,
      orElse: () => LibraryAccess.denied,
    );
  }

  /// iOS: asks for read-write access so files can go into a named album
  /// (add-only access cannot create or find albums). Android: same as
  /// [libraryAccess] with `request: true`.
  Future<LibraryAccess> requestAlbumAccess() async {
    final r = await _channel.invokeMethod<String>('requestAlbumAccess');
    return LibraryAccess.values.firstWhere((a) => a.name == r, orElse: () => LibraryAccess.denied);
  }

  /// Adds a file to the device library inside the system album [album].
  Future<bool> saveToLibrary({
    required String path,
    required bool isVideo,
    required String album,
  }) async =>
      (await _channel.invokeMethod<bool>('saveToLibrary', {
        'path': path,
        'isVideo': isVideo,
        'album': album,
      })) ??
      false;

  /// iOS: keeps these folders out of the iCloud backup (they can be
  /// downloaded or rebuilt again). Android: no-op (backup rules decide).
  Future<void> excludeFromBackup(List<String> paths) async {
    await _channel.invokeMethod<bool>('excludeFromBackup', {'paths': paths});
  }

  Future<ThermalState> thermalState() async =>
      _thermal(await _channel.invokeMethod<String>('thermalState'));
}
