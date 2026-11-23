import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// LPE Sum Up design (Claude Design export, "Style guide" + "Animation & thông số in"):
// deep night background, champagne metal gold, ivory text, glass panels.

abstract final class Lux {
  static const night = Color(0xFF0B0B12);
  static const navy = Color(0xFF141A33);
  static const champagne = Color(0xFFD4AF6A);
  static const champagneLight = Color(0xFFF5E1A4);
  static const goldDeep = Color(0xFF9C7A3F);
  static const goldInk = Color(0xFF1A1408);
  static const ivory = Color(0xFFF8F3E8);
  static const rose = Color(0xFFE9C7C0);
  static const urgent = Color(0xFFE0525A);
  static const urgentText = Color(0xFFFFB3B7);
  static const amber = Color(0xFFE8B04A);
  static const flash = Color(0xFFFFFDF7);

  static Color ivoryA(double a) => ivory.withValues(alpha: a);

  /// Metal for text and lines (100°, 220 % wide so it can sweep).
  static const metal = [
    Color(0xFF9C7A3F),
    Color(0xFFD4AF6A),
    Color(0xFFF5E1A4),
    Color(0xFFFFF6DA),
    Color(0xFFF5E1A4),
    Color(0xFFD4AF6A),
    Color(0xFF9C7A3F),
  ];
  static const metalStops = [0.0, 0.22, 0.45, 0.5, 0.55, 0.78, 1.0];

  /// Gold ink for gold on ivory paper (prints).
  static const ink = [Color(0xFF6E5223), Color(0xFF9C7A3F), Color(0xFFC9A35C), Color(0xFF9C7A3F), Color(0xFF6E5223)];

  /// Gold button face (180°).
  static const button = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF5E1A4), Color(0xFFE6C886), Color(0xFFD4AF6A), Color(0xFFB8914F)],
    stops: [0, 0.4, 0.7, 1],
  );

  /// Screen background behind the panels (navy glow from the top, rose / gold from the corners).
  static const backdrop = BoxDecoration(
    color: night,
    gradient: RadialGradient(
      center: Alignment(0, -1.1),
      radius: 1.1,
      colors: [Color(0x8C28305C), Color(0x000B0B12)],
    ),
  );
}

/// Fonts: Playfair Display (titles) and Be Vietnam Pro (everything else), from Google Fonts.
/// Off in tests (no network): plain styles then.
abstract final class LuxFonts {
  static bool enabled = false;

  static TextStyle serif({double size = 38, FontWeight weight = FontWeight.w600, bool italic = false, Color? color, double? height, double? spacing}) {
    final s = TextStyle(
      fontSize: size,
      fontWeight: weight,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      color: color ?? Lux.ivory,
      height: height,
      letterSpacing: spacing,
    );
    return enabled ? GoogleFonts.playfairDisplay(textStyle: s) : s.copyWith(fontFamily: 'Georgia');
  }

  static TextStyle sans({double size = 20, FontWeight weight = FontWeight.w400, Color? color, double? height, double? spacing}) {
    final s = TextStyle(fontSize: size, fontWeight: weight, color: color ?? Lux.ivory, height: height, letterSpacing: spacing);
    return enabled ? GoogleFonts.beVietnamPro(textStyle: s) : s;
  }

  /// Small caps label in rose ("BƯỚC 1 / 3").
  static TextStyle eyebrow({double size = 15, Color color = Lux.rose}) =>
      sans(size: size, weight: FontWeight.w600, color: color, spacing: size * 0.24);

  /// Starts loading every weight the app uses; waits a little so the first screen has them.
  static Future<void> warmUp() async {
    enabled = true;
    for (final w in [FontWeight.w400, FontWeight.w600, FontWeight.w700]) {
      serif(weight: w);
      serif(weight: w, italic: true);
    }
    for (final w in [FontWeight.w300, FontWeight.w400, FontWeight.w500, FontWeight.w600]) {
      sans(weight: w);
    }
    try {
      await GoogleFonts.pendingFonts().timeout(const Duration(seconds: 6));
    } catch (_) {
      // Offline on the first launch: system fonts until the next start.
    }
  }
}

/// Text painted with the metal gradient. [sweep]: the light slides across every 6 s.
class GoldText extends StatefulWidget {
  const GoldText(this.text, {super.key, required this.style, this.sweep = true, this.align = TextAlign.center, this.ink = false});
  final String text;
  final TextStyle style;
  final bool sweep;
  final TextAlign align;

  /// Darker gold for light backgrounds.
  final bool ink;

  @override
  State<GoldText> createState() => _GoldTextState();
}

class _GoldTextState extends State<GoldText> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    if (widget.sweep) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(widget.text, textAlign: widget.align, style: widget.style.copyWith(color: Colors.white));
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        // 100% → 0% → 100% of a 220 % wide gradient.
        final p = Curves.easeInOutCubic.transform(_c.value < 0.5 ? _c.value * 2 : 2 - _c.value * 2);
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) {
            final w = rect.width * 2.2;
            final dx = -(rect.width * 1.2) * (1 - p);
            return LinearGradient(
              colors: widget.ink ? Lux.ink : Lux.metal,
              stops: widget.ink ? null : Lux.metalStops,
              transform: const GradientRotation(0.17),
            ).createShader(Rect.fromLTWH(rect.left + dx, rect.top, w, rect.height));
          },
          child: child,
        );
      },
      child: text,
    );
  }
}

/// Dark glass panel: blur 18, gold hairline, soft shadow.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.radius = 30, this.padding = EdgeInsets.zero, this.width, this.height, this.border});
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final double? width;
  final double? height;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 60, offset: Offset(0, 20))],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: r,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x9E1E1C2A), Color(0xBD0E0D16)],
              ),
              border: border ?? Border.all(color: const Color(0x47D4AF6A)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Gold pill button: metal face, light shimmer every 3 s, sinks and glows when pressed.
class GoldButton extends StatefulWidget {
  const GoldButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.width,
    this.height = 88,
    this.fontSize = 28,
    this.icon,
    this.iconAfter = false,
    this.pulse = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final double? width;
  final double height;
  final double fontSize;
  final IconData? icon;
  final bool iconAfter;

  /// "Ready" glow (1.8 s) on the button that finishes the step.
  final bool pulse;

  @override
  State<GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<GoldButton> with TickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  bool _down = false;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(GoldButton old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    if (!widget.pulse && _pulse.isAnimating) _pulse.stop();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final fg = enabled ? Lux.goldInk : Lux.ivoryA(0.45);
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null && !widget.iconAfter) ...[Icon(widget.icon, color: fg, size: widget.fontSize), const SizedBox(width: 14)],
        Text(widget.label, style: LuxFonts.sans(size: widget.fontSize, weight: FontWeight.w600, color: fg, spacing: widget.fontSize * 0.01)),
        if (widget.icon != null && widget.iconAfter) ...[const SizedBox(width: 14), Icon(widget.icon, color: fg, size: widget.fontSize)],
      ],
    );
    final r = BorderRadius.circular(999);
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: () => setState(() => _down = false),
      onTapUp: enabled
          ? (_) {
              setState(() => _down = false);
              widget.onPressed!();
            }
          : null,
      child: AnimatedBuilder(
        animation: Listenable.merge([_shimmer, _pulse]),
        builder: (context, child) {
          final glow = widget.pulse ? Curves.easeInOut.transform(_pulse.value) : 0.0;
          return AnimatedScale(
            scale: _down ? 0.97 : 1,
            duration: Duration(milliseconds: _down ? 140 : 220),
            curve: _down ? const Cubic(.2, .8, .2, 1) : Curves.easeOutBack,
            child: AnimatedSlide(
              offset: Offset(0, _down ? 3 / widget.height : 0),
              duration: const Duration(milliseconds: 140),
              child: Container(
                width: widget.width,
                height: widget.height,
                decoration: BoxDecoration(
                  borderRadius: r,
                  gradient: enabled
                      ? Lux.button
                      : const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF4A4434), Color(0xFF3A3528)]),
                  border: Border.all(color: enabled ? const Color(0x99FFF4D6) : const Color(0x40D4AF6A)),
                  boxShadow: enabled
                      ? [
                          BoxShadow(color: Lux.champagne.withValues(alpha: 0.28 + 0.3 * glow), blurRadius: 30 + 18 * glow, offset: const Offset(0, 10)),
                          const BoxShadow(color: Color(0x80000000), blurRadius: 6, offset: Offset(0, 2)),
                          if (_down) const BoxShadow(color: Color(0xBFF5E1A4), blurRadius: 44),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: r,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (enabled) Positioned.fill(child: CustomPaint(painter: _ShimmerPainter(_shimmer.value))),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: child),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
        child: Center(widthFactor: 1, child: label),
      ),
    );
  }
}

/// White band (45 % wide, −20°) crossing the button in the first 28 % of each cycle.
class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t > 0.28) return;
    final p = Curves.fastOutSlowIn.transform(t / 0.28);
    final w = size.width * 0.45;
    final x = -size.width * 0.6 + p * size.width * 1.9;
    canvas.save();
    canvas.translate(x + w / 2, size.height / 2);
    canvas.skew(-0.36, 0);
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: size.height * 1.4);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(colors: [Color(0x00FFFFFF), Color(0xCCFFFFFF), Color(0x00FFFFFF)]).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.t != t;
}

/// Outlined glass pill (secondary action).
class LineButton extends StatefulWidget {
  const LineButton({super.key, required this.label, required this.onPressed, this.icon, this.width, this.height = 84, this.fontSize = 26});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double? width;
  final double height;
  final double fontSize;

  @override
  State<LineButton> createState() => _LineButtonState();
}

class _LineButtonState extends State<LineButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled
            ? (_) {
                setState(() => _down = false);
                widget.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.98 : 1,
          duration: const Duration(milliseconds: 140),
          child: Container(
            width: widget.width,
            height: widget.height,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: _down ? const Color(0x29D4AF6A) : const Color(0x590B0B12),
              border: Border.all(color: const Color(0xB3D4AF6A), width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[Icon(widget.icon, color: Lux.ivory, size: widget.fontSize), const SizedBox(width: 10)],
                Text(widget.label, style: LuxFonts.sans(size: widget.fontSize, weight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ─◇◆◇─ art-deco divider.
class DecoDivider extends StatelessWidget {
  const DecoDivider({super.key, this.width = 80});
  final double width;

  @override
  Widget build(BuildContext context) {
    Widget line(bool left) => Container(
          width: width,
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: left ? const [Color(0x00D4AF6A), Lux.champagne] : const [Lux.champagne, Color(0x00D4AF6A)]),
          ),
        );
    Widget diamond(double s, bool filled) => Transform.rotate(
          angle: 0.785,
          child: Container(
            width: s,
            height: s,
            decoration: BoxDecoration(color: filled ? Lux.champagne : null, border: filled ? null : Border.all(color: Lux.champagne)),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [line(true), const SizedBox(width: 12), diamond(7, false), const SizedBox(width: 12), diamond(6, true), const SizedBox(width: 12), diamond(7, false), const SizedBox(width: 12), line(false)],
    );
  }
}

/// Fade + scale 1.02 → 1 page change (380 ms, easeOutQuint).
Widget luxTransition(Widget child, Animation<double> anim) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutQuint),
      child: ScaleTransition(scale: Tween(begin: 1.02, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutQuint)), child: child),
    );
