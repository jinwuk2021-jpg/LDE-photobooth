import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'lux.dart';

/// How much glitter a screen gets (design "Mức nền lấp lánh"): MAX on the start and
/// thank-you screens, MID on the pickers, LOW over the camera (no beams, no bokeh).
enum SparkleLevel { max, mid, low }

/// Gold dust, falling glitter, bokeh, 4-point glints, cross flares, gala spotlights and a
/// light sweep, all in one CustomPainter driven by one Ticker.
class SparkleBackground extends StatefulWidget {
  const SparkleBackground({super.key, this.level = SparkleLevel.mid, this.seed = 7});
  final SparkleLevel level;
  final int seed;

  @override
  State<SparkleBackground> createState() => _SparkleBackgroundState();
}

class _SparkleBackgroundState extends State<SparkleBackground> with SingleTickerProviderStateMixin {
  late final _field = _Field(widget.level, widget.seed);
  final _time = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker((d) => _time.value = d.inMicroseconds / 1e6)..start();

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(child: CustomPaint(painter: _SparklePainter(_field, _time), size: Size.infinite)),
    );
  }
}

class _Dust {
  _Dust(math.Random r)
      : x = r.nextDouble(),
        y = r.nextDouble(),
        size = 1.8 + r.nextDouble() * (r.nextDouble() < 0.18 ? 5.7 : 2.2),
        drift = 8 + r.nextDouble() * 8,
        rise = 50 + r.nextDouble() * 40,
        twinkle = 1.8 + r.nextDouble() * 2.2,
        phase = r.nextDouble() * 20;
  final double x, y, size, drift, rise, twinkle, phase;
  bool get big => size > 4;
}

class _Rain {
  _Rain(math.Random r)
      : x = r.nextDouble(),
        fall = 7 + r.nextDouble() * 7,
        flip = 0.6 + r.nextDouble() * 0.7,
        size = 2.5 + r.nextDouble() * 3,
        phase = r.nextDouble() * 14;
  final double x, fall, flip, size, phase;
}

class _Bokeh {
  _Bokeh(math.Random r)
      : x = r.nextDouble(),
        y = r.nextDouble(),
        radius = 45 + r.nextDouble() * 105,
        rose = r.nextBool(),
        ring = r.nextDouble() < 0.4,
        period = 10 + r.nextDouble() * 10,
        phase = r.nextDouble() * 20;
  final double x, y, radius, period, phase;
  final bool rose, ring;
}

class _Glint {
  _Glint(math.Random r, {required this.flare})
      : x = r.nextDouble(),
        y = r.nextDouble(),
        size = flare ? 70 + r.nextDouble() * 80 : 10 + r.nextDouble() * 12,
        period = flare ? 4.6 + r.nextDouble() * 2.4 : 4.6,
        phase = r.nextDouble() * 7;
  final bool flare;
  final double x, y, size, period, phase;
}

class _Field {
  _Field(SparkleLevel level, int seed) : this._(level, math.Random(seed));
  _Field._(this.level, math.Random r)
      : dust = List.generate(const {SparkleLevel.max: 80, SparkleLevel.mid: 50, SparkleLevel.low: 24}[level]!, (_) => _Dust(r)),
        rain = List.generate(const {SparkleLevel.max: 64, SparkleLevel.mid: 38, SparkleLevel.low: 20}[level]!, (_) => _Rain(r)),
        bokeh = level == SparkleLevel.low ? [] : List.generate(level == SparkleLevel.max ? 12 : 9, (_) => _Bokeh(r)),
        glints = List.generate(level == SparkleLevel.max ? 16 : (level == SparkleLevel.mid ? 11 : 7), (_) => _Glint(r, flare: false)),
        flares = List.generate(level == SparkleLevel.max ? 7 : (level == SparkleLevel.mid ? 4 : 2), (_) => _Glint(r, flare: true));
  final SparkleLevel level;
  final List<_Dust> dust;
  final List<_Rain> rain;
  final List<_Bokeh> bokeh;
  final List<_Glint> glints;
  final List<_Glint> flares;
}

double _wave(double t, double period, double phase) => 0.5 - 0.5 * math.cos(2 * math.pi * ((t + phase) / period));

class _SparklePainter extends CustomPainter {
  _SparklePainter(this.f, this.time) : super(repaint: time);
  final _Field f;
  final ValueNotifier<double> time;

  static const _gold = Color(0xFFF5E1A4);

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final add = Paint()..blendMode = BlendMode.plus;

    // Gala spotlights: cones from the top edge, swinging.
    if (f.level != SparkleLevel.low) {
      for (final (i, x) in [0.14, 0.5, 0.86].indexed) {
        if (f.level == SparkleLevel.mid && i == 1) continue;
        final swing = _wave(t, 8 + i * 1.5, i * 3.0);
        final angle = (i == 0 ? 1 : (i == 2 ? -1 : 0.3)) * (0.14 + swing * 0.45);
        final alpha = 0.045 + swing * 0.04;
        canvas.save();
        canvas.translate(size.width * x, -20);
        canvas.rotate(angle);
        final cone = Path()
          ..moveTo(-14, 0)
          ..lineTo(14, 0)
          ..lineTo(size.height * 0.42, size.height * 1.25)
          ..lineTo(-size.height * 0.42, size.height * 1.25)
          ..close();
        canvas.drawPath(
          cone,
          Paint()
            ..blendMode = BlendMode.screen
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_gold.withValues(alpha: alpha * 2.2), _gold.withValues(alpha: 0)],
            ).createShader(Rect.fromLTWH(-size.height * 0.42, 0, size.height * 0.84, size.height * 1.25)),
        );
        canvas.restore();
      }
    }

    // Bokeh and soft rings.
    for (final b in f.bokeh) {
      final k = _wave(t, b.period, b.phase);
      final c = Offset((b.x + 0.03 * (k - 0.5)) * size.width, (b.y - 0.04 * k) * size.height);
      final color = b.rose ? Lux.rose : (b.radius > 100 ? Lux.champagne : _gold);
      if (b.ring) {
        canvas.drawCircle(
          c,
          b.radius * 0.35,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = _gold.withValues(alpha: 0.22 + 0.12 * k),
        );
      } else {
        canvas.drawCircle(
          c,
          b.radius,
          Paint()
            ..shader = RadialGradient(colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: b.radius)),
        );
      }
    }

    // Gold dust drifting up and twinkling (the big ones glow).
    for (final d in f.dust) {
      final k = _wave(t, d.drift, d.phase);
      final c = Offset(d.x * size.width + 12 * math.sin((t + d.phase) / d.drift * 2 * math.pi), d.y * size.height - d.rise * k);
      final a = 0.15 + 0.8 * _wave(t, d.twinkle, d.phase);
      if (d.big) canvas.drawCircle(c, d.size * 1.8, Paint()..color = _gold.withValues(alpha: a * 0.25)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      canvas.drawCircle(c, d.size / 2, add..color = _gold.withValues(alpha: a));
    }

    // Glitter rain: diamonds falling the whole height, flipping (the flash when face-on).
    for (final g in f.rain) {
      final p = ((t + g.phase) / g.fall) % 1.0;
      final flip = math.cos(2 * math.pi * ((t + g.phase) / g.flip));
      final c = Offset(g.x * size.width, -20 + p * (size.height + 40));
      final w = g.size * flip.abs().clamp(0.15, 1.0);
      final path = Path()
        ..moveTo(c.dx, c.dy - g.size)
        ..lineTo(c.dx + w / 2, c.dy)
        ..lineTo(c.dx, c.dy + g.size)
        ..lineTo(c.dx - w / 2, c.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = Color.lerp(Lux.champagne, Colors.white, flip.abs() > 0.92 ? 0.8 : 0)!.withValues(alpha: 0.75));
    }

    // 4-point glints (visible 68 → 92 % of each 4.6 s) and big cross flares.
    for (final g in [...f.glints, ...f.flares]) {
      final cyc = ((t + g.phase) / g.period) % 1.0;
      final lo = g.flare ? 0.58 : 0.68, hi = g.flare ? 0.88 : 0.92;
      if (cyc < lo || cyc > hi) continue;
      final k = math.sin(math.pi * (cyc - lo) / (hi - lo));
      final c = Offset(g.x * size.width, g.y * size.height);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate((g.flare ? 0.49 : 1.57) * k);
      final s = g.size / 2 * (g.flare ? 0.2 + 0.8 * k : k);
      final thin = g.flare ? s * 0.035 + 1 : s * 0.22;
      final star = Path()
        ..moveTo(0, -s)
        ..quadraticBezierTo(thin, -thin, s, 0)
        ..quadraticBezierTo(thin, thin, 0, s)
        ..quadraticBezierTo(-thin, thin, -s, 0)
        ..quadraticBezierTo(-thin, -thin, 0, -s)
        ..close();
      canvas.drawPath(star, add..color = Colors.white.withValues(alpha: 0.85 * k));
      if (g.flare) {
        canvas.drawCircle(Offset.zero, 9, Paint()..color = _gold.withValues(alpha: 0.6 * k)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9));
      }
      canvas.restore();
    }

    // Diagonal light sweep: 3.15 s across, every 7 s.
    if (f.level != SparkleLevel.low) {
      final cyc = (t % 7) / 7;
      if (cyc < 0.45) {
        final p = const Cubic(.45, 0, .55, 1).transform(cyc / 0.45);
        final w = size.width * 0.32;
        canvas.save();
        canvas.translate(-w + p * (size.width + 2 * w), 0);
        canvas.skew(-0.32, 0);
        final r = Rect.fromLTWH(0, -50, w, size.height + 100);
        canvas.drawRect(
          r,
          Paint()
            ..blendMode = BlendMode.screen
            ..shader = const LinearGradient(colors: [Color(0x00F8F3E8), Color(0x24F8F3E8), Color(0x00F8F3E8)]).createShader(r),
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.f != f;
}

/// Spark burst from the middle right after the shutter (20 rays, 760 ms).
class SparkBurst extends StatelessWidget {
  const SparkBurst({super.key, required this.progress});

  /// 0 → 1 over the burst; hidden outside (0, 1).
  final double progress;

  @override
  Widget build(BuildContext context) => IgnorePointer(child: CustomPaint(painter: _BurstPainter(progress), size: Size.infinite));
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.p);
  final double p;

  @override
  void paint(Canvas canvas, Size size) {
    if (p <= 0 || p >= 1) return;
    final e = const Cubic(.15, .8, .3, 1).transform(p);
    final c = Offset(size.width / 2, size.height * 0.46);
    final fade = 1 - p;
    for (var i = 0; i < 20; i++) {
      final a = i * math.pi / 10 + (i.isOdd ? 0.12 : 0);
      final dist = (230 + (i * 37) % 130) * e;
      final pos = c + Offset(math.cos(a), math.sin(a)) * dist;
      if (i % 5 == 1) {
        // A small 4-point star among the rays.
        final s = 16 * fade;
        final star = Path()
          ..moveTo(pos.dx, pos.dy - s)
          ..lineTo(pos.dx + s * 0.25, pos.dy)
          ..lineTo(pos.dx, pos.dy + s)
          ..lineTo(pos.dx - s * 0.25, pos.dy)
          ..close();
        canvas.drawPath(star, Paint()..color = Colors.white.withValues(alpha: fade));
      } else {
        final tail = pos - Offset(math.cos(a), math.sin(a)) * 26 * fade;
        canvas.drawLine(
          tail,
          pos,
          Paint()
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFFF5E1A4).withValues(alpha: fade),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.p != p;
}

/// Falling confetti for the thank-you screen (46 pieces: gold, rose, ivory; spinning, swaying).
class Confetti extends StatefulWidget {
  const Confetti({super.key});

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  final _time = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker((d) => _time.value = d.inMicroseconds / 1e6)..start();
  final _r = math.Random(11);
  late final _pieces = List.generate(
    46,
    (_) => (
      x: _r.nextDouble(),
      w: 6 + _r.nextDouble() * 6,
      h: 8 + _r.nextDouble() * 16,
      fall: 4.5 + _r.nextDouble() * 3,
      sway: 1.6 + _r.nextDouble(),
      spin: 420 + _r.nextDouble() * 120,
      phase: _r.nextDouble() * 8,
      color: [Lux.champagneLight, Lux.champagne, Lux.rose, Lux.ivory, const Color(0xFFE6C886)][_r.nextInt(5)],
      round: _r.nextDouble() < 0.12,
    ),
  );

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _ConfettiPainter(_pieces, _time),
          ),
        ),
      );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.time) : super(repaint: time);
  final List<({double x, double w, double h, double fall, double sway, double spin, double phase, Color color, bool round})> pieces;
  final ValueNotifier<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    for (final c in pieces) {
      final p = ((t + c.phase) / c.fall) % 1.0;
      final sway = 26 * math.sin(2 * math.pi * (t + c.phase) / c.sway);
      canvas.save();
      canvas.translate(c.x * size.width + sway, -30 + p * (size.height + 60));
      canvas.rotate(p * c.spin * math.pi / 180);
      final flip = math.cos(2 * math.pi * (t + c.phase) / 1.3).abs().clamp(0.2, 1.0);
      final r = Rect.fromCenter(center: Offset.zero, width: c.w * flip, height: c.round ? c.w : c.h);
      final paint = Paint()..color = c.color.withValues(alpha: 0.92);
      c.round ? canvas.drawOval(r, paint) : canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(2)), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
