import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/booth/frame_detect.dart';

/// A [w] × [h] opaque card in one colour, with transparent [holes] (soft 1 px edge on each).
Uint8List card(int w, int h, List<Rect> holes, {List<Rect> busy = const [], int scale = 1}) {
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    px[i * 4] = 240;
    px[i * 4 + 1] = 214;
    px[i * 4 + 2] = 206;
    px[i * 4 + 3] = 255;
  }
  void fill(Rect r, void Function(int i, int x, int y) f) {
    for (var y = math.max(0, (r.top * scale).round()); y < math.min(h, (r.bottom * scale).round()); y++) {
      for (var x = math.max(0, (r.left * scale).round()); x < math.min(w, (r.right * scale).round()); x++) {
        f((y * w + x) * 4, x, y);
      }
    }
  }

  for (final r in holes) {
    fill(r.inflate(1), (i, _, _) => px[i + 3] = 190); // soft (mostly opaque) anti-aliased edge
    fill(r, (i, _, _) => px[i + 3] = 0);
  }
  // Busy = a checker pattern (text, decoration): no QR there.
  for (final r in busy) {
    fill(r, (i, x, y) {
      final v = ((x ~/ 6) + (y ~/ 6)).isEven ? 30 : 230;
      px[i] = v;
      px[i + 1] = v;
      px[i + 2] = v;
    });
  }
  return px;
}

const fourCut = [
  Rect.fromLTWH(116, 56, 760, 428),
  Rect.fromLTWH(900, 56, 760, 428),
  Rect.fromLTWH(116, 508, 760, 428),
  Rect.fromLTWH(900, 508, 760, 428),
];

void main() {
  test('4 Cut landscape: four windows in reading order, QR in the bottom-right corner', () {
    // Holes given out of order: the scan sorts them.
    final s = scanFrame(card(1776, 1200, fourCut.reversed.toList()), 1776, 1200);
    expect(s.canSave, isTrue, reason: '${s.checks}');
    expect(s.card, landscapeCard);
    expect(s.slots, fourCut);
    expect(s.autoQr, isNotNull);
    final qr = s.autoQr!;
    expect(qr.width, qrSide);
    expect(s.qrCorner, 'góc phải dưới');
    for (final slot in fourCut) {
      expect(slot.overlaps(qr), isFalse);
    }
    // Where the built-in 4 Cut has it: flush with the windows' right edge, 52 above the bottom.
    expect(qr, const Rect.fromLTWH(1480, 968, 180, 180));
    expect(s.checks.map((c) => c.text), contains('Tìm thấy 4 ô trong suốt'));
    expect(s.checks.map((c) => c.text), contains('Ô 16:9: ảnh chụp được cắt vừa ô'));
    expect(s.checks.any((c) => c.text.contains('bán trong suốt')), isTrue);
  });

  test('3 Cut strip: windows top to bottom; busy corner pushes the QR to a plain spot', () {
    const strip = [
      Rect.fromLTWH(300, 60, 840, 500),
      Rect.fromLTWH(300, 600, 840, 500),
      Rect.fromLTWH(300, 1140, 840, 500),
    ];
    // Text over the whole bottom band except the left part.
    final s = scanFrame(
      card(1200, 1776, strip, busy: const [Rect.fromLTWH(260, 1650, 940, 126), Rect.fromLTWH(1140, 0, 60, 1776)]),
      1200,
      1776,
    );
    expect(s.slots, strip);
    expect(s.autoQr, isNotNull);
    final qr = s.autoQr!;
    expect(qr.left, lessThan(300), reason: 'the plain band left of the windows: $qr');
  });

  test('a PNG at twice the size: windows come back in card units, with a note', () {
    final s = scanFrame(card(2400, 3552, const [Rect.fromLTWH(80, 80, 1040, 700)], scale: 2), 2400, 3552);
    expect(s.card, portraitCard);
    expect(s.slots, [const Rect.fromLTWH(80, 80, 1040, 700)]);
    expect(s.checks.first.level, CheckLevel.warn);
    expect(s.canSave, isTrue);
  });

  test('refused: wrong proportions, no transparency, too many windows', () {
    final square = scanFrame(card(1000, 1000, const []), 1000, 1000);
    expect(square.canSave, isFalse);
    expect(square.checks.single.level, CheckLevel.bad);

    final opaque = scanFrame(card(1200, 1776, const []), 1200, 1776);
    expect(opaque.canSave, isFalse);
    expect(opaque.checks.last.text, contains('không có vùng trong suốt'));

    final seven = scanFrame(
      card(1200, 1776, [for (var i = 0; i < 7; i++) Rect.fromLTWH(100, 60.0 + i * 220, 400, 180)]),
      1200,
      1776,
    );
    expect(seven.canSave, isFalse);
    expect(seven.checks.any((c) => c.text == 'Tìm thấy 7 ô, tối đa 6 ô'), isTrue);
  });

  test('transparent margin on the paper edge and round holes are ignored, with a warning', () {
    final px = card(1200, 1776, const [Rect.fromLTWH(100, 100, 1000, 700), Rect.fromLTWH(0, 1700, 1200, 76)]);
    // A round hole: a disc of radius 150 at (600, 1200).
    for (var y = 1050; y < 1350; y++) {
      for (var x = 450; x < 750; x++) {
        if ((x - 600) * (x - 600) + (y - 1200) * (y - 1200) < 150 * 150) px[(y * 1200 + x) * 4 + 3] = 0;
      }
    }
    final s = scanFrame(px, 1200, 1776);
    expect(s.slots, [const Rect.fromLTWH(100, 100, 1000, 700)]);
    expect(s.checks.any((c) => c.text.contains('sát mép')), isTrue);
    expect(s.checks.any((c) => c.text.contains('không phải hình chữ nhật')), isTrue);
  });

  test('labels', () {
    expect(ratioLabel(760 / 428), '16:9');
    expect(ratioLabel(1.5), '3:2');
    expect(ratioLabel(1.62), '1,62:1');
    expect(cornerLabel(const Rect.fromLTWH(40, 1544, 180, 180), portraitCard), 'góc trái dưới');
    expect(cornerLabel(const Rect.fromLTWH(1480, 968, 180, 180), landscapeCard), 'góc phải dưới');
  });
}
