import 'package:film_camera/film_camera.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// The front camera full screen, mirrored like a mirror (the plugin never mirrors, as in Lensly).
class CameraView extends StatelessWidget {
  const CameraView(this.info, {super.key});
  final PreviewInfo? info;

  @override
  Widget build(BuildContext context) {
    final i = info;
    if (i == null) return const ColoredBox(color: Palette.charcoal);
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: i.width.toDouble(),
          height: i.height.toDouble(),
          child: Transform.flip(flipX: true, child: Texture(textureId: i.textureId)),
        ),
      ),
    );
  }
}

/// A big rounded button with a pressed "lip" (Lensly's red buttons).
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = Palette.brick,
    this.outlined = false,
    this.icon,
    this.fontSize = 34,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final bool outlined;
  final IconData? icon;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = outlined ? Palette.coffee : Palette.paper;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: outlined ? Palette.paper : color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: outlined ? const BorderSide(color: Palette.coffee, width: 2.5) : BorderSide.none,
        ),
        elevation: outlined ? 0 : 4,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, color: fg, size: fontSize), const SizedBox(width: 12)],
                Text(
                  label,
                  style: TextStyles.button.copyWith(color: fg, fontSize: fontSize),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Six dots: done, current, still to come.
class ShotDots extends StatelessWidget {
  const ShotDots({super.key, required this.total, required this.taken, required this.current});
  final int total;
  final int taken;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: i == current && i >= taken ? 30 : 22,
            height: i == current && i >= taken ? 30 : 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < taken ? Palette.mustard : Palette.paper.withValues(alpha: 0.35),
              border: Border.all(color: Palette.paper, width: 3),
            ),
          ),
      ],
    );
  }
}
