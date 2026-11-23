import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:qr/qr.dart';

import '../config.dart';
import '../ui/tokens.dart';

/// 100×148 mm postcard as the printer gets it: portrait, ~300 dpi.
const Size kPrintSize = Size(1200, 1776);

/// The frames on the studio menu. Every one fills one postcard; [cut4] is drawn
/// landscape and turned for the printer.
enum BoothLayout {
  /// 2 photos stacked.
  cut2('2 Cut', 2),

  /// 3 photos stacked, dark band with the title on the left.
  cut3('3 Cut', 3),

  /// 2×2, landscape card.
  cut4('4 Cut', 4),

  /// 2 columns × 3 rows.
  cut6('6 Cut', 6);

  const BoothLayout(this.label, this.picks);
  final String label;

  /// Photos the guest picks.
  final int picks;

  /// Shots taken: always 2 spare to choose from, at least [SHOTS].
  int get shots => math.max(SHOTS, picks + 2);

  bool get landscape => this == cut4;

  /// The card as designed (and as shown on the download page).
  Size get size => landscape ? Size(kPrintSize.height, kPrintSize.width) : kPrintSize;

  /// Width / height of one photo window.
  double get cellAspect => PrintGeometry.of(this).cells.first.size.aspectRatio;
}

/// Where the title and date go. [vertical]: read bottom to top (3 Cut band).
class Caption {
  const Caption(this.rect, {this.vertical = false, this.onDark = false});
  final Rect rect;
  final bool vertical;
  final bool onDark;
}

/// Photo windows, captions, QR squares and dark bands, in [BoothLayout.size] pixels.
class PrintGeometry {
  PrintGeometry._({required this.cells, required this.captions, required this.qrs, this.bands = const []});

  final List<Rect> cells;
  final List<Caption> captions;
  final List<Rect> qrs;
  final List<Rect> bands;

  factory PrintGeometry.of(BoothLayout layout) {
    switch (layout) {
      case BoothLayout.cut2:
        const m = 60.0, top = 56.0, w = 1080.0, h = 720.0, gap = 30.0, qr = 170.0;
        final footTop = (top + 2 * h + gap + kPrintSize.height) / 2 - qr / 2;
        return PrintGeometry._(
          cells: [for (var i = 0; i < 2; i++) Rect.fromLTWH(m, top + i * (h + gap), w, h)],
          captions: [Caption(Rect.fromLTWH(m, footTop, w - qr - 24, qr))],
          qrs: [Rect.fromLTWH(m + w - qr, footTop, qr, qr)],
        );

      case BoothLayout.cut3:
        // Dark band on the left: title read bottom to top, QR at its foot.
        const band = 250.0, x = band + 40, w = 870.0, h = 544.0, gap = 26.0, qr = 190.0;
        const top = (1776 - (3 * h + 2 * gap)) / 2;
        return PrintGeometry._(
          cells: [for (var i = 0; i < 3; i++) Rect.fromLTWH(x, top + i * (h + gap), w, h)],
          bands: [const Rect.fromLTWH(0, 0, band, 1776)],
          qrs: [const Rect.fromLTWH((band - qr) / 2, 1776 - top - qr, qr, qr)],
          captions: [
            const Caption(Rect.fromLTWH(20, top, band - 40, 1776 - 2 * top - qr - 30), vertical: true, onDark: true),
          ],
        );

      case BoothLayout.cut4:
        // Landscape 1776×1200: 2×2 photos at 16:9 (the camera's own shape), caption + QR below.
        const m = 48.0, gap = 24.0, w = 828.0, h = 466.0, qr = 160.0;
        final size = layout.size;
        final footTop = (m + 2 * h + gap + size.height) / 2 - qr / 2;
        return PrintGeometry._(
          cells: [for (var i = 0; i < 4; i++) Rect.fromLTWH(m + (i % 2) * (w + gap), m + (i ~/ 2) * (h + gap), w, h)],
          captions: [Caption(Rect.fromLTWH(m, footTop, size.width - 2 * m - qr - 24, qr))],
          qrs: [Rect.fromLTWH(size.width - m - qr, footTop, qr, qr)],
        );

      case BoothLayout.cut6:
        const m = 48.0, gap = 24.0, w = 540.0, h = 480.0, qr = 170.0;
        final footTop = (m + 3 * h + 2 * gap + kPrintSize.height) / 2 - qr / 2;
        return PrintGeometry._(
          cells: [for (var i = 0; i < 6; i++) Rect.fromLTWH(m + (i % 2) * (w + gap), m + (i ~/ 2) * (h + gap), w, h)],
          captions: [Caption(Rect.fromLTWH(m, footTop, kPrintSize.width - 2 * m - qr - 24, qr))],
          qrs: [Rect.fromLTWH(kPrintSize.width - m - qr, footTop, qr, qr)],
        );
    }
  }
}

/// Everything on one card. [photos] in print order ([BoothLayout.picks] of them); null draws an
/// empty numbered window.
class PrintSpec {
  const PrintSpec({
    required this.layout,
    required this.photos,
    required this.title,
    required this.dateLine,
    this.qrUrl,
    this.qrSlot = false,
  });

  final BoothLayout layout;
  final List<ui.Image?> photos;
  final String title;
  final String dateLine;

  /// The link printed as a QR. Null on previews: the QR square stays blank paper
  /// (or shows a "QR" mark when [qrSlot]).
  final String? qrUrl;
  final bool qrSlot;
}

/// Paints a card at any size (scaled from [BoothLayout.size]).
class PrintPainter extends CustomPainter {
  PrintPainter(this.spec);
  final PrintSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final full = spec.layout.size;
    canvas.save();
    canvas.scale(size.width / full.width, size.height / full.height);
    paintPrint(canvas, spec);
    canvas.restore();
  }

  @override
  bool shouldRepaint(PrintPainter old) =>
      old.spec.layout != spec.layout ||
      old.spec.title != spec.title ||
      old.spec.dateLine != spec.dateLine ||
      old.spec.qrUrl != spec.qrUrl ||
      old.spec.qrSlot != spec.qrSlot ||
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

/// [card] as the printer takes it: portrait, a landscape card turned a quarter clockwise.
Future<ui.Image> forPrinter(ui.Image card) {
  final rec = ui.PictureRecorder();
  Canvas(rec)
    ..translate(card.height.toDouble(), 0)
    ..rotate(math.pi / 2)
    ..drawImage(card, Offset.zero, Paint()..filterQuality = FilterQuality.high);
  return rec.endRecording().toImage(card.height, card.width);
}

void paintPrint(Canvas canvas, PrintSpec spec) {
  final geo = PrintGeometry.of(spec.layout);
  canvas.drawRect(Offset.zero & spec.layout.size, Paint()..color = Palette.printPaper);
  for (final b in geo.bands) {
    canvas.drawRect(b, Paint()..color = Palette.coffee);
  }

  final n = spec.layout.picks;
  for (var i = 0; i < geo.cells.length; i++) {
    final cell = geo.cells[i];
    final img = spec.photos.length > i % n ? spec.photos[i % n] : null;
    if (img == null) {
      canvas.drawRect(cell, Paint()..color = Palette.paperDeep);
      _text(
        canvas,
        '${i % n + 1}',
        cell,
        const TextStyle(fontFamily: Fonts.mono, fontSize: 64, color: Palette.kraft),
        center: true,
      );
    } else {
      _cover(canvas, img, cell);
    }
  }

  for (final c in geo.captions) {
    _caption(canvas, c, spec.title, spec.dateLine);
  }

  for (final q in geo.qrs) {
    if (spec.qrUrl != null) {
      paintQr(canvas, spec.qrUrl!, q);
    } else if (spec.qrSlot) {
      canvas.drawRect(q, Paint()..color = Palette.paperDeep);
      _text(canvas, 'QR', q, const TextStyle(fontFamily: Fonts.mono, fontSize: 36, color: Palette.kraft), center: true);
    }
  }
}

/// Title (up to 2 lines) over the date line, sized from the caption's height.
void _caption(Canvas canvas, Caption c, String title, String dateLine) {
  canvas.save();
  var box = c.rect;
  if (c.vertical) {
    // Turn so the text runs bottom to top along the band.
    canvas.translate(box.left, box.bottom);
    canvas.rotate(-math.pi / 2);
    box = Rect.fromLTWH(0, 0, c.rect.height, c.rect.width);
  }
  final h = box.height;
  _text(
    canvas,
    title,
    Rect.fromLTWH(box.left, box.top, box.width, h * 0.68),
    TextStyle(
      fontFamily: Fonts.hand,
      fontSize: h * 0.3,
      color: c.onDark ? Palette.paper : Palette.coffee,
      height: 1.05,
    ),
    maxLines: 2,
  );
  _text(
    canvas,
    dateLine,
    Rect.fromLTWH(box.left, box.top + h * 0.72, box.width, h * 0.28),
    TextStyle(
      fontFamily: Fonts.mono,
      fontSize: h * 0.14,
      color: c.onDark ? Palette.mustard : Palette.kraftInk,
      letterSpacing: 1,
    ),
  );
  canvas.restore();
}

/// [img] fills [rect], centre-cropped.
void _cover(Canvas canvas, ui.Image img, Rect rect) {
  final scale = math.max(rect.width / img.width, rect.height / img.height);
  final sw = rect.width / scale, sh = rect.height / scale;
  final src = Rect.fromLTWH((img.width - sw) / 2, (img.height - sh) / 2, sw, sh);
  canvas.drawImageRect(img, src, rect, Paint()..filterQuality = FilterQuality.high);
}

void _text(Canvas canvas, String text, Rect box, TextStyle style, {int maxLines = 1, bool center = false}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: maxLines,
    ellipsis: '…',
    textAlign: center ? TextAlign.center : TextAlign.left,
  )..layout(maxWidth: box.width);
  final dx = center ? box.left + (box.width - tp.width) / 2 : box.left;
  final dy = center ? box.top + (box.height - tp.height) / 2 : box.top;
  tp.paint(canvas, Offset(dx, dy));
  tp.dispose();
}

/// Charcoal modules on white with a two-module quiet zone (Lensly QrPainter).
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
  canvas.drawPath(path, Paint()..color = Palette.charcoal);
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
