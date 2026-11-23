import 'package:flutter/material.dart';

import '../booth/print_layout.dart';
import '../services/settings.dart';
import '../ui/lux.dart';
import '../ui/strings.dart';
import '../ui/sparkle.dart';

/// 2 · "Chọn khung ảnh": a glass card per frame with its print drawn small; tap one (it lifts,
/// glows, gets a ✓, the others dim), then "Bắt đầu chụp".
class LayoutScreen extends StatefulWidget {
  const LayoutScreen({super.key, required this.settings, required this.onPick, required this.onBack});
  final BoothSettings settings;
  final ValueChanged<BoothLayout> onPick;
  final VoidCallback onBack;

  @override
  State<LayoutScreen> createState() => _LayoutScreenState();
}

class _LayoutScreenState extends State<LayoutScreen> {
  BoothLayout? _picked;

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    return DecoratedBox(
      decoration: Lux.backdrop,
      child: Stack(
        children: [
          const SparkleBackground(level: SparkleLevel.mid, seed: 21),
          Positioned(
            left: 0,
            right: 0,
            top: 50,
            child: Column(
              children: [
                Text(T.now.step1, style: LuxFonts.eyebrow()),
                const SizedBox(height: 10),
                GoldText(T.now.chooseFrame, style: LuxFonts.serif(size: 64, weight: FontWeight.w600, height: 1.15)),
                const SizedBox(height: 10),
                const DecoDivider(),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 236,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final layout in BoothLayout.values) ...[
                  _FrameCard(
                    layout: layout,
                    settings: widget.settings,
                    on: picked == layout,
                    dim: picked != null && picked != layout,
                    onTap: () => setState(() => _picked = layout),
                  ),
                  if (layout != BoothLayout.values.last) const SizedBox(width: 28),
                ],
              ],
            ),
          ),
          Positioned(
            left: 48,
            right: 48,
            bottom: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                LineButton(label: T.now.back, icon: Icons.arrow_back, onPressed: widget.onBack, width: 220),
                GoldButton(
                  label: picked == null ? T.now.tapAFrame : T.now.startShooting,
                  icon: picked == null ? null : Icons.arrow_forward,
                  iconAfter: true,
                  width: 380,
                  onPressed: picked == null ? null : () => widget.onPick(picked),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FrameCard extends StatelessWidget {
  const _FrameCard({
    required this.layout,
    required this.settings,
    required this.on,
    required this.dim,
    required this.onTap,
  });
  final BoothLayout layout;
  final BoothSettings settings;
  final bool on;
  final bool dim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The print at 270 pt tall (landscape: 290 wide).
    final preview = layout.landscape ? const Size(290, 196) : const Size(176, 260.5);
    const spring = Cubic(.34, 1.56, .64, 1);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: dim ? 0.62 : 1,
        duration: const Duration(milliseconds: 240),
        child: AnimatedSlide(
          offset: Offset(0, on ? -16 / 420 : 0),
          duration: const Duration(milliseconds: 260),
          curve: spring,
          child: AnimatedScale(
            scale: on ? 1.03 : 1,
            duration: const Duration(milliseconds: 260),
            curve: spring,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: on
                        ? const [
                            BoxShadow(color: Color(0x61F5E1A4), blurRadius: 42),
                            BoxShadow(color: Color(0x8C000000), blurRadius: 60, offset: Offset(0, 30)),
                          ]
                        : null,
                  ),
                  child: Glass(
                    radius: 28,
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                    border: Border.all(color: on ? Lux.champagneLight : const Color(0x47D4AF6A), width: on ? 1.5 : 1),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 270,
                          width: preview.width,
                          child: Center(
                            child: Container(
                              width: preview.width,
                              height: preview.height,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: const [
                                  BoxShadow(color: Color(0x8C000000), blurRadius: 40, offset: Offset(0, 18)),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: CustomPaint(
                                  painter: PrintPainter(
                                    PrintSpec(
                                      layout: layout,
                                      photos: const [],
                                      title: settings.title,
                                      dateLine: settings.dateLine,
                                      subtitle: settings.subtitle,
                                      qrSlot: true,
                                      scanHint: T.now.printScanHint,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          layout.label,
                          style: LuxFonts.serif(
                            size: 36,
                            weight: FontWeight.w600,
                            height: 1,
                            color: on ? Lux.champagneLight : Lux.ivory,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(_hint(layout), style: LuxFonts.sans(size: 16, color: Lux.ivoryA(0.68))),
                      ],
                    ),
                  ),
                ),
                if (on)
                  Positioned(
                    top: -14,
                    right: -14,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 260),
                      curve: spring,
                      builder: (context, k, child) => Transform.scale(scale: k, child: child),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: Lux.button,
                          boxShadow: [BoxShadow(color: Color(0x99F5E1A4), blurRadius: 24)],
                        ),
                        child: const Icon(Icons.check, color: Lux.goldInk, size: 26),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _hint(BoothLayout layout) {
  final t = T.now;
  return t.frameHint(layout.picks, switch (layout) {
    BoothLayout.cut2 => t.portrait,
    BoothLayout.cut3 => t.titleBand,
    BoothLayout.cut4 => t.landscape,
    BoothLayout.cut6 => t.twoColumns,
  });
}
