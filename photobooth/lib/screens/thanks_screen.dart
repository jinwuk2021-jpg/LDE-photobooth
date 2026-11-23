import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../booth/booth.dart';
import '../booth/print_layout.dart';
import '../config.dart';
import '../ui/lux.dart';
import '../ui/strings.dart';
import '../ui/sparkle.dart';

/// 5 · "Xong rồi!": confetti, the QR in a white tile with a gold light running round it, the
/// print floating beside, a gold bar running out over [THANKS_TIMEOUT] (or "Xong").
class ThanksScreen extends StatefulWidget {
  const ThanksScreen({super.key, required this.finished, required this.onDone});
  final Finished finished;
  final VoidCallback onDone;

  @override
  State<ThanksScreen> createState() => _ThanksScreenState();
}

class _ThanksScreenState extends State<ThanksScreen> with TickerProviderStateMixin {
  late final AnimationController _left = AnimationController(vsync: this, duration: THANKS_TIMEOUT)..forward();
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 3))
    ..repeat();
  late final AnimationController _float = AnimationController(vsync: this, duration: const Duration(seconds: 4))
    ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _left.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void dispose() {
    _left.dispose();
    _spin.dispose();
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aspect = widget.finished.aspect;
    // The print: 420 wide when landscape, 400 tall when portrait.
    final printSize = aspect >= 1 ? Size(420, 420 / aspect) : Size(400 * aspect, 400);
    return DecoratedBox(
      decoration: Lux.backdrop,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const SparkleBackground(level: SparkleLevel.max, seed: 57),
          const Confetti(),
          Positioned(
            left: 0,
            right: 0,
            top: 46,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutQuint,
              builder: (context, p, child) => Opacity(
                opacity: p,
                child: Transform.translate(offset: Offset(0, 20 * (1 - p)), child: child),
              ),
              child: Column(
                children: [
                  GoldText(
                    PRINTING ? T.now.printing : T.now.allDone,
                    style: LuxFonts.serif(size: 92, weight: FontWeight.w700, height: 1.08),
                  ),
                  const SizedBox(height: 6),
                  Text(T.now.scanToGet, style: LuxFonts.sans(size: 32, weight: FontWeight.w500)),
                ],
              ),
            ),
          ),
          Positioned(
            left: 40,
            right: 0,
            top: 232,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    _RunningQr(url: widget.finished.url, spin: _spin),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(Icons.photo_camera_outlined, size: 20, color: Lux.ivoryA(0.7)),
                        const SizedBox(width: 8),
                        Text(T.now.openCamera, style: LuxFonts.sans(size: 17, color: Lux.ivoryA(0.7))),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 84),
                // Floating print: y 0 ↔ −8, tilt 4° ↔ 3°.
                AnimatedBuilder(
                  animation: _float,
                  builder: (context, child) {
                    final k = Curves.easeInOut.transform(_float.value);
                    return Transform.translate(
                      offset: Offset(0, -8 * k),
                      child: Transform.rotate(angle: (4 - k) * math.pi / 180, child: child),
                    );
                  },
                  child: Container(
                    width: printSize.width,
                    height: printSize.height,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0x59D4AF6A)),
                      boxShadow: const [BoxShadow(color: Color(0xA6000000), blurRadius: 60, offset: Offset(0, 30))],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(File(widget.finished.printPath), fit: BoxFit.cover),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 640,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.auto_awesome, color: Lux.rose, size: 22),
                    const SizedBox(width: 10),
                    Text(T.now.videosLater, style: LuxFonts.sans(size: 19, color: Lux.ivoryA(0.78))),
                  ],
                ),
                const SizedBox(height: 18),
                GoldButton(label: T.now.done, width: 280, height: 84, onPressed: widget.onDone),
              ],
            ),
          ),
          // Auto return: seconds left and the gold bar at the bottom.
          AnimatedBuilder(
            animation: _left,
            builder: (context, _) {
              final secs = (THANKS_TIMEOUT.inSeconds * (1 - _left.value)).ceil();
              return Stack(
                children: [
                  Positioned(
                    right: 28,
                    bottom: 16,
                    child: Text(T.now.backIn(secs), style: LuxFonts.sans(size: 15, color: Lux.ivoryA(0.55))),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 4,
                    child: ColoredBox(
                      color: const Color(0x24D4AF6A),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: 1 - _left.value,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: Lux.metal, stops: Lux.metalStops),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 332 pt tile: a gold sweep (bright from 230° to 360°) spinning behind a white QR card.
class _RunningQr extends StatelessWidget {
  const _RunningQr({required this.url, required this.spin});
  final String url;
  final Animation<double> spin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 332,
      height: 332,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: const Color(0x47D4AF6A),
        boxShadow: const [BoxShadow(color: Color(0x47D4AF6A), blurRadius: 60)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: spin,
              builder: (context, _) => Transform.rotate(
                angle: spin.value * 2 * math.pi,
                child: Container(
                  width: 520,
                  height: 520,
                  decoration: const BoxDecoration(
                    gradient: SweepGradient(
                      colors: [
                        Color(0x00D4AF6A),
                        Color(0x00D4AF6A),
                        Lux.champagne,
                        Color(0xFFFFF6DA),
                        Color(0x00D4AF6A),
                      ],
                      stops: [0, 230 / 360, 290 / 360, 340 / 360, 1],
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: 320,
              height: 320,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: CustomPaint(painter: QrPainter(url)),
            ),
          ],
        ),
      ),
    );
  }
}
