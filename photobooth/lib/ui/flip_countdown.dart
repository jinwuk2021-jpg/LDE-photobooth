import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Big countdown number on a mechanical split-flap card. The top half flips
/// down each second.
class FlipCountdown extends StatelessWidget {
  const FlipCountdown({super.key, required this.value, required this.size});

  final int value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      liveRegion: true,
      label: '$value',
      child: SizedBox(
        width: size * 0.78,
        height: size,
        child: AnimatedSwitcher(
          duration: reduce ? const Duration(milliseconds: 150) : const Duration(milliseconds: 320),
          transitionBuilder: (child, anim) {
            if (reduce) return FadeTransition(opacity: anim, child: child);
            return AnimatedBuilder(
              animation: anim,
              child: child,
              builder: (context, child) {
                // Incoming card flips down from the top hinge.
                final angle = (1 - anim.value) * math.pi / 2;
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.002)
                    ..rotateX(-angle),
                  child: child,
                );
              },
            );
          },
          child: _Card(key: ValueKey(value), value: value, size: size),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({super.key, required this.value, required this.size});
  final int value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.08);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: Palette.charcoal.withValues(alpha: 0.88),
        border: Border.all(color: Palette.brass, width: size * 0.02),
        boxShadow: const [BoxShadow(color: Palette.shadow, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            '$value',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontFamily: Fonts.mono,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.72,
              height: 1,
              color: Palette.paper,
            ),
          ),
          // Split line + hinge pins.
          Container(height: size * 0.014, color: Palette.shadow),
          Positioned(
            left: size * 0.02,
            child: _Pin(size: size * 0.05),
          ),
          Positioned(
            right: size * 0.02,
            child: _Pin(size: size * 0.05),
          ),
        ],
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size * 1.6,
    decoration: BoxDecoration(color: Palette.brass, borderRadius: BorderRadius.circular(size / 3)),
  );
}
