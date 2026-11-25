import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../booth/booth.dart';
import '../../booth/frame_detect.dart';
import '../../booth/frames.dart';
import '../../booth/print_layout.dart';
import '../../ui/lux.dart';
import 'kit.dart';

/// 7d · Cài đặt – Thêm / sửa khung: a PNG with transparent windows; the windows are found by
/// themselves, the QR goes on a plain spot (or where the staff drags it).
class FrameEditPage extends StatefulWidget {
  const FrameEditPage({super.key, required this.booth, this.frame, required this.onDone});
  final Booth booth;

  /// The custom frame being edited; null for a new one.
  final BoothFrame? frame;
  final VoidCallback onDone;

  @override
  State<FrameEditPage> createState() => _FrameEditPageState();
}

class _FrameEditPageState extends State<FrameEditPage> {
  static const _files = MethodChannel('booth/files');

  late final _name = TextEditingController(text: widget.frame?.name ?? '');
  String? _fileName;
  Uint8List? _png;
  ui.Image? _image;
  FrameScan? _scan;
  bool _busy = false;
  bool _sample = false;
  bool _manualQr = false;
  Rect? _qr;
  ui.Image? _sampleCard;
  List<ui.Image>? _samplePhotos;

  Booth get b => widget.booth;
  bool get _editing => widget.frame != null;

  @override
  void initState() {
    super.initState();
    final f = widget.frame;
    final file = f == null ? null : b.frames.pngOf(f);
    if (f != null && file != null && file.existsSync()) {
      // Editing: the saved QR stays where it is unless the staff asks for "Tự nhận".
      _manualQr = true;
      _qr = f.qr;
      _open(file.path, 'frame.png', keepQr: true);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _image?.dispose();
    _sampleCard?.dispose();
    for (final i in _samplePhotos ?? const <ui.Image>[]) {
      i.dispose();
    }
    super.dispose();
  }

  Future<void> _chooseSource() => showSheet<void>(
    context,
    title: 'Chọn file khung',
    body: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetRow(
          icon: Icons.folder_outlined,
          title: 'App Tệp',
          subtitle: 'PNG trong iCloud Drive, Trên iPad, AirDrop…',
          onTap: () async {
            Navigator.of(ctx).pop();
            final path = await _files.invokeMethod<String>('pickPng');
            if (path != null) await _open(path, p.basename(path).replaceFirst(RegExp(r'^frame-\d+-'), ''));
          },
        ),
        SheetRow(
          icon: Icons.photo_library_outlined,
          title: 'Ảnh',
          subtitle: 'PNG đã lưu vào app Ảnh',
          onTap: () async {
            Navigator.of(ctx).pop();
            final x = await ImagePicker().pickImage(source: ImageSource.gallery, requestFullMetadata: false);
            if (x != null) await _open(x.path, x.name);
          },
        ),
        Text(
          'File PNG 1200×1776 (dọc) hoặc 1776×1200 (ngang), ô ảnh để trong suốt, chừa chỗ nền trơn cho QR.',
          style: hintStyle(),
        ),
      ],
    ),
  );

  Future<void> _open(String path, String name, {bool keepQr = false}) async {
    setState(() => _busy = true);
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!.buffer.asUint8List();
      final scan = await compute(scanFrameArgs, (rgba, image.width, image.height));
      if (!mounted) return;
      _image?.dispose();
      _sampleCard?.dispose();
      _sampleCard = null;
      setState(() {
        _png = bytes;
        _image = image;
        _scan = scan;
        _fileName = name;
        if (!keepQr) {
          _manualQr = false;
          _qr = scan.autoQr ?? scan.fallbackQr;
        }
        if (_name.text.trim().isEmpty) _name.text = _prettyName(name);
      });
      if (_sample) await _renderSample();
    } catch (e) {
      if (mounted) showToast(context, 'Không mở được file: $e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _prettyName(String file) {
    final base = p.basenameWithoutExtension(file).replaceAll(RegExp(r'[-_]+'), ' ').trim();
    return base.isEmpty ? 'Khung riêng' : base[0].toUpperCase() + base.substring(1);
  }

  /// The frame as it would be saved now.
  BoothFrame? get _frame {
    final s = _scan;
    if (s == null || s.card == null || s.slots.isEmpty || _qr == null) return null;
    return BoothFrame(
      id: widget.frame?.id ?? 'preview',
      name: _name.text.trim(),
      size: s.card!,
      slots: s.slots,
      qr: _qr!,
      overlay: _image,
    );
  }

  /// "Ảnh mẫu": the card exactly as it prints, with sample photos.
  Future<void> _renderSample() async {
    final f = _frame;
    if (f == null) return;
    _samplePhotos ??= await _makeSamples();
    final card = await renderPrint(
      PrintSpec(
        frame: f,
        photos: [for (var i = 0; i < f.picks; i++) _samplePhotos![i % _samplePhotos!.length]],
        title: b.settings.title,
        dateLine: b.settings.dateLine,
        subtitle: b.settings.subtitle,
        qrUrl: b.linkFor('testtesttest'),
      ),
    );
    if (!mounted) return card.dispose();
    _sampleCard?.dispose();
    setState(() => _sampleCard = card);
  }

  /// Bokeh-style stand-ins for guest photos (no photo assets in the app).
  static Future<List<ui.Image>> _makeSamples() async {
    const palettes = [
      [Color(0xFF5C3A4A), Color(0xFF2A1A24), Color(0xFFE9C7C0)],
      [Color(0xFF4A3A22), Color(0xFF1E160C), Color(0xFFF5E1A4)],
      [Color(0xFF233056), Color(0xFF0E1428), Color(0xFFB8C8F0)],
      [Color(0xFFE8DCC4), Color(0xFFB9A987), Color(0xFFFFF6DA)],
    ];
    final out = <ui.Image>[];
    for (final (i, c) in palettes.indexed) {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      const size = Size(800, 600);
      canvas.drawRect(
        Offset.zero & size,
        Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(800, 600), [c[0], c[1]]),
      );
      final r = math.Random(7 + i);
      for (var k = 0; k < 26; k++) {
        canvas.drawCircle(
          Offset(r.nextDouble() * 800, r.nextDouble() * 360),
          12 + r.nextDouble() * 46,
          Paint()
            ..color = c[2].withValues(alpha: 0.12 + r.nextDouble() * 0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
      // Heads and shoulders.
      final people = Paint()..color = const Color(0xFF15100C);
      for (var k = 0; k < 4; k++) {
        final x = 130.0 + k * 180;
        canvas.drawCircle(Offset(x, 420), 46, people);
        canvas.drawRRect(RRect.fromLTRBR(x - 90, 470, x + 90, 640, const Radius.circular(70)), people);
      }
      out.add(await rec.endRecording().toImage(800, 600));
    }
    return out;
  }

  void _setQrMode(bool manual) {
    setState(() {
      _manualQr = manual;
      if (!manual) _qr = _scan?.autoQr ?? _scan?.fallbackQr;
    });
    if (_sample) _renderSample();
  }

  void _dragQr(Offset cardPoint) {
    final s = _scan?.card;
    if (s == null) return;
    final x = (cardPoint.dx - qrSide / 2).clamp(0.0, s.width - qrSide).roundToDouble();
    final y = (cardPoint.dy - qrSide / 2).clamp(0.0, s.height - qrSide).roundToDouble();
    setState(() {
      _manualQr = true;
      _qr = Rect.fromLTWH(x, y, qrSide, qrSide);
    });
  }

  List<FrameCheck> get _checks {
    final s = _scan;
    if (s == null) return const [];
    final out = [...s.checks];
    if (_manualQr && _qr != null) {
      out.removeWhere((c) => c.text.startsWith('Chỗ QR') || c.text.startsWith('Không thấy chỗ'));
      final hit = s.slots.any((r) => r.overlaps(_qr!));
      out.insert(
        math.min(3, out.length),
        hit
            ? const FrameCheck(CheckLevel.warn, 'QR đè lên ô ảnh: kéo QR ra chỗ trống')
            : FrameCheck(CheckLevel.ok, 'QR đặt tay ở ${cornerLabel(_qr!, s.card ?? portraitCard)}'),
      );
    }
    return out;
  }

  Future<void> _save() async {
    final f = _frame;
    final png = _png;
    if (f == null || png == null) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      showToast(context, 'Đặt tên cho khung', icon: Icons.error_outline);
      return;
    }
    setState(() => _busy = true);
    try {
      await b.frames.saveCustom(
        id: widget.frame?.id,
        name: name,
        png: png,
        card: f.size,
        slots: f.slots,
        qr: f.qr,
      );
      if (!mounted) return;
      showToast(context, 'Đã lưu khung "$name"');
      widget.onDone();
    } catch (e) {
      if (mounted) showToast(context, 'Không lưu được: $e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() => showSheet<void>(
    context,
    title: 'Xoá khung này?',
    body: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Khung "${widget.frame!.name}" sẽ không còn ở màn chọn khung. Các tấm đã in và ảnh của khách không bị ảnh hưởng.',
          style: LuxFonts.sans(size: 16, height: 1.5),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: LineButton(label: 'Thôi', height: 56, fontSize: 18, onPressed: () => Navigator.of(ctx).pop()),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GoldButton(
                label: 'Xoá khung',
                icon: Icons.delete_outline,
                height: 56,
                fontSize: 18,
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  final name = widget.frame!.name;
                  await b.frames.deleteCustom(widget.frame!);
                  if (!mounted) return;
                  showToast(context, 'Đã xoá khung "$name"');
                  widget.onDone();
                },
              ),
            ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scan = _scan;
    final img = _image;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 36, 0, 40),
      children: [
        PageHeader(
          back: ('Khung ảnh', widget.onDone),
          title: _editing ? 'Sửa khung' : 'Thêm khung mới',
          subtitle: const SizedBox.shrink(),
          trailing: _fileName == null || img == null
              ? null
              : Glass(
                  radius: 999,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.insert_drive_file_outlined, size: 18, color: Lux.champagneLight),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(_fileName!, style: LuxFonts.sans(size: 15), overflow: TextOverflow.ellipsis),
                      ),
                      Text(' · ${img.width}×${img.height}', style: hintStyle(size: 15)),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 560, child: _left(scan, img)),
            const SizedBox(width: 24),
            Expanded(child: _right(scan)),
          ],
        ),
      ],
    );
  }

  Widget _left(FrameScan? scan, ui.Image? img) {
    if (img == null || scan == null) {
      return GestureDetector(
        onTap: _busy ? null : _chooseSource,
        child: Container(
          height: 420,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: Lux.champagne.withValues(alpha: 0.04),
            border: Border.all(color: Lux.champagne.withValues(alpha: 0.6), width: 1.5),
          ),
          child: Center(
            child: _busy
                ? const CircularProgressIndicator(color: Lux.champagne)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const PicoIcon(Icons.add_photo_alternate_outlined, size: 72),
                      const SizedBox(height: 16),
                      Text(
                        'Chọn file PNG khung',
                        style: LuxFonts.sans(size: 21, weight: FontWeight.w600, color: Lux.champagneLight),
                      ),
                      const SizedBox(height: 6),
                      Text('Ô ảnh để trong suốt, app tự tìm các ô và chỗ đặt QR', style: hintStyle()),
                    ],
                  ),
          ),
        ),
      );
    }
    final card = scan.card ?? Size(img.width.toDouble(), img.height.toDouble());
    final boxW = card.width >= card.height ? 560.0 : 560.0 * 0.62;
    final k = boxW / card.width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _manualQr ? 'CHẠM HOẶC KÉO ĐỂ ĐẶT QR' : 'Ô ẢNH TỰ NHẬN TỪ VÙNG TRONG SUỐT',
                style: LuxFonts.eyebrow(size: 13),
              ),
            ),
            Text('Ảnh mẫu', style: hintStyle()),
            const SizedBox(width: 10),
            GoldToggle(
              value: _sample,
              onChanged: scan.canSave
                  ? (v) {
                      setState(() => _sample = v);
                      if (v) _renderSample();
                    }
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: boxW,
            height: card.height * k,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                const BoxShadow(color: Color(0x99000000), blurRadius: 50, offset: Offset(0, 24)),
                BoxShadow(color: Lux.champagne.withValues(alpha: 0.35), spreadRadius: 1),
              ],
            ),
            child: _sample && _sampleCard != null
                ? RawImage(image: _sampleCard, fit: BoxFit.fill)
                : GestureDetector(
                    onTapDown: _manualQr ? (d) => _dragQr(d.localPosition / k) : null,
                    onPanUpdate: _manualQr ? (d) => _dragQr(d.localPosition / k) : null,
                    onPanEnd: _manualQr && _sample ? (_) => _renderSample() : null,
                    child: CustomPaint(
                      painter: _EditPainter(
                        image: img,
                        card: card,
                        slots: scan.slots,
                        qr: _qr,
                        qrUrl: b.linkFor('testtesttest'),
                        manual: _manualQr,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 20),
        if (scan.slots.isNotEmpty) _table(scan),
      ],
    );
  }

  Widget _table(FrameScan scan) {
    TextStyle cell({Color? color}) => monoStyle(size: 14, color: color ?? Lux.ivoryA(0.8));
    Widget row(String head, Color headColor, List<double> v, {bool header = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(head, style: header ? LuxFonts.eyebrow(size: 12) : cell(color: headColor))),
          for (final x in v) Expanded(child: Text(x.round().toString(), style: cell())),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(width: 90, child: Text('Ô', style: LuxFonts.eyebrow(size: 12))),
            for (final h in ['X', 'Y', 'RỘNG', 'CAO']) Expanded(child: Text(h, style: LuxFonts.eyebrow(size: 12))),
          ],
        ),
        const SizedBox(height: 4),
        for (final (i, r) in scan.slots.indexed)
          row('Ô ${i + 1}', Lux.champagneLight, [r.left, r.top, r.width, r.height]),
        if (_qr != null) row('QR', Lux.rose, [_qr!.left, _qr!.top, _qr!.width, _qr!.height]),
      ],
    );
  }

  Widget _right(FrameScan? scan) {
    final checks = _checks;
    return Glass(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('KIỂM TRA FILE', style: LuxFonts.eyebrow(size: 13)),
          const SizedBox(height: 8),
          if (scan == null)
            for (final t in const [
              'PNG 1200×1776 hoặc 1776×1200',
              'Ô ảnh trong suốt, hình chữ nhật (1–6 ô)',
              'Chừa chỗ nền trơn ~2 cm cho QR',
            ])
              _checkRow(null, t)
          else
            for (final c in checks) _checkRow(c.level, c.text),
          const SizedBox(height: 14),
          AdminField(controller: _name, label: 'Tên khung', onChanged: (_) => setState(() {})),
          const SizedBox(height: 14),
          Text('Vị trí QR', style: LuxFonts.sans(size: 16, color: Lux.ivoryA(0.72))),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: GoldSegments<bool>(
              options: const [(false, 'Tự nhận'), (true, 'Chọn lại')],
              value: _manualQr,
              onChanged: scan?.canSave == true ? _setQrMode : (_) {},
            ),
          ),
          const SizedBox(height: 22),
          GoldButton(
            label: _busy ? 'Đang xử lý…' : 'Lưu khung',
            icon: Icons.check,
            height: 60,
            fontSize: 19,
            onPressed: !_busy && scan?.canSave == true && _name.text.trim().isNotEmpty ? _save : null,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: LineButton(
                  label: _png == null ? 'Chọn file' : 'Chọn file khác',
                  height: 52,
                  fontSize: 16,
                  onPressed: _busy ? null : _chooseSource,
                ),
              ),
              const SizedBox(width: 10),
              LineButton(label: 'Huỷ', width: 90, height: 52, fontSize: 16, onPressed: widget.onDone),
            ],
          ),
          if (_editing) ...[
            const SizedBox(height: 14),
            Center(child: TextLink('Xoá khung này', onTap: _delete)),
          ],
        ],
      ),
    );
  }

  Widget _checkRow(CheckLevel? level, String text) {
    final (icon, color) = switch (level) {
      CheckLevel.ok => (Icons.check, kGreen),
      CheckLevel.warn => (Icons.error_outline, Lux.amber),
      CheckLevel.bad => (Icons.close, kBad),
      null => (Icons.circle_outlined, Lux.ivoryA(0.45)),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 19, color: color)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: LuxFonts.sans(size: 15, height: 1.4))),
        ],
      ),
    );
  }
}

/// The PNG over a checkerboard (holes show it), each window numbered with its size, the QR.
class _EditPainter extends CustomPainter {
  _EditPainter({
    required this.image,
    required this.card,
    required this.slots,
    required this.qr,
    required this.qrUrl,
    required this.manual,
  });
  final ui.Image image;
  final Size card;
  final List<Rect> slots;
  final Rect? qr;
  final String qrUrl;
  final bool manual;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / card.width;
    canvas.save();
    canvas.scale(k);
    final all = Offset.zero & card;
    // Checkerboard where the PNG lets it through.
    canvas.drawRect(all, Paint()..color = const Color(0xFF2A2730));
    final light = Paint()..color = const Color(0xFF3A3640);
    const sq = 28.0;
    for (var y = 0.0; y < card.height; y += sq) {
      for (var x = ((y / sq).round().isEven ? 0.0 : sq); x < card.width; x += 2 * sq) {
        canvas.drawRect(Rect.fromLTWH(x, y, sq, sq), light);
      }
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      all,
      Paint()..filterQuality = FilterQuality.medium,
    );
    final gold = Paint()
      ..color = const Color(0xFFB8914F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 / k;
    for (final (i, r) in slots.indexed) {
      canvas.drawRect(r.inflate(5), gold);
      _badge(canvas, r, i + 1, k);
    }
    final q = qr;
    if (q != null) {
      canvas.drawRect(q.inflate(8), Paint()..color = const Color(0xFFFFFFFF));
      paintQr(canvas, qrUrl, q);
      if (manual) {
        canvas.drawRect(
          q.inflate(14),
          Paint()
            ..color = Lux.champagneLight
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 / k,
        );
      }
    }
    canvas.restore();
  }

  /// Gold numbered disc with "760×428" under it, drawn at screen size whatever the card scale.
  void _badge(Canvas canvas, Rect r, int n, double k) {
    final c = r.center;
    final radius = 19 / k;
    canvas.drawCircle(
      c.translate(0, -12 / k),
      radius,
      Paint()..shader = ui.Gradient.linear(c.translate(0, -31 / k), c.translate(0, 7 / k), Lux.button.colors, Lux.button.stops),
    );
    _text(canvas, '$n', c.translate(0, -12 / k), LuxFonts.serif(size: 19 / k, weight: FontWeight.w700, color: Lux.goldInk));
    final label = '${r.width.round()}×${r.height.round()}';
    final tp = TextPainter(
      text: TextSpan(text: label, style: LuxFonts.sans(size: 11 / k, weight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    final chip = Rect.fromCenter(center: c.translate(0, 22 / k), width: tp.width + 14 / k, height: tp.height + 6 / k);
    canvas.drawRRect(
      RRect.fromRectAndRadius(chip, Radius.circular(6 / k)),
      Paint()..color = const Color(0xCC17141C),
    );
    tp.paint(canvas, chip.center - Offset(tp.width / 2, tp.height / 2));
  }

  void _text(Canvas canvas, String s, Offset center, TextStyle style) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_EditPainter old) =>
      old.image != image || old.qr != qr || old.manual != manual || old.slots != slots;
}
