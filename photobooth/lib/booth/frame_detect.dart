import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// The card sizes a frame PNG can have (≈300 dpi on a 100 × 148 mm postcard).
const portraitCard = Size(1200, 1776);
const landscapeCard = Size(1776, 1200);

/// QR square on every card (as the built-in frames).
const qrSide = 180.0;

enum CheckLevel { ok, warn, bad }

/// One line of "Kiểm tra file".
class FrameCheck {
  const FrameCheck(this.level, this.text);
  final CheckLevel level;
  final String text;

  @override
  String toString() => '${level.name}: $text';
}

/// What a frame PNG holds: its photo windows (from the transparent holes) and a free spot for the
/// QR, in card units (1200 × 1776 or 1776 × 1200, whatever the PNG's own pixel size).
class FrameScan {
  const FrameScan({
    required this.pngSize,
    required this.card,
    required this.slots,
    required this.checks,
    this.autoQr,
    this.qrCorner,
  });

  final Size pngSize;

  /// Card size the frame prints at; null when the PNG has the wrong proportions.
  final Size? card;

  /// Photo windows in reading order (rows top to bottom, left to right in a row).
  final List<Rect> slots;
  final List<FrameCheck> checks;

  /// A plain, opaque spot clear of the windows for the QR, or null when there is none.
  final Rect? autoQr;

  /// "góc phải dưới" … for the check line.
  final String? qrCorner;

  bool get canSave => card != null && slots.isNotEmpty && checks.every((c) => c.level != CheckLevel.bad);

  /// Where the QR goes when nothing better is known: bottom-right, as on the 2 Cut cards.
  Rect get fallbackQr {
    final c = card ?? portraitCard;
    return Rect.fromLTWH(c.width - qrSide - (c.width > c.height ? 116 : 72), c.height - qrSide - 52, qrSide, qrSide);
  }
}

/// Reads [rgba] (straight alpha, [w] × [h]) the way the booth needs it. Runs on a background
/// isolate (`compute(scanFrameArgs, (rgba, w, h))`): about 2 M pixels.
FrameScan scanFrame(Uint8List rgba, int w, int h) {
  final checks = <FrameCheck>[];
  final pngSize = Size(w.toDouble(), h.toDouble());
  final portrait = h > w;
  final card = portrait ? portraitCard : landscapeCard;
  final kind = portrait ? 'dọc' : 'ngang';
  if ((w / h - card.aspectRatio).abs() > 0.01) {
    checks.add(
      FrameCheck(CheckLevel.bad, 'Khổ $w×$h không đúng tỉ lệ tấm in (cần 1200×1776 dọc hoặc 1776×1200 ngang)'),
    );
    return FrameScan(pngSize: pngSize, card: null, slots: const [], checks: checks);
  }
  if (w == card.width && h == card.height) {
    checks.add(FrameCheck(CheckLevel.ok, 'Đúng khổ $kind $w×$h'));
  } else {
    checks.add(
      FrameCheck(CheckLevel.warn, 'Khổ $w×$h, sẽ in như ${card.width.round()}×${card.height.round()} (đúng tỉ lệ)'),
    );
  }
  final scale = card.width / w;

  // Transparent = alpha below half; count the in-between pixels (soft hole edges).
  final n = w * h;
  final mask = Uint8List(n);
  var semi = 0;
  var anyAlpha = false;
  for (var i = 0; i < n; i++) {
    final a = rgba[i * 4 + 3];
    if (a < 255) anyAlpha = true;
    if (a < 128) mask[i] = 1;
    if (a > 8 && a < 248) semi++;
  }
  if (!anyAlpha) {
    checks.add(const FrameCheck(CheckLevel.bad, 'File không có vùng trong suốt (ô ảnh phải để trong suốt)'));
    return FrameScan(pngSize: pngSize, card: card, slots: const [], checks: checks);
  }

  // Connected transparent areas (4-neighbour flood fill with an explicit stack).
  final holes = <Rect>[];
  var edgeAreas = 0, oddAreas = 0;
  final minArea = 0.005 * n;
  final stack = Int32List(n);
  for (var start = 0; start < n; start++) {
    if (mask[start] != 1) continue;
    var top = 0;
    stack[top++] = start;
    mask[start] = 2;
    var count = 0;
    var x0 = w, y0 = h, x1 = -1, y1 = -1;
    while (top > 0) {
      final i = stack[--top];
      count++;
      final x = i % w, y = i ~/ w;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
      if (x > 0 && mask[i - 1] == 1) {
        mask[i - 1] = 2;
        stack[top++] = i - 1;
      }
      if (x < w - 1 && mask[i + 1] == 1) {
        mask[i + 1] = 2;
        stack[top++] = i + 1;
      }
      if (y > 0 && mask[i - w] == 1) {
        mask[i - w] = 2;
        stack[top++] = i - w;
      }
      if (y < h - 1 && mask[i + w] == 1) {
        mask[i + w] = 2;
        stack[top++] = i + w;
      }
    }
    if (count < minArea) continue; // specks, anti-aliasing
    final box = Rect.fromLTRB(x0.toDouble(), y0.toDouble(), x1 + 1.0, y1 + 1.0);
    if (x0 == 0 || y0 == 0 || x1 == w - 1 || y1 == h - 1) {
      edgeAreas++;
    } else if (count / (box.width * box.height) < 0.85) {
      oddAreas++;
    } else {
      holes.add(box);
    }
  }

  if (holes.isEmpty) {
    checks.add(const FrameCheck(CheckLevel.bad, 'Không tìm thấy ô trong suốt hình chữ nhật nào'));
  } else if (holes.length > 6) {
    checks.add(FrameCheck(CheckLevel.bad, 'Tìm thấy ${holes.length} ô, tối đa 6 ô'));
  } else {
    checks.add(FrameCheck(CheckLevel.ok, 'Tìm thấy ${holes.length} ô trong suốt'));
  }
  if (edgeAreas > 0) {
    checks.add(FrameCheck(CheckLevel.warn, 'Có $edgeAreas vùng trong suốt sát mép giấy – đã bỏ qua'));
  }
  if (oddAreas > 0) {
    checks.add(FrameCheck(CheckLevel.warn, 'Có $oddAreas vùng trong suốt không phải hình chữ nhật – đã bỏ qua'));
  }

  // Reading order: rows (centres within half a window's height), then left to right.
  final slots = _readingOrder(holes)
      .map((r) => Rect.fromLTRB(
            (r.left * scale).roundToDouble(),
            (r.top * scale).roundToDouble(),
            (r.right * scale).roundToDouble(),
            (r.bottom * scale).roundToDouble(),
          ))
      .toList();
  if (slots.length > 1) {
    final a = slots.map((r) => r.width / r.height).toList();
    final spread = a.reduce(math.max) / a.reduce(math.min);
    if (spread > 1.03) {
      checks.add(const FrameCheck(CheckLevel.warn, 'Các ô khác tỉ lệ: ảnh được cắt theo ô đầu tiên rồi phủ vừa từng ô'));
    }
  }
  if (slots.isNotEmpty) {
    checks.add(
      FrameCheck(CheckLevel.ok, 'Ô ${ratioLabel(slots.first.size.aspectRatio)}: ảnh chụp được cắt vừa ô'),
    );
  }

  // QR: a plain, opaque square clear of the windows, as near the bottom-right corner as possible.
  final qr = slots.isEmpty ? null : _findQr(rgba, w, h, scale, card, slots);
  String? corner;
  if (qr != null) {
    corner = cornerLabel(qr, card);
    checks.add(FrameCheck(CheckLevel.ok, 'Chỗ QR trống ở $corner'));
  } else if (slots.isNotEmpty) {
    checks.add(const FrameCheck(CheckLevel.warn, 'Không thấy chỗ nền trơn cho QR: bấm "Chọn lại" rồi kéo QR'));
  }
  if (semi > 0) checks.add(const FrameCheck(CheckLevel.warn, 'Viền có điểm bán trong suốt – đã bỏ qua'));

  return FrameScan(pngSize: pngSize, card: card, slots: slots, checks: checks, autoQr: qr, qrCorner: corner);
}

/// [scanFrame] for `compute`.
FrameScan scanFrameArgs((Uint8List, int, int) a) => scanFrame(a.$1, a.$2, a.$3);

List<Rect> _readingOrder(List<Rect> holes) {
  if (holes.isEmpty) return holes;
  final minH = holes.map((r) => r.height).reduce(math.min);
  final byY = [...holes]..sort((a, b) => a.center.dy.compareTo(b.center.dy));
  final rows = <List<Rect>>[];
  for (final r in byY) {
    if (rows.isNotEmpty && (r.center.dy - rows.last.first.center.dy).abs() < minH / 2) {
      rows.last.add(r);
    } else {
      rows.add([r]);
    }
  }
  return [
    for (final row in rows) ...(row..sort((a, b) => a.left.compareTo(b.left))),
  ];
}

/// "16:9", "3:2", "4:3", "1:1", "2:3" … or "1,62:1".
String ratioLabel(double r) {
  const known = [(16, 9), (3, 2), (4, 3), (5, 4), (1, 1), (4, 5), (3, 4), (2, 3), (9, 16)];
  for (final (a, b) in known) {
    if ((r - a / b).abs() / (a / b) < 0.03) return '$a:$b';
  }
  return '${r.toStringAsFixed(2).replaceAll('.', ',')}:1';
}

/// "góc phải dưới", "góc trái dưới", "phía dưới" …
String cornerLabel(Rect qr, Size card) {
  final c = qr.center;
  final h = c.dx < card.width / 3 ? 'trái' : (c.dx > card.width * 2 / 3 ? 'phải' : null);
  final v = c.dy < card.height / 3 ? 'trên' : (c.dy > card.height * 2 / 3 ? 'dưới' : null);
  if (h != null && v != null) return 'góc $h $v';
  if (v != null) return 'phía $v';
  if (h != null) return 'bên $h';
  return 'giữa tấm';
}

/// A 180-unit square (plus a quiet margin) that is opaque and plain, off the windows and the paper
/// edge. First where the built-in cards put it (flush with the windows' right edge, then their left
/// edge, 52 above the bottom), else the plain spot nearest the bottom-right corner. Candidates come
/// from summed-area tables on a 4 px grid; each is then checked pixel by pixel, so a thin line or an
/// ornament in the way is seen.
Rect? _findQr(Uint8List rgba, int w, int h, double scale, Size card, List<Rect> slots) {
  const quiet = 12.0, edge = 40.0;

  /// Every 2nd pixel under [qr] + quiet zone: opaque, and no channel more than 28 off the mean.
  bool strict(Rect qr) {
    final outer = qr.inflate(quiet);
    if (outer.left < edge || outer.top < edge || outer.right > card.width - edge || outer.bottom > card.height - edge) {
      return false;
    }
    if (slots.any((s) => s.inflate(quiet).overlaps(outer))) return false;
    final x0 = (outer.left / scale).floor(), x1 = (outer.right / scale).ceil().clamp(0, w);
    final y0 = (outer.top / scale).floor(), y1 = (outer.bottom / scale).ceil().clamp(0, h);
    final sum = [0.0, 0.0, 0.0];
    var n = 0;
    for (var y = y0; y < y1; y += 2) {
      for (var x = x0; x < x1; x += 2) {
        final i = (y * w + x) * 4;
        if (rgba[i + 3] < 250) return false;
        for (var c = 0; c < 3; c++) {
          sum[c] += rgba[i + c];
        }
        n++;
      }
    }
    if (n == 0) return false;
    final mean = [for (final v in sum) v / n];
    for (var y = y0; y < y1; y += 2) {
      for (var x = x0; x < x1; x += 2) {
        final i = (y * w + x) * 4;
        for (var c = 0; c < 3; c++) {
          if ((rgba[i + c] - mean[c]).abs() > 28) return false;
        }
      }
    }
    return true;
  }

  // Where the built-in cards have it.
  final right = slots.map((r) => r.right).reduce(math.max);
  final left = slots.map((r) => r.left).reduce(math.min);
  final top = card.height - 52 - qrSide;
  for (final x in [right - qrSide, left]) {
    final r = Rect.fromLTWH(x, top, qrSide, qrSide);
    if (strict(r)) return r;
  }

  // Elsewhere: plain squares on a coarse grid, nearest the bottom-right corner first.
  const cell = 4;
  final gw = w ~/ cell, gh = h ~/ cell;
  final stride = gw + 1;
  final sum = List.generate(3, (_) => Float64List(stride * (gh + 1)));
  final sq = List.generate(3, (_) => Float64List(stride * (gh + 1)));
  final clear = Int32List(stride * (gh + 1));
  for (var gy = 0; gy < gh; gy++) {
    for (var gx = 0; gx < gw; gx++) {
      final i = ((gy * cell + cell ~/ 2) * w + gx * cell + cell ~/ 2) * 4;
      final o = (gy + 1) * stride + gx + 1;
      for (var c = 0; c < 3; c++) {
        final v = rgba[i + c].toDouble();
        sum[c][o] = v + sum[c][o - 1] + sum[c][o - stride] - sum[c][o - stride - 1];
        sq[c][o] = v * v + sq[c][o - 1] + sq[c][o - stride] - sq[c][o - stride - 1];
      }
      final see = rgba[i + 3] < 250 ? 1 : 0;
      clear[o] = see + clear[o - 1] + clear[o - stride] - clear[o - stride - 1];
    }
  }
  double area(Float64List t, int x0, int y0, int x1, int y1) =>
      t[y1 * stride + x1] - t[y0 * stride + x1] - t[y1 * stride + x0] + t[y0 * stride + x0];
  int areaI(Int32List t, int x0, int y0, int x1, int y1) =>
      t[y1 * stride + x1] - t[y0 * stride + x1] - t[y1 * stride + x0] + t[y0 * stride + x0];

  final side = qrSide + 2 * quiet;
  final sideG = (side / scale / cell).ceil();
  final edgeG = (edge / scale / cell).ceil();
  final found = <(double, Rect)>[];
  for (var gy = edgeG; gy + sideG <= gh - edgeG; gy += 2) {
    for (var gx = edgeG; gx + sideG <= gw - edgeG; gx += 2) {
      final outer = Rect.fromLTWH(gx * cell * scale, gy * cell * scale, side, side);
      if (slots.any((s) => s.inflate(quiet).overlaps(outer))) continue;
      final x1 = gx + sideG, y1 = gy + sideG;
      if (areaI(clear, gx, gy, x1, y1) > 0) continue;
      final k = (sideG * sideG).toDouble();
      var plain = true;
      for (var c = 0; c < 3 && plain; c++) {
        final mean = area(sum[c], gx, gy, x1, y1) / k;
        if (area(sq[c], gx, gy, x1, y1) / k - mean * mean > 14 * 14) plain = false;
      }
      if (!plain) continue;
      final qr = outer.deflate(quiet);
      found.add(((card.width - qr.right) + (card.height - qr.bottom), qr));
    }
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  for (final (_, qr) in found.take(400)) {
    final r = Rect.fromLTWH(qr.left.roundToDouble(), qr.top.roundToDouble(), qrSide, qrSide);
    if (strict(r)) return r;
  }
  return null;
}
