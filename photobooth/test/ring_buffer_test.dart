import 'package:film_camera/film_camera.dart';
import 'package:photobooth/camera/ring_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

const s = 1000000; // 1 second in µs

SegmentInfo seg(int i, {int start = 0, int len = s}) =>
    SegmentInfo(path: 'seg$i.mp4', startUs: start + i * len, endUs: start + (i + 1) * len);

void main() {
  late List<String> evicted;
  late RingBuffer rb;

  setUp(() {
    evicted = [];
    rb = RingBuffer(onEvict: (s) => evicted.add(s.path));
  });

  test('keeps only what covers the last 5 seconds (+1 s slack)', () {
    for (var i = 0; i < 20; i++) {
      rb.add(seg(i));
    }
    // newest end = 20s, horizon = 20 − 5 − 1 = 14s → segments 14..19 stay.
    expect(rb.segments.map((e) => e.path), [
      'seg14.mp4',
      'seg15.mp4',
      'seg16.mp4',
      'seg17.mp4',
      'seg18.mp4',
      'seg19.mp4',
    ]);
    expect(evicted.length, 14);
    expect(rb.spanUs, 6 * s);
  });

  test('never grows unbounded (no leak) over a long session', () {
    for (var i = 0; i < 10000; i++) {
      rb.add(seg(i));
      expect(rb.length, lessThanOrEqualTo(7));
    }
    expect(evicted.length + rb.length, 10000);
    expect(rb.filesHeld, rb.length);
  });

  test('keeps one extra segment when segments do not align with the window', () {
    // 1.3 s segments: covering 5 s needs the segment that straddles the horizon.
    for (var i = 0; i < 10; i++) {
      rb.add(seg(i, len: 1300000));
    }
    final first = rb.segments.first;
    final horizon = rb.segments.last.endUs - 6 * s;
    expect(first.startUs, lessThanOrEqualTo(horizon));
    expect(rb.segments[1].startUs, greaterThan(horizon));
  });

  test('plans exactly the 5 seconds before the shutter', () {
    for (var i = 0; i < 8; i++) {
      rb.add(seg(i));
    }
    // Flushed segment ends at 8 s, shutter was at 7.5 s: window 2.5..7.5 s
    // is still fully on disk thanks to the slack.
    final parts = rb.planClip(7500000);
    expect(parts.first, const ClipPart(path: 'seg2.mp4', inUs: 500000, outUs: s));
    expect(parts.last, const ClipPart(path: 'seg7.mp4', inUs: 0, outUs: 500000));
    final total = parts.fold<int>(0, (a, p) => a + p.durationUs);
    expect(total, 5 * s);
  });

  test('clip is shorter when the camera was open less than 5 s', () {
    rb.add(seg(0));
    rb.add(seg(1));
    final parts = rb.planClip(1800000);
    expect(parts.length, 2);
    expect(parts.fold<int>(0, (a, p) => a + p.durationUs), 1800000);
  });

  test('empty buffer plans an empty clip', () {
    expect(rb.planClip(123456), isEmpty);
  });

  test('pinned segments survive eviction until unpinned', () {
    for (var i = 0; i < 6; i++) {
      rb.add(seg(i));
    }
    final parts = rb.planClip(6 * s);
    rb.pin(parts);
    for (var i = 6; i < 15; i++) {
      rb.add(seg(i));
    }
    // seg1..seg5 were pinned: not yet evicted.
    for (final p in parts) {
      expect(evicted, isNot(contains(p.path)));
    }
    expect(rb.filesHeld, rb.length + parts.length);
    rb.unpin(parts);
    for (final p in parts) {
      expect(evicted, contains(p.path));
    }
    expect(rb.filesHeld, rb.length);
  });

  test('overlapping pins (photobooth clips) need every unpin', () {
    for (var i = 0; i < 6; i++) {
      rb.add(seg(i));
    }
    final a = rb.planClip(5 * s);
    final b = rb.planClip(6 * s);
    rb.pin(a);
    rb.pin(b);
    rb.clear();
    rb.unpin(a);
    expect(evicted.toSet().intersection(b.map((p) => p.path).toSet()), isEmpty);
    rb.unpin(b);
    expect(evicted.toSet(), containsAll({...a.map((p) => p.path), ...b.map((p) => p.path)}));
  });

  test('clear evicts everything', () {
    for (var i = 0; i < 4; i++) {
      rb.add(seg(i));
    }
    rb.clear();
    expect(rb.length, 0);
    expect(evicted.length, 4);
  });

  test('zero-length segments are dropped immediately', () {
    rb.add(const SegmentInfo(path: 'z.mp4', startUs: 5, endUs: 5));
    expect(rb.length, 0);
    expect(evicted, ['z.mp4']);
  });

  test('a segment reported twice (flush result + event) is kept once', () {
    rb.add(seg(0));
    rb.add(seg(0));
    expect(rb.length, 1);
    expect(evicted, isEmpty);
  });
}
