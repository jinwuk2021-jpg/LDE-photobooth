import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../booth/booth.dart';
import '../booth/print_layout.dart';
import '../camera/filters.dart';
import '../ui/lux.dart';
import '../ui/strings.dart';
import '../ui/sparkle.dart';

/// 4 · Pick the frame's photos (tap order = print order, gold number badges) and a filter, with
/// the print preview in a glass panel beside. A countdown pill (red and beating for the last
/// 10 s): when it runs out the first shots not picked fill the frame and it finishes by itself.
class PickScreen extends StatefulWidget {
  const PickScreen({
    super.key,
    required this.booth,
    required this.guest,
    required this.onRetake,
    required this.onPrinted,
  });
  final Booth booth;
  final GuestSession guest;
  final VoidCallback onRetake;
  final ValueChanged<Finished> onPrinted;

  @override
  State<PickScreen> createState() => _PickScreenState();
}

class _PickScreenState extends State<PickScreen> {
  BoothFilter _filter = BoothFilter.values.first;

  /// The shots through [_filter]; null while developing the first time.
  List<ui.Image>? _images;
  final Map<BoothFilter, ui.Image> _thumbs = {};
  int _generation = 0;
  bool _developing = false;
  bool _printing = false;

  /// The shots could not be processed: only "Chụp lại" is left.
  bool _failed = false;

  /// Seconds left to pick; starts once the photos show.
  late int _secondsLeft = widget.booth.settings.pickSeconds;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _develop(_filter);
    _makeThumbs();
  }

  @override
  void dispose() {
    _clock?.cancel();
    final images = _images, thumbs = _thumbs.values.toList();
    // After the last frame that may still paint them.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      images?.forEach((i) => i.dispose());
      for (final t in thumbs) {
        t.dispose();
      }
    });
    super.dispose();
  }

  Future<void> _develop(BoothFilter filter) async {
    final gen = ++_generation;
    setState(() {
      _filter = filter;
      _developing = true;
    });
    final List<ui.Image> images;
    try {
      images = await widget.booth.developAll(widget.guest, filter);
    } catch (_) {
      // Also lands here when "Chụp lại" freed the shots meanwhile.
      if (mounted && gen == _generation) setState(() => _failed = true);
      return;
    }
    if (!mounted || gen != _generation) {
      for (final i in images) {
        i.dispose();
      }
      return;
    }
    final old = _images;
    setState(() {
      _images = images;
      _developing = false;
    });
    SchedulerBinding.instance.addPostFrameCallback((_) => old?.forEach((i) => i.dispose()));
    _clock ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    // Time ran out while a filter was developing.
    if (_secondsLeft <= 0) _timeUp();
  }

  void _tick() {
    if (_printing) return;
    setState(() => _secondsLeft--);
    if (_secondsLeft <= 0) _timeUp();
  }

  void _timeUp() {
    _clock?.cancel();
    if (_developing || _failed || _printing) return;
    widget.guest.fillPicks();
    _print();
  }

  /// One small sample of the first shot per filter, for the filter buttons.
  Future<void> _makeThumbs() async {
    try {
      await _makeThumbsUnsafe();
    } catch (_) {
      // Shots freed by "Chụp lại" or not processable: the buttons stay plain.
    }
  }

  Future<void> _makeThumbsUnsafe() async {
    final base = await widget.guest.shots.first.base;
    const w = 240;
    final h = (w * base.height / base.width).round();
    final rec = ui.PictureRecorder();
    Canvas(rec).drawImageRect(
      base,
      Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final small = await rec.endRecording().toImage(w, h);
    for (final f in BoothFilter.values) {
      final t = await widget.booth.camera.develop(small, f, '0');
      if (!mounted) return t.dispose();
      setState(() => _thumbs[f] = t);
    }
    small.dispose();
  }

  Future<void> _print() async {
    final images = _images;
    if (images == null || !widget.guest.complete || _printing) return;
    setState(() => _printing = true);
    try {
      widget.onPrinted(await widget.booth.finish(widget.guest, _filter, images));
    } catch (e) {
      if (!mounted) return;
      setState(() => _printing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không tạo được ảnh in: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final guest = widget.guest;
    return DecoratedBox(
      decoration: Lux.backdrop,
      child: Stack(
        children: [
          const SparkleBackground(level: SparkleLevel.mid, seed: 45),
          ListenableBuilder(
            listenable: guest,
            builder: (context, _) => Stack(
              children: [
                Positioned(left: 40, top: 40, width: 680, bottom: 40, child: _left(guest)),
                Positioned(left: 744, top: 40, right: 40, bottom: 40, child: _right(guest)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _left(GuestSession guest) {
    final images = _images;
    final need = guest.frame.picks;
    // 4 shots 2 × 2, 5–6 in rows of 3, 8 in rows of 4.
    final n = guest.shots.length;
    final cols = n <= 4 ? 2 : (n <= 6 ? 3 : 4);
    final tileH = cols == 4 ? 118.0 : 162.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        T.now.pickBest(need),
                        style: LuxFonts.serif(size: 38, weight: FontWeight.w600, height: 1.15),
                      ),
                      GoldText(
                        '(${guest.picks.length}/$need)',
                        style: LuxFonts.serif(size: 38, weight: FontWeight.w600, height: 1.15),
                        sweep: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(T.now.tapToPick, style: LuxFonts.sans(size: 18, color: Lux.ivoryA(0.68))),
                ],
              ),
            ),
            const SizedBox(width: 16),
            _TimerPill(seconds: _secondsLeft),
          ],
        ),
        const SizedBox(height: 22),
        if (_failed)
          Expanded(
            child: Center(
              child: Text(T.now.cannotProcess, textAlign: TextAlign.center, style: LuxFonts.serif(size: 32)),
            ),
          )
        else if (images == null)
          const Expanded(
            child: Center(child: CircularProgressIndicator(color: Lux.champagne)),
          )
        else
          GridView.count(
            crossAxisCount: cols,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: ((680 - 16 * (cols - 1)) / cols) / tileH,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < images.length; i++)
                _ShotTile(
                  image: images[i],
                  order: guest.picks.indexOf(i),
                  dim: guest.complete && !guest.picks.contains(i),
                  developing: _developing,
                  onTap: () => guest.toggle(i),
                ),
            ],
          ),
        const Spacer(),
        Text(T.now.filters, style: LuxFonts.eyebrow(size: 14)),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final f in BoothFilter.values)
              _FilterChip(
                name: T.now.filterNames[f.name] ?? f.label,
                thumb: _thumbs[f],
                on: f == _filter,
                onTap: f == _filter || _printing ? null : () => _develop(f),
              ),
          ],
        ),
      ],
    );
  }

  Widget _right(GuestSession guest) {
    final images = _images;
    final s = widget.booth.settings;
    final need = guest.frame.picks;
    final aspect = guest.frame.size.aspectRatio;
    // The print fitted into 362 × 300.
    final previewW = aspect >= 362 / 300 ? 362.0 : 300 * aspect;
    return Glass(
      radius: 30,
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(T.now.printPreview, style: LuxFonts.eyebrow(size: 14)),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 300,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  left: -24,
                  right: -24,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(colors: [Color(0x38D4AF6A), Color(0x00D4AF6A)], stops: [0, 0.7]),
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  child: Container(
                    key: ValueKey(Object.hashAll([...guest.picks, _filter, images])),
                    width: previewW,
                    height: previewW / aspect,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 50, offset: Offset(0, 24))],
                      border: Border.all(color: const Color(0x59D4AF6A)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CustomPaint(
                        painter: PrintPainter(
                          PrintSpec(
                            frame: guest.frame,
                            photos: [
                              for (var k = 0; k < need; k++)
                                k < guest.picks.length && images != null ? images[guest.picks[k]] : null,
                            ],
                            title: s.title,
                            dateLine: s.dateLine,
                            subtitle: s.subtitle,
                            scanHint: T.now.printScanHint,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(T.now.frameName(guest.frame.label), style: LuxFonts.serif(size: 24, weight: FontWeight.w600)),
              GoldText(
                T.now.filterNames[_filter.name] ?? _filter.label,
                style: LuxFonts.serif(size: 24, weight: FontWeight.w600),
                sweep: false,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(T.now.slotsInOrder(need), style: LuxFonts.sans(size: 16, color: Lux.ivoryA(0.62))),
          const Spacer(),
          Container(
            height: 1,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0x00D4AF6A), Color(0x80D4AF6A), Color(0x00D4AF6A)]),
            ),
          ),
          Row(
            children: [
              LineButton(
                label: T.now.retake,
                icon: Icons.replay,
                width: 156,
                height: 88,
                fontSize: 21,
                onPressed: _printing ? null : widget.onRetake,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GoldButton(
                  label: _printing
                      ? T.now.processing
                      : (guest.complete
                            ? (widget.booth.settings.printing ? T.now.print : T.now.done)
                            : T.now.doneMore(need - guest.picks.length)),
                  icon: guest.complete && !_printing ? Icons.arrow_forward : null,
                  iconAfter: true,
                  fontSize: guest.complete ? 28 : 26,
                  pulse: guest.complete && !_printing,
                  onPressed: guest.complete && images != null && !_developing && !_printing ? _print : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A shot: rounded, hairline gold; picked = shrinks a little, gold ring + glow, number badge pops.
class _ShotTile extends StatelessWidget {
  const _ShotTile({
    required this.image,
    required this.order,
    required this.dim,
    required this.developing,
    required this.onTap,
  });
  final ui.Image image;
  final int order;
  final bool dim;
  final bool developing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = order >= 0;
    const spring = Cubic(.34, 1.56, .64, 1);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: dim ? 0.42 : 1,
        duration: const Duration(milliseconds: 200),
        child: AnimatedScale(
          scale: on ? 0.965 : 1,
          duration: const Duration(milliseconds: 220),
          curve: spring,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                if (on) const BoxShadow(color: Color(0x73F5E1A4), blurRadius: 28),
                const BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RawImage(image: image, fit: BoxFit.cover),
                  if (developing) const ColoredBox(color: Color(0x400B0B12)),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: on ? Lux.champagneLight : const Color(0x47D4AF6A), width: on ? 3 : 1),
                    ),
                  ),
                  if (on)
                    Positioned(
                      left: 10,
                      top: 10,
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey(order),
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 260),
                        curve: spring,
                        builder: (context, k, child) => Transform.scale(scale: k, child: child),
                        child: Container(
                          width: 46,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: Lux.button,
                            boxShadow: [
                              BoxShadow(color: Color(0x73000000), blurRadius: 14, offset: Offset(0, 4)),
                              BoxShadow(color: Color(0x8CF5E1A4), blurRadius: 18),
                            ],
                          ),
                          child: Text(
                            '${order + 1}',
                            style: LuxFonts.serif(size: 26, weight: FontWeight.w700, color: Lux.goldInk, height: 1),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.name, required this.thumb, required this.on, required this.onTap});
  final String name;
  final ui.Image? thumb;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 98,
        child: Column(
          children: [
            AnimatedSlide(
              offset: Offset(0, on ? -3 / 92 : 0),
              duration: const Duration(milliseconds: 200),
              curve: const Cubic(.34, 1.56, .64, 1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: on ? Lux.champagneLight : const Color(0x47D4AF6A), width: on ? 3 : 1),
                  boxShadow: on ? const [BoxShadow(color: Color(0x73F5E1A4), blurRadius: 22)] : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: thumb == null
                      ? const ColoredBox(color: Color(0xFF17141C))
                      : RawImage(image: thumb, fit: BoxFit.cover),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: LuxFonts.sans(
                  size: 15,
                  height: 1.2,
                  weight: on ? FontWeight.w600 : FontWeight.w400,
                  color: on ? Lux.champagneLight : Lux.ivoryA(0.75),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "⏱ 45 giây"; the last 10 s red, beating once a second.
class _TimerPill extends StatelessWidget {
  const _TimerPill({required this.seconds});
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final urgent = seconds <= 10;
    final pill = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 60,
      padding: const EdgeInsets.fromLTRB(18, 0, 22, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: urgent ? const Color(0x2EE0525A) : const Color(0x9914121E),
        border: Border.all(color: urgent ? Lux.urgent : const Color(0x80D4AF6A)),
        boxShadow: urgent ? const [BoxShadow(color: Color(0x59E0525A), blurRadius: 24)] : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, color: urgent ? Lux.urgentText : Lux.champagne, size: 26),
          const SizedBox(width: 10),
          Text(
            T.now.secondsLeft(seconds.clamp(0, 999)),
            style: LuxFonts.sans(
              size: 24,
              weight: FontWeight.w600,
              color: urgent ? Lux.urgentText : Lux.ivory,
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
    if (!urgent) return pill;
    // A beat (1 → 1.06 → 1) at each new second.
    return TweenAnimationBuilder<double>(
      key: ValueKey(seconds),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1000),
      builder: (context, p, child) =>
          Transform.scale(scale: 1 + 0.06 * Curves.easeInOut.transform(1 - (2 * p - 1).abs()), child: child),
      child: pill,
    );
  }
}
