import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../booth/booth.dart';
import '../config.dart';
import '../ui/lux.dart';
import '../ui/strings.dart';
import '../ui/sparkle.dart';
import 'admin_screen.dart';

/// 1 · Start screen: the event poster (picked in admin, or the designed LPE Sum Up poster)
/// in a breathing column, its blur behind, MAX glitter, "Chạm để bắt đầu" with halos.
/// Hidden admin: 5 taps in the top-right corner, then the PIN.
class IdleScreen extends StatefulWidget {
  const IdleScreen({super.key, required this.booth, required this.onStart});
  final Booth booth;
  final VoidCallback onStart;

  @override
  State<IdleScreen> createState() => _IdleScreenState();
}

class _IdleScreenState extends State<IdleScreen> with TickerProviderStateMixin {
  int _cornerTaps = 0;
  DateTime _firstTap = DateTime(0);
  Timer? _check;
  late final AnimationController _breathe = AnimationController(vsync: this, duration: const Duration(seconds: 10))
    ..repeat(reverse: true);
  late final AnimationController _halo = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat();

  @override
  void initState() {
    super.initState();
    widget.booth.prints.check();
    _check = Timer.periodic(const Duration(seconds: 60), (_) => widget.booth.prints.check());
  }

  @override
  void dispose() {
    _check?.cancel();
    _breathe.dispose();
    _halo.dispose();
    super.dispose();
  }

  void _corner() {
    final now = DateTime.now();
    if (now.difference(_firstTap) > const Duration(seconds: 3)) {
      _firstTap = now;
      _cornerTaps = 0;
    }
    if (++_cornerTaps >= 5) {
      _cornerTaps = 0;
      openAdmin(context, widget.booth);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booth;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onStart,
      child: ColoredBox(
        color: Lux.night,
        child: ListenableBuilder(
          listenable: Listenable.merge([b.startImageVersion, b.settings, lang]),
          builder: (context, _) {
            final file = b.startImage;
            final image = file.existsSync() ? FileImage(file) : null;
            if (image != null && b.startImageVersion.value > 0) image.evict();
            return LayoutBuilder(
              builder: (context, box) => FutureBuilder<double>(
                // The poster column keeps the picture's shape (the designed poster is 590 × 834) at full height.
                future: image == null ? Future.value(590 / 834) : _aspectOf(image),
                builder: (context, snap) {
                  final aspect = snap.data ?? 590 / 834;
                  final posterW = math.min(box.maxWidth, box.maxHeight * aspect);
                  final poster = image == null ? _DesignedPoster(booth: b) : Image(image: image, fit: BoxFit.cover);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // The same poster, huge and blurred, fills the sides.
                      ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                        child: ColorFiltered(
                          colorFilter: const ColorFilter.matrix([
                            0.55,
                            0,
                            0,
                            0,
                            0,
                            0,
                            0.55,
                            0,
                            0,
                            0,
                            0,
                            0,
                            0.6,
                            0,
                            0,
                            0,
                            0,
                            0,
                            1,
                            0,
                          ]),
                          child: Transform.scale(
                            scale: 2.1,
                            child: Center(
                              child: SizedBox(width: posterW, height: box.maxHeight, child: poster),
                            ),
                          ),
                        ),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0x990B0B12), Color(0x330B0B12), Color(0x330B0B12), Color(0x990B0B12)],
                            stops: [0, 0.25, 0.75, 1],
                          ),
                        ),
                      ),
                      // The poster itself, breathing (scale 1 → 1.015 over 10 s).
                      Center(
                        child: AnimatedBuilder(
                          animation: _breathe,
                          builder: (context, child) => Transform.scale(
                            scale: 1 + 0.015 * Curves.easeInOut.transform(_breathe.value),
                            child: child,
                          ),
                          child: Container(
                            width: posterW,
                            height: box.maxHeight,
                            decoration: const BoxDecoration(
                              boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 80)],
                            ),
                            child: poster,
                          ),
                        ),
                      ),
                      // Gold hairlines along the poster's edges.
                      if (posterW < box.maxWidth - 2) ...[
                        Positioned(left: (box.maxWidth - posterW) / 2 - 1, top: 0, bottom: 0, child: const _GoldEdge()),
                        Positioned(left: (box.maxWidth + posterW) / 2, top: 0, bottom: 0, child: const _GoldEdge()),
                      ],
                      const SparkleBackground(level: SparkleLevel.max),
                      Positioned(left: 24, top: 22, child: _StaffChip(booth: b)),
                      // Language for this guest (left of the hidden admin corner).
                      const Positioned(right: 130, top: 22, child: _LangSwitch()),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 64,
                        child: Center(
                          child: SizedBox(
                            width: 440,
                            height: 100,
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.center,
                              children: [
                                _Halo(_halo, delay: 0),
                                _Halo(_halo, delay: 0.5),
                                GoldButton(
                                  label: T.now.start,
                                  onPressed: widget.onStart,
                                  width: 440,
                                  height: 100,
                                  fontSize: 30,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Hidden admin corner.
                      Positioned(
                        right: 0,
                        top: 0,
                        width: 110,
                        height: 110,
                        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _corner),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  static Future<double> _aspectOf(ImageProvider image) {
    final done = Completer<double>();
    final stream = image.resolve(ImageConfiguration.empty);
    late final ImageStreamListener l;
    l = ImageStreamListener(
      (info, _) {
        if (!done.isCompleted) done.complete(info.image.width / info.image.height);
        stream.removeListener(l);
      },
      onError: (_, _) {
        if (!done.isCompleted) done.complete(590 / 834);
      },
    );
    stream.addListener(l);
    return done.future;
  }
}

class _GoldEdge extends StatelessWidget {
  const _GoldEdge();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x00D4AF6A), Lux.champagne, Color(0x00D4AF6A)],
      ),
    ),
  );
}

/// Pill outline growing out of the CTA and fading (2.4 s, the second one half a cycle later).
class _Halo extends StatelessWidget {
  const _Halo(this.anim, {required this.delay});
  final Animation<double> anim;
  final double delay;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: anim,
    builder: (context, _) {
      final p = const Cubic(.2, .7, .3, 1).transform((anim.value + delay) % 1.0);
      return IgnorePointer(
        child: Transform.scale(
          scaleX: 1 + 0.32 * p,
          scaleY: 1 + 0.6 * p,
          child: Container(
            width: 440,
            height: 100,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Lux.champagneLight.withValues(alpha: 0.7 * (1 - p)), width: 1.5),
              boxShadow: [BoxShadow(color: Lux.champagneLight.withValues(alpha: 0.35 * (1 - p)), blurRadius: 30)],
            ),
          ),
        ),
      );
    },
  );
}

/// The designed poster (when no event picture is set): night-navy arch, gold rays, LPE / Sum Up.
class _DesignedPoster extends StatelessWidget {
  const _DesignedPoster({required this.booth});
  final Booth booth;

  @override
  Widget build(BuildContext context) {
    final words = booth.settings.title.trim().split(RegExp(r'\s+'));
    final head = words.first;
    final tail = words.skip(1).join(' ');
    return FittedBox(
      child: SizedBox(
        width: 590,
        height: 834,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.4),
              radius: 1.2,
              colors: [Color(0xFF1D2448), Color(0xFF10132A), Lux.night],
              stops: [0, 0.45, 1],
            ),
          ),
          child: Stack(
            children: [
              const Positioned.fill(child: CustomPaint(painter: _ArchPainter())),
              Positioned(
                left: 0,
                right: 0,
                top: 188,
                child: Column(
                  children: [
                    Text(
                      booth.settings.subtitle.toUpperCase(),
                      style: LuxFonts.eyebrow(size: 14, color: Lux.ivoryA(0.82)).copyWith(letterSpacing: 14 * 0.38),
                    ),
                    const SizedBox(height: 18),
                    const DecoDivider(width: 70),
                    const SizedBox(height: 14),
                    GoldText(head, style: LuxFonts.serif(size: 150, weight: FontWeight.w700, height: 1, spacing: 6)),
                    if (tail.isNotEmpty)
                      Transform.translate(
                        offset: const Offset(0, -4),
                        child: GoldText(
                          tail,
                          style: LuxFonts.serif(size: 92, weight: FontWeight.w400, italic: true, height: 1.05),
                        ),
                      ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(width: 64, height: 1, color: Lux.champagne),
                        const SizedBox(width: 16),
                        Text(
                          '${DateTime.now().year}',
                          style: LuxFonts.serif(size: 30, weight: FontWeight.w400, spacing: 9),
                        ),
                        const SizedBox(width: 16),
                        Container(width: 64, height: 1, color: Lux.champagne),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(booth.settings.dateLine, style: LuxFonts.sans(size: 17, color: Lux.ivoryA(0.72), spacing: 1)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The poster's art-deco arch: two arched frames, rays behind the title, a sunrise at the foot.
class _ArchPainter extends CustomPainter {
  const _ArchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.36);
    final rays = Paint()
      ..strokeWidth = 4
      ..shader = const RadialGradient(colors: [Color(0x24D4AF6A), Color(0x00D4AF6A)])
          .createShader(Rect.fromCircle(center: c, radius: size.height * 0.62));
    for (var a = 0.0; a < 360; a += 7.5) {
      final r = a * math.pi / 180;
      canvas.drawLine(c, c + Offset(math.cos(r), math.sin(r)) * size.height * 0.62, rays);
    }
    RRect arch(double inset, double radius) => RRect.fromRectAndCorners(
      Rect.fromLTRB(inset, inset, size.width - inset, size.height - inset),
      topLeft: Radius.circular(radius),
      topRight: Radius.circular(radius),
      bottomLeft: const Radius.circular(6),
      bottomRight: const Radius.circular(6),
    );
    canvas.drawRRect(
      arch(44, 251),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xD9D4AF6A),
    );
    canvas.drawRRect(
      arch(56, 239),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x6BD4AF6A),
    );
    // Sunrise at the foot.
    final foot = Offset(size.width / 2, size.height - 57);
    final sun = Paint()
      ..strokeWidth = 3
      ..shader = const RadialGradient(
        colors: [Color(0x42D4AF6A), Color(0x00D4AF6A)],
        stops: [0.3, 0.72],
      ).createShader(Rect.fromCircle(center: foot, radius: 200));
    for (var a = 180.0; a <= 360; a += 10) {
      final r = a * math.pi / 180;
      canvas.drawLine(foot, foot + Offset(math.cos(r), math.sin(r)) * 200, sun);
    }
    for (final (r, color) in [(110.0, const Color(0x99D4AF6A)), (75.0, const Color(0x73D4AF6A))]) {
      canvas.drawArc(
        Rect.fromCircle(center: foot, radius: r),
        math.pi,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_ArchPainter old) => false;
}

/// For the staff: uploads waiting (amber), plus the printer when printing is on.
class _StaffChip extends StatelessWidget {
  const _StaffChip({required this.booth});
  final Booth booth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([booth.prints, booth.uploads, booth.settings]),
      builder: (context, _) {
        final pending = booth.uploads.pendingSessions;
        final failing = booth.uploads.failingSessions;
        final printerOk = booth.settings.printerUrl == null ? false : booth.prints.printerOk;
        Widget dot(Color c, IconData icon) => Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.withValues(alpha: 0.2)),
          child: Icon(icon, size: 14, color: c),
        );
        return Glass(
          radius: 999,
          padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              dot(pending == 0 ? const Color(0xFF7BD389) : Lux.amber, pending == 0 ? Icons.check : Icons.arrow_upward),
              const SizedBox(width: 8),
              Text(
                pending == 0 ? 'đã lên hết' : '$pending chờ${failing > 0 ? ' · $failing thử lại' : ''}',
                style: LuxFonts.sans(size: 15, weight: FontWeight.w500),
              ),
              if (PRINTING) ...[
                const SizedBox(width: 14),
                dot(printerOk == true ? const Color(0xFF7BD389) : Lux.urgent, Icons.print),
                const SizedBox(width: 8),
                Text(
                  printerOk == true ? 'máy in ok' : 'máy in?',
                  style: LuxFonts.sans(size: 15, weight: FontWeight.w500),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Tiếng Việt · English · 日本語, the current one in gold.
class _LangSwitch extends StatelessWidget {
  const _LangSwitch();

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 999,
      padding: const EdgeInsets.all(5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final l in Lang.values)
            GestureDetector(
              onTap: () => lang.value = l,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: l == lang.value ? Lux.button : null,
                ),
                child: Text(
                  l.name,
                  style: LuxFonts.sans(
                    size: 18,
                    weight: FontWeight.w600,
                    color: l == lang.value ? Lux.goldInk : Lux.ivoryA(0.8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
