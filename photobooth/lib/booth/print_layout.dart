import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:qr/qr.dart';

import '../config.dart';
import '../ui/lux.dart';

/// 100×148 mm postcard as the printer gets it: portrait, ~300 dpi (1 mm ≈ 12 px).
const Size kPrintSize = Size(1200, 1776);

/// The frames (LPE Sum Up design, "Tấm in · postcard 100 × 148 mm"). 4 Cut is drawn
/// landscape and turned for the printer.
enum BoothLayout {
  /// 2 photos stacked, ivory.
  cut2('2 Cut', 2, '2 ảnh · khổ dọc'),

  /// 3 photos, navy band with the title on the left.
  cut3('3 Cut', 3, '3 ảnh · dải tiêu đề'),

  /// 2×2, landscape, black.
  cut4('4 Cut', 4, '4 ảnh · khổ ngang'),

  /// 2 columns × 3 rows, ivory.
  cut6('6 Cut', 6, '6 ảnh · 2 cột');

  const BoothLayout(this.label, this.picks, this.hint);
  final String label;

  /// Photos the guest picks.
  final int picks;

  /// Under the name on the frame picker.
  final String hint;

  /// Shots taken: always 2 spare to choose from, at least [SHOTS].
  int get shots => math.max(SHOTS, picks + 2);

  bool get landscape => this == cut4;

  /// Black card with light-gold ink (the others are ivory with dark-gold ink).
  bool get dark => this == cut4;

  /// The card as designed (and as shown on the download page).
  Size get size => landscape ? Size(kPrintSize.height, kPrintSize.width) : kPrintSize;

  /// Width / height of one photo window.
  double get cellAspect => PrintGeometry.of(this).cells.first.size.aspectRatio;
}

/// Photo windows, the QR square and where the title block goes, in [BoothLayout.size] pixels.
class PrintGeometry {
  const PrintGeometry._({required this.cells, required this.qr, required this.title, this.band});

  final List<Rect> cells;
  final Rect qr;

  /// Title block (3 Cut: centred in the band, turned −90°).
  final Rect title;

  /// 3 Cut's navy band.
  final Rect? band;

  factory PrintGeometry.of(BoothLayout layout) => switch (layout) {
    BoothLayout.cut2 => const PrintGeometry._(
      cells: [Rect.fromLTWH(72, 72, 1056, 704), Rect.fromLTWH(72, 800, 1056, 704)],
      qr: Rect.fromLTWH(948, 1544, 180, 180),
      title: Rect.fromLTWH(72, 1532, 830, 200),
    ),
    BoothLayout.cut3 => const PrintGeometry._(
      cells: [Rect.fromLTWH(300, 87, 828, 518), Rect.fromLTWH(300, 629, 828, 518), Rect.fromLTWH(300, 1171, 828, 518)],
      qr: Rect.fromLTWH(40, 1544, 180, 180),
      // A 1380 × 220 box centred at (130, 790), turned.
      title: Rect.fromLTWH(130 - 690, 790 - 110, 1380, 220),
      band: Rect.fromLTWH(0, 0, 260, 1776),
    ),
    BoothLayout.cut4 => const PrintGeometry._(
      cells: [
        Rect.fromLTWH(116, 56, 760, 428),
        Rect.fromLTWH(900, 56, 760, 428),
        Rect.fromLTWH(116, 508, 760, 428),
        Rect.fromLTWH(900, 508, 760, 428),
      ],
      qr: Rect.fromLTWH(1480, 968, 180, 180),
      title: Rect.fromLTWH(116, 962, 1300, 200),
    ),
    BoothLayout.cut6 => const PrintGeometry._(
      cells: [
        Rect.fromLTWH(72, 72, 516, 459),
        Rect.fromLTWH(612, 72, 516, 459),
        Rect.fromLTWH(72, 555, 516, 459),
        Rect.fromLTWH(612, 555, 516, 459),
        Rect.fromLTWH(72, 1038, 516, 459),
        Rect.fromLTWH(612, 1038, 516, 459),
      ],
      qr: Rect.fromLTWH(948, 1544, 180, 180),
      title: Rect.fromLTWH(72, 1532, 830, 200),
    ),
  };
}

/// Everything on one card. [photos] in print order ([BoothLayout.picks] of them); null draws an
/// empty numbered window.
class PrintSpec {
  const PrintSpec({
    required this.layout,
    required this.photos,
    required this.title,
    required this.dateLine,
    this.subtitle = 'Tiệc tổng kết cuối năm',
    this.qrUrl,
    this.qrSlot = false,
    this.scanHint = 'Quét mã để tải ảnh & video Live →',
  });

  final BoothLayout layout;
  final List<ui.Image?> photos;

  /// "LPE Sum Up": the first word bold, the rest italic.
  final String title;
  final String dateLine;
  final String subtitle;

  /// The link printed as a QR. Null on previews: the QR square stays empty
  /// (or shows a "QR" mark when [qrSlot]).
  final String? qrUrl;
  final bool qrSlot;

  /// Under the date, in the guest's language.
  final String scanHint;
}

/// Paints a card at any size (scaled from [BoothLayout.size]).
class PrintPainter extends CustomPainter {
  PrintPainter(this.spec);
  final PrintSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final full = spec.layout.size;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / full.width, size.height / full.height);
    paintPrint(canvas, spec);
    canvas.restore();
  }

  @override
  bool shouldRepaint(PrintPainter old) =>
      old.spec.layout != spec.layout ||
      old.spec.title != spec.title ||
      old.spec.dateLine != spec.dateLine ||
      old.spec.subtitle != spec.subtitle ||
      old.spec.qrUrl != spec.qrUrl ||
      old.spec.qrSlot != spec.qrSlot ||
      old.spec.scanHint != spec.scanHint ||
      !_sameList(old.spec.photos, spec.photos);

  static bool _sameList(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }
}

/// The card as an image of [BoothLayout.size] (what is uploaded and shown on the thank-you screen).
Future<ui.Image> renderPrint(PrintSpec spec) {
  final rec = ui.PictureRecorder();
  paintPrint(Canvas(rec), spec);
  final s = spec.layout.size;
  return rec.endRecording().toImage(s.width.round(), s.height.round());
}

/// [card] as the printer takes it: always portrait (a landscape card turned a quarter,
/// clockwise unless [counterClockwise]), [brighten] lifted (0.1 = +10 %: dye-sub prints run dark).
Future<ui.Image> forPrinter(ui.Image card, {bool counterClockwise = false, double brighten = 0}) {
  final landscape = card.width > card.height;
  final w = landscape ? card.height : card.width, h = landscape ? card.width : card.height;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  if (landscape) {
    if (counterClockwise) {
      canvas
        ..translate(0, h.toDouble())
        ..rotate(-math.pi / 2);
    } else {
      canvas
        ..translate(w.toDouble(), 0)
        ..rotate(math.pi / 2);
    }
  }
  final k = 1 + brighten, add = 255 * brighten * 0.5;
  canvas.drawImage(
    card,
    Offset.zero,
    Paint()
      ..filterQuality = FilterQuality.high
      ..colorFilter = brighten == 0
          ? null
          : ColorFilter.matrix([k, 0, 0, 0, add, 0, k, 0, 0, add, 0, 0, k, 0, add, 0, 0, 0, 1, 0]),
  );
  return rec.endRecording().toImage(w, h);
}

const _ivoryFrame = Color(0xFFC9A35C);
const _darkFrame = Color(0xFFD4AF6A);
const _ivoryInk = Color(0xFF3B3326);

void paintPrint(Canvas canvas, PrintSpec spec) {
  final layout = spec.layout;
  final size = layout.size;
  final geo = PrintGeometry.of(layout);
  final card = Offset.zero & size;
  final frame = layout.dark ? _darkFrame : _ivoryFrame;
  final ink = layout.dark ? Lux.ivory : _ivoryInk;

  // Paper: ivory, or night with a navy glow from the top.
  canvas.drawRect(
    card,
    Paint()
      ..shader = layout.dark
          ? const RadialGradient(
              center: Alignment(0, -1),
              radius: 1.2,
              colors: [Color(0xFF1A1F3A), Lux.night],
              stops: [0, 0.62],
            ).createShader(card)
          : const LinearGradient(
              begin: Alignment(-0.34, -1),
              end: Alignment(0.34, 1),
              colors: [Color(0xFFFBF7EE), Color(0xFFF8F3E8), Color(0xFFF1E8D6)],
            ).createShader(card),
  );
  final band = geo.band;
  if (band != null) {
    canvas.drawRect(
      band,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Lux.navy, Lux.night],
        ).createShader(band),
    );
    final edge = Rect.fromLTWH(band.right, 0, 3, size.height);
    canvas.drawRect(
      edge,
      Paint()..shader = const LinearGradient(colors: Lux.metal, stops: Lux.metalStops).createShader(edge),
    );
  }

  // Thin frame 22 px in (decoration only, may be trimmed) and the four art-deco corners.
  canvas.drawRect(
    card.deflate(23),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = frame.withValues(alpha: 0.55),
  );
  _corners(canvas, size, frame);

  // Photos, each with a 2 px gold outline 5 px out.
  for (var i = 0; i < geo.cells.length; i++) {
    final cell = geo.cells[i];
    canvas.drawRect(
      cell.inflate(6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = frame,
    );
    canvas.drawRect(cell, Paint()..color = const Color(0xFF17141C));
    final img = spec.photos.length > i ? spec.photos[i] : null;
    if (img == null) {
      _text(
        canvas,
        '${i + 1}',
        cell,
        LuxFonts.serif(size: 120, weight: FontWeight.w700, color: frame.withValues(alpha: 0.5)),
        center: true,
      );
    } else {
      _cover(canvas, img, cell);
    }
  }

  _titleBlock(canvas, spec, geo.title, ink, rotated: band != null, onDark: layout.dark || band != null);

  if (spec.qrUrl != null) {
    paintQr(canvas, spec.qrUrl!, geo.qr);
  } else if (spec.qrSlot) {
    canvas.drawRect(geo.qr, Paint()..color = const Color(0xFFFFFFFF));
    _text(canvas, 'QR', geo.qr, LuxFonts.sans(size: 40, weight: FontWeight.w600, color: frame), center: true);
  }
}

/// "LPE *Sum Up*" in gold, then "DATE · SUBTITLE", then the scan hint (not on 3 Cut).
void _titleBlock(Canvas canvas, PrintSpec spec, Rect box, Color ink, {required bool rotated, required bool onDark}) {
  final words = spec.title.trim().split(RegExp(r'\s+'));
  final head = words.first;
  final tail = words.length > 1 ? ' ${words.skip(1).join(' ')}' : '';
  final big = rotated ? 128.0 : (spec.layout.landscape ? 84.0 : 96.0);
  final line2 = '${spec.dateLine} · ${spec.subtitle}'.toUpperCase();

  canvas.save();
  if (rotated) {
    canvas.translate(box.center.dx, box.center.dy);
    canvas.rotate(-math.pi / 2);
    canvas.translate(-box.width / 2, -box.height / 2);
  } else {
    canvas.translate(box.left, box.top);
  }
  final w = box.width;

  TextSpan title(Paint? gold) => TextSpan(
    style: LuxFonts.serif(
      size: big,
      weight: FontWeight.w700,
      height: 1.05,
      spacing: big * 0.01,
    ).copyWith(foreground: gold),
    children: [
      TextSpan(text: head),
      TextSpan(
        text: tail,
        style: LuxFonts.serif(
          size: big,
          weight: FontWeight.w400,
          italic: true,
          height: 1.05,
        ).copyWith(foreground: gold),
      ),
    ],
  );
  // Measure first, then paint with the gold spread over exactly the text.
  final measure = TextPainter(textDirection: TextDirection.ltr, maxLines: 1, ellipsis: '…', text: title(null))
    ..layout(maxWidth: w);
  final gold = Paint()
    ..shader = LinearGradient(
      colors: onDark ? Lux.metal : Lux.ink,
      stops: onDark ? Lux.metalStops : null,
    ).createShader(Rect.fromLTWH(0, 0, measure.width, measure.height));
  final goldTitle = TextPainter(textDirection: TextDirection.ltr, maxLines: 1, ellipsis: '…', text: title(gold))
    ..layout(maxWidth: w);
  measure.dispose();

  final subSize = rotated ? 26.0 : 24.0;
  final sub = TextPainter(
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
    text: TextSpan(
      text: line2,
      style: LuxFonts.sans(
        size: subSize,
        color: rotated ? Lux.ivoryA(0.9) : ink,
        spacing: subSize * (rotated ? 0.14 : 0.1),
      ),
    ),
  )..layout(maxWidth: w);

  if (rotated) {
    // Centred in the band, title over the date (18 px gap).
    final total = goldTitle.height + 18 + sub.height;
    final top = (box.height - total) / 2;
    goldTitle.paint(canvas, Offset((w - goldTitle.width) / 2, top));
    sub.paint(canvas, Offset((w - sub.width) / 2, top + goldTitle.height + 18));
  } else {
    goldTitle.paint(canvas, Offset.zero);
    final y2 = goldTitle.height + 14;
    sub.paint(canvas, Offset(0, y2));
    final hint = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
      text: TextSpan(
        text: spec.scanHint,
        style: LuxFonts.sans(size: 22, color: ink.withValues(alpha: 0.72)),
      ),
    )..layout(maxWidth: w);
    hint.paint(canvas, Offset(0, y2 + sub.height + 10));
    hint.dispose();
  }
  goldTitle.dispose();
  sub.dispose();
  canvas.restore();
}

/// The design's corner ornament (a 120-unit SVG drawn 80 px), mirrored into each corner.
void _corners(Canvas canvas, Size size, Color color) {
  const s = 80.0, inset = 22.0;
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..color = color;
  final fill = Paint()..color = color;
  for (final (fx, fy) in [(1.0, 1.0), (-1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)]) {
    canvas.save();
    canvas.translate(fx > 0 ? inset : size.width - inset, fy > 0 ? inset : size.height - inset);
    canvas.scale(fx * s / 120, fy * s / 120);
    canvas.drawPath(
      Path()
        ..moveTo(1, 119)
        ..lineTo(1, 1)
        ..lineTo(119, 1)
        ..moveTo(10, 86)
        ..lineTo(10, 10)
        ..lineTo(86, 10)
        ..moveTo(10, 46)
        ..arcToPoint(const Offset(46, 10), radius: const Radius.circular(36))
        ..moveTo(10, 31)
        ..arcToPoint(const Offset(31, 10), radius: const Radius.circular(21))
        ..moveTo(10, 10)
        ..lineTo(30, 30)
        ..moveTo(1, 64)
        ..lineTo(7, 64)
        ..moveTo(64, 1)
        ..lineTo(64, 7),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(36, 28)
        ..lineTo(42, 34)
        ..lineTo(36, 40)
        ..lineTo(30, 34)
        ..close(),
      fill,
    );
    canvas.restore();
  }
}

/// [img] fills [rect], centre-cropped.
void _cover(Canvas canvas, ui.Image img, Rect rect) {
  final scale = math.max(rect.width / img.width, rect.height / img.height);
  final sw = rect.width / scale, sh = rect.height / scale;
  final src = Rect.fromLTWH((img.width - sw) / 2, (img.height - sh) / 2, sw, sh);
  canvas.drawImageRect(img, src, rect, Paint()..filterQuality = FilterQuality.high);
}

void _text(Canvas canvas, String text, Rect box, TextStyle style, {bool center = false}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    textAlign: center ? TextAlign.center : TextAlign.left,
  )..layout(maxWidth: box.width);
  final dx = center ? box.left + (box.width - tp.width) / 2 : box.left;
  final dy = center ? box.top + (box.height - tp.height) / 2 : box.top;
  tp.paint(canvas, Offset(dx, dy));
  tp.dispose();
}

/// Dark modules on white with a two-module quiet zone (error correction M).
void paintQr(Canvas canvas, String data, Rect rect) {
  final qr = QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M));
  final n = qr.moduleCount;
  final m = rect.shortestSide / (n + 4);
  canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
  final path = Path();
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      if (qr.isDark(y, x)) {
        path.addRect(Rect.fromLTWH(rect.left + (x + 2) * m, rect.top + (y + 2) * m, m + 0.3, m + 0.3));
      }
    }
  }
  canvas.drawPath(path, Paint()..color = const Color(0xFF16141C));
}

/// A QR code as a widget painter (thank-you screen).
class QrPainter extends CustomPainter {
  QrPainter(this.data);
  final String data;

  @override
  void paint(Canvas canvas, Size size) => paintQr(canvas, data, Offset.zero & size);

  @override
  bool shouldRepaint(QrPainter old) => old.data != data;
}
