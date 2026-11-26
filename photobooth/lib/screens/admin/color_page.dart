import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../booth/booth.dart';
import '../../camera/filters.dart';
import '../../camera/grade.dart';
import '../../ui/lux.dart';
import 'kit.dart';

/// Cài đặt – Màu ảnh: the staff's colour grade (exposure, contrast, warmth, … vignette, rounded
/// windows), set before the event. Saved with "Áp dụng", it goes under the guest's filter on every
/// photo and Live clip taken afterwards. Guests never see these controls.
class ColorPage extends StatefulWidget {
  const ColorPage({super.key, required this.booth});
  final Booth booth;

  @override
  State<ColorPage> createState() => _ColorPageState();
}

class _ColorPageState extends State<ColorPage> {
  Booth get b => widget.booth;

  late PhotoGrade _draft = b.settings.grade;
  BoothFilter _filter = BoothFilter.values.first;

  /// The photo the preview is made from (downscaled), and where it came from.
  ui.Image? _sample;
  String? _sampleFrom;

  /// [_sample] through [_filter] with the draft grade / without any grade ("ảnh gốc").
  ui.Image? _graded;
  ui.Image? _plain;
  bool _showPlain = false;
  bool _shooting = false;

  Timer? _debounce;
  int _renderId = 0;

  static const _previewLong = 1100;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLastSession());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sample?.dispose();
    _graded?.dispose();
    _plain?.dispose();
    super.dispose();
  }

  /// Newest guest's first photo (it already has that guest's filter; "Chụp ảnh mẫu" gives a clean one).
  Future<void> _loadLastSession() async {
    final root = Directory(p.join(b.docs.path, 'Booth'));
    File? newest;
    try {
      final days = root.listSync().whereType<Directory>().where((d) => RegExp(r'\d{4}-\d{2}-\d{2}$').hasMatch(d.path)).toList()
        ..sort((a, c) => c.path.compareTo(a.path));
      for (final day in days) {
        final sessions = day.listSync().whereType<Directory>().toList()..sort((a, c) => c.path.compareTo(a.path));
        for (final s in sessions) {
          final f = File(p.join(s.path, '1.jpg'));
          if (f.existsSync()) {
            newest = f;
            break;
          }
        }
        if (newest != null) break;
      }
    } catch (_) {}
    if (newest == null) return;
    final img = await _decode(await newest.readAsBytes());
    if (!mounted) return img.dispose();
    _setSample(img, 'Ảnh của lượt gần nhất (đã có filter của khách đó)');
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    final long = math.max(desc.width, desc.height);
    final k = long > _previewLong ? _previewLong / long : 1.0;
    final codec = await desc.instantiateCodec(
      targetWidth: (desc.width * k).round(),
      targetHeight: (desc.height * k).round(),
    );
    final img = (await codec.getNextFrame()).image;
    codec.dispose();
    desc.dispose();
    buffer.dispose();
    return img;
  }

  /// A fresh photo from the camera the guests use (Sony when it is on and ready, else the iPad).
  Future<void> _shoot() async {
    final cam = b.camera;
    setState(() => _shooting = true);
    try {
      await cam.wake();
      // Give the exposure a moment to settle after the camera turns on.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      final shot = await cam.capture(
        0,
        cellAspect: 3 / 2,
        skin: b.settings.skin,
        external: b.settings.externalCamera,
      );
      final base = await shot.base;
      cam.release([shot]);
      // Downscaled copy for a quick preview.
      final k = math.min(1.0, _previewLong / math.max(base.width, base.height));
      final w = (base.width * k).round(), h = (base.height * k).round();
      final rec = ui.PictureRecorder();
      Canvas(rec).drawImageRect(
        base,
        Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()),
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final small = await rec.endRecording().toImage(w, h);
      base.dispose();
      if (!mounted) return small.dispose();
      _setSample(small, shot.fromSony ? 'Ảnh mẫu vừa chụp (máy ảnh Sony)' : 'Ảnh mẫu vừa chụp (camera iPad)');
    } catch (e) {
      if (mounted) showToast(context, 'Chụp ảnh mẫu lỗi: $e', icon: Icons.error_outline);
    } finally {
      await cam.sleep();
      if (mounted) setState(() => _shooting = false);
    }
  }

  void _setSample(ui.Image img, String from) {
    _sample?.dispose();
    setState(() {
      _sample = img;
      _sampleFrom = from;
    });
    _render(plainToo: true);
  }

  void _change(PhotoGrade g) {
    setState(() => _draft = g);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 90), _render);
  }

  Future<void> _render({bool plainToo = false}) async {
    final src = _sample;
    if (src == null) return;
    final id = ++_renderId;
    final cam = b.camera;
    final graded = await cam.develop(src, _filter, '0', grade: _draft);
    final plain = plainToo ? await cam.develop(src, _filter, '0', grade: PhotoGrade.none) : null;
    if (!mounted || id != _renderId) {
      graded.dispose();
      plain?.dispose();
      return;
    }
    setState(() {
      _graded?.dispose();
      _graded = graded;
      if (plain != null) {
        _plain?.dispose();
        _plain = plain;
      }
    });
  }

  void _apply() {
    b.settings.grade = _draft;
    showToast(context, 'Đã áp dụng cho các ảnh chụp từ giờ');
  }

  @override
  Widget build(BuildContext context) {
    final saved = b.settings.grade;
    final dirty = _draft != saved;
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'Màu ảnh',
            subtitle: const Text('Chỉnh trước sự kiện · áp dụng cho ảnh và video chụp từ giờ, dưới filter khách chọn'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusPill(
                  dirty ? 'Chưa áp dụng' : (saved.isNeutral ? 'Màu gốc' : 'Đang áp dụng'),
                  dirty ? PillKind.wait : (saved.isNeutral ? PillKind.none : PillKind.ok),
                ),
                const SizedBox(width: 12),
                LineButton(
                  label: 'Đặt lại',
                  icon: Icons.restart_alt,
                  width: 150,
                  height: 56,
                  fontSize: 18,
                  onPressed: _draft.isNeutral ? null : () => _change(PhotoGrade.none),
                ),
                const SizedBox(width: 10),
                GoldButton(label: 'Áp dụng', icon: Icons.check, width: 170, height: 56, fontSize: 18, onPressed: dirty ? _apply : null),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 420, child: _previewColumn()),
                const SizedBox(width: 24),
                Expanded(child: _sliders()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewColumn() {
    final img = _showPlain ? _plain : _graded;
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        AdminCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTapDown: (_) => setState(() => _showPlain = true),
                onTapUp: (_) => setState(() => _showPlain = false),
                onTapCancel: () => setState(() => _showPlain = false),
                child: AspectRatio(
                  aspectRatio: _sample == null ? 3 / 2 : _sample!.width / _sample!.height,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      // Bo góc as it lands on the print: radius in card px on a ~760 px wide window.
                      final r = _draft.corner * box.maxWidth / 760;
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(_showPlain ? 0 : r),
                        child: Container(
                          color: Colors.white.withValues(alpha: 0.04),
                          alignment: Alignment.center,
                          child: img != null
                              ? RawImage(image: img, fit: BoxFit.cover, width: box.maxWidth, height: box.maxHeight)
                              : Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Text(
                                    _shooting ? 'Đang chụp…' : 'Chưa có ảnh mẫu.\nBấm "Chụp ảnh mẫu" để xem màu trước.',
                                    textAlign: TextAlign.center,
                                    style: hintStyle(size: 16),
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _sample == null
                    ? 'Ảnh mẫu dùng camera đang chọn ở trang Máy ảnh'
                    : '${_sampleFrom ?? ''} · chạm giữ ảnh để xem màu gốc',
                style: hintStyle(size: 14),
              ),
              const SizedBox(height: 12),
              LineButton(
                label: _shooting ? 'Đang chụp…' : 'Chụp ảnh mẫu',
                icon: Icons.photo_camera_outlined,
                width: double.infinity,
                height: 52,
                fontSize: 18,
                onPressed: _shooting ? null : _shoot,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AdminCard(
          title: 'Xem với filter',
          icon: Icons.filter_vintage_outlined,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in BoothFilter.values)
                _Chip(
                  label: f.label,
                  on: f == _filter,
                  onTap: () {
                    setState(() => _filter = f);
                    _render(plainToo: true);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sliders() {
    final g = _draft;
    String signed(double v) {
      final n = (v * 100).round();
      return n > 0 ? '+$n' : '$n';
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        AdminCard(
          title: 'Ánh sáng',
          icon: Icons.wb_sunny_outlined,
          child: Column(
            children: [
              _GradeSlider('Phơi sáng', g.exposure, signed, (v) => _change(g.copyWith(exposure: v))),
              _GradeSlider('Độ sáng', g.brightness, signed, (v) => _change(g.copyWith(brightness: v))),
              _GradeSlider('Tương phản', g.contrast, signed, (v) => _change(g.copyWith(contrast: v))),
              _GradeSlider('Vùng sáng', g.highlights, signed, (v) => _change(g.copyWith(highlights: v))),
              _GradeSlider('Vùng tối', g.shadows, signed, (v) => _change(g.copyWith(shadows: v)), last: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AdminCard(
          title: 'Màu',
          icon: Icons.palette_outlined,
          child: Column(
            children: [
              _GradeSlider(
                'Nhiệt độ',
                g.temperature,
                signed,
                (v) => _change(g.copyWith(temperature: v)),
                track: const [Color(0xFF4A8FE0), Color(0xFFEDE6D8), Color(0xFFE8A13A)],
                ends: ('Lạnh', 'Ấm'),
              ),
              _GradeSlider(
                'Tông màu',
                g.tint,
                signed,
                (v) => _change(g.copyWith(tint: v)),
                track: const [Color(0xFF5DBB63), Color(0xFFEDE6D8), Color(0xFFD86BB4)],
                ends: ('Xanh lá', 'Hồng'),
              ),
              _GradeSlider('Độ bão hoà', g.saturation, signed, (v) => _change(g.copyWith(saturation: v))),
              _GradeSlider('Độ rực', g.vibrance, signed, (v) => _change(g.copyWith(vibrance: v)), last: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AdminCard(
          title: 'Hiệu ứng',
          icon: Icons.auto_awesome_outlined,
          child: Column(
            children: [
              _GradeSlider(
                'Tối góc',
                g.vignette,
                (v) => '${(v * 100).round()}',
                (v) => _change(g.copyWith(vignette: v)),
                min: 0,
              ),
              _GradeSlider(
                'Bo góc ảnh',
                g.corner,
                (v) => v == 0 ? 'Vuông' : '${v.round()} px',
                (v) => _change(g.copyWith(corner: v.roundToDouble())),
                min: 0,
                max: PhotoGrade.maxCorner,
                hint: 'Góc ô ảnh trên tấm in',
                last: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Chạm hai lần vào tên một mục để đưa nó về 0. Video Live nhận cùng màu và tối góc; bo góc chỉ có trên tấm in.',
          style: hintStyle(size: 14),
        ),
      ],
    );
  }
}

class _GradeSlider extends StatelessWidget {
  const _GradeSlider(
    this.label,
    this.value,
    this.format,
    this.onChanged, {
    this.min = -1,
    this.max = 1,
    this.track,
    this.ends,
    this.hint,
    this.last = false,
  });
  final String label;
  final double value;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;

  /// Colour track (cool → warm …); null = gold.
  final List<Color>? track;
  final (String, String)? ends;
  final String? hint;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final zero = min < 0 ? 0.0 : min;
    final changed = value != zero;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: Lux.champagne.withValues(alpha: 0.12))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onDoubleTap: () => onChanged(zero),
                child: Text(label, style: LuxFonts.sans(size: 18, weight: changed ? FontWeight.w600 : FontWeight.w400)),
              ),
              if (hint != null) ...[const SizedBox(width: 10), Flexible(child: Text(hint!, style: hintStyle(size: 14)))],
              const Spacer(),
              Text(
                format(value),
                style: LuxFonts.sans(size: 17, weight: FontWeight.w600, color: changed ? Lux.champagneLight : Lux.ivoryA(0.5)),
              ),
            ],
          ),
          SizedBox(
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Bipolar: a plain track with a tick at 0 (a gold fill from the left would read as "changed").
                if (track == null && min < 0) ...[
                  Positioned(
                    left: 24,
                    right: 24,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: Lux.champagne.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                  Container(width: 2, height: 16, color: Lux.champagne.withValues(alpha: 0.55)),
                ],
                if (track != null)
                  Positioned(
                    left: 24,
                    right: 24,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        gradient: LinearGradient(colors: track!),
                      ),
                    ),
                  ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: track != null || min < 0 ? Colors.transparent : Lux.champagne,
                    inactiveTrackColor: track != null || min < 0 ? Colors.transparent : Lux.champagne.withValues(alpha: 0.18),
                    thumbColor: Lux.champagneLight,
                    overlayColor: Lux.champagne.withValues(alpha: 0.15),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                    trackShape: const RoundedRectSliderTrackShape(),
                  ),
                  child: Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
          if (ends != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Text(ends!.$1, style: hintStyle(size: 13)),
                  const Spacer(),
                  Text(ends!.$2, style: hintStyle(size: 13)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: on ? Lux.button : null,
        border: on ? null : Border.all(color: Lux.champagne.withValues(alpha: 0.35)),
      ),
      child: Align(
        widthFactor: 1,
        child: Text(
          label,
          style: LuxFonts.sans(size: 16, weight: on ? FontWeight.w600 : FontWeight.w500, color: on ? Lux.goldInk : Lux.ivoryA(0.85)),
        ),
      ),
    ),
  );
}
