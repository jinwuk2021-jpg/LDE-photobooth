import 'package:film_camera/film_camera.dart';

/// Keeps only the newest segments needed to cover [window] and plans the
/// clip that ends at the shutter.
///
/// Native code just writes ~1 s files and reports them; this class owns the
/// policy so it can be unit-tested. Memory is bounded by the number of
/// segments covering the window (+ any pinned by an in-flight export).
class RingBuffer {
  RingBuffer({
    this.window = const Duration(seconds: 5),
    this.slack = const Duration(seconds: 1),
    required this.onEvict,
  });

  final Duration window;

  /// Extra history kept beyond [window]. The segment flushed at capture ends
  /// a few frames *after* the shutter, so trimming against the newest end
  /// alone could cut the start of the clip.
  final Duration slack;

  /// Called with each segment that is no longer needed (delete the file).
  final void Function(SegmentInfo segment) onEvict;

  final List<SegmentInfo> _segments = [];
  final Map<String, int> _pins = {};
  final Set<String> _evictWhenUnpinned = {};

  List<SegmentInfo> get segments => List.unmodifiable(_segments);
  int get length => _segments.length;

  /// Covered span in µs (newest end − oldest start), 0 when empty.
  int get spanUs => _segments.isEmpty ? 0 : _segments.last.endUs - _segments.first.startUs;

  /// Adds a closed segment. The same segment can arrive twice (as the
  /// `flushSegment` result and as an event); duplicates are ignored.
  void add(SegmentInfo s) {
    if (_segments.any((e) => e.path == s.path) || _pinnedDetached.containsKey(s.path)) return;
    if (s.endUs <= s.startUs) {
      onEvict(s);
      return;
    }
    // Keep sorted by start time; native delivers in order but be defensive.
    var i = _segments.length;
    while (i > 0 && _segments[i - 1].startUs > s.startUs) {
      i--;
    }
    _segments.insert(i, s);
    _trim();
  }

  /// Drops the oldest segments while the remainder still covers
  /// [window] + [slack] back from the newest end.
  void _trim() {
    if (_segments.isEmpty) return;
    final horizon = _segments.last.endUs - window.inMicroseconds - slack.inMicroseconds;
    while (_segments.length > 1 && _segments[1].startUs <= horizon) {
      _release(_segments.removeAt(0));
    }
  }

  void _release(SegmentInfo s) {
    if ((_pins[s.path] ?? 0) > 0) {
      _evictWhenUnpinned.add(s.path);
      _pinnedDetached[s.path] = s;
    } else {
      onEvict(s);
    }
  }

  final Map<String, SegmentInfo> _pinnedDetached = {};

  /// The parts covering `[shutterUs − window, shutterUs]`, oldest first.
  /// Shorter than [window] when not enough has been recorded yet.
  List<ClipPart> planClip(int shutterUs) {
    final startUs = shutterUs - window.inMicroseconds;
    final parts = <ClipPart>[];
    for (final s in _segments) {
      if (s.endUs <= startUs || s.startUs >= shutterUs) continue;
      final inUs = (startUs - s.startUs).clamp(0, s.durationUs);
      final outUs = (shutterUs - s.startUs).clamp(0, s.durationUs);
      if (outUs > inUs) parts.add(ClipPart(path: s.path, inUs: inUs, outUs: outUs));
    }
    return parts;
  }

  /// Prevents the files in [parts] from being deleted until [unpin].
  void pin(List<ClipPart> parts) {
    for (final p in parts) {
      _pins[p.path] = (_pins[p.path] ?? 0) + 1;
    }
  }

  void unpin(List<ClipPart> parts) {
    for (final p in parts) {
      final n = (_pins[p.path] ?? 1) - 1;
      if (n > 0) {
        _pins[p.path] = n;
        continue;
      }
      _pins.remove(p.path);
      if (_evictWhenUnpinned.remove(p.path)) {
        final s = _pinnedDetached.remove(p.path);
        if (s != null) onEvict(s);
      }
    }
  }

  /// Files an in-flight export still reads (never delete these).
  Set<String> get pinnedPaths => {..._pins.keys};

  /// Number of files currently on disk because of this buffer.
  int get filesHeld => _segments.length + _pinnedDetached.length;

  /// Evicts everything not pinned (app backgrounded / Live off).
  void clear() {
    final all = List.of(_segments);
    _segments.clear();
    all.forEach(_release);
  }
}
