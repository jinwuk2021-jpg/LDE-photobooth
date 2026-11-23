import 'dart:async';
import 'dart:io';

import 'package:film_camera/film_camera.dart';

import '../config.dart';
import 'ring_buffer.dart';

/// Glue between the native segment writer and [RingBuffer].
class LiveRecorder {
  LiveRecorder(this.camera, this.segmentsDir) {
    buffer = RingBuffer(window: LIVE_WINDOW, onEvict: _delete);
  }

  final FilmCamera camera;
  final Directory segmentsDir;

  /// Longest a clip export may take before the print gives up on it.
  static const exportTimeout = Duration(seconds: 90);
  late final RingBuffer buffer;
  bool _active = false;
  bool get active => _active;

  static void _delete(SegmentInfo s) {
    try {
      final f = File(s.path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// Removes stray segments left by a crash or a previous session, but never
  /// the files a clip export is still reading (going to the gallery right
  /// after a shot used to delete them and the print lost its Live).
  void wipe() {
    if (!segmentsDir.existsSync()) return;
    final keep = buffer.pinnedPaths;
    for (final f in segmentsDir.listSync()) {
      if (keep.contains(f.path)) continue;
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }

  // Cuts in flight: segments closed meanwhile (also by a stop) are kept for
  // them instead of being deleted.
  int _cutting = 0;

  // Exports run one at a time: the segment encoder already holds one
  // hardware codec, and back-to-back shots must not starve each other.
  Future<void> _exports = Future.value();

  /// Live clips are silent (video only).
  Future<void> start() async {
    if (_active) return;
    _active = true;
    await camera.startSegments(dir: segmentsDir.path, segmentMs: LIVE_SEGMENT.inMilliseconds, audio: false);
  }

  /// Stops recording and deletes every segment not used by an export.
  Future<void> stop() async {
    if (!_active) return;
    _active = false;
    try {
      await camera.stopSegments();
    } finally {
      buffer.clear();
    }
  }

  void onSegment(SegmentInfo s) {
    if (_active || _cutting > 0) {
      buffer.add(s);
    } else {
      _delete(s);
    }
  }

  /// Closes the current segment and reserves the files covering the
  /// [LIVE_WINDOW] before [shutterUs]. Call [release] when done.
  /// Never throws: a print without its clip beats a print stuck waiting.
  Future<List<ClipPart>> cut(int shutterUs) async {
    if (!_active) return const [];
    _cutting++;
    try {
      final flushed = await camera.flushSegment().timeout(const Duration(seconds: 3), onTimeout: () => null);
      if (flushed != null) buffer.add(flushed);
      final parts = buffer.planClip(shutterUs);
      buffer.pin(parts);
      return parts;
    } catch (_) {
      return const [];
    } finally {
      _cutting--;
    }
  }

  void release(Iterable<List<ClipPart>> clips) {
    for (final c in clips) {
      buffer.unpin(c);
    }
  }

  /// Exports [clips] (one per shot) through the filter [lut] + [look] into [outPath].
  Future<String?> export(
    List<List<ClipPart>> clips,
    LutData lut,
    FilmLook look,
    String outPath, {
    bool flashBetween = false,
    bool mirror = false,
  }) {
    final run = _exports.then((_) => _export(clips, lut, look, outPath, flashBetween: flashBetween, mirror: mirror));
    _exports = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<String?> _export(
    List<List<ClipPart>> clips,
    LutData lut,
    FilmLook look,
    String outPath, {
    required bool flashBetween,
    required bool mirror,
  }) async {
    // Parts whose file is gone (deleted by the OS or a wipe) are skipped
    // rather than failing the whole clip.
    final nonEmpty = [
      for (final c in clips)
        if (c.where((p) => File(p.path).existsSync()).toList() case final kept when kept.isNotEmpty) kept,
    ];
    if (nonEmpty.isEmpty) return null;
    try {
      // A wedged encoder must not hold the print forever.
      return await camera
          .exportVideo(
            clips: nonEmpty,
            lut: lut,
            look: look,
            outPath: outPath,
            flashBetween: flashBetween,
            mirror: mirror,
          )
          .timeout(exportTimeout);
    } catch (_) {
      return null;
    }
  }
}
