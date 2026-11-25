// Building blocks of the staff screens (design: "7 · Cài đặt", Claude Design handoff
// "LPE Sum Up – Photobooth", SettingsPrinter / SettingsFrames / SettingsHistory).
import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/lpe_tokens.dart';
import '../../ui/lux.dart';

const kGreen = LpeColors.ok;
const kBad = Color(0xFFF08A90);

/// `.hint`: 14 px, ivory 60 %.
TextStyle hintStyle({double size = 14}) => LuxFonts.sans(size: size, color: Lux.ivoryA(0.6), height: 1.5);

/// `.mono`: printer addresses.
TextStyle monoStyle({double size = 14, Color? color}) =>
    TextStyle(fontFamily: 'Menlo', fontSize: size, color: color ?? Lux.ivoryA(0.6));

/// `.glass.card`: radius 24, padding 22 / 24, with a `.ctitle` heading.
class AdminCard extends StatelessWidget {
  const AdminCard({super.key, this.title, this.icon, required this.child, this.height, this.padding});
  final String? title;
  final IconData? icon;
  final Widget child;
  final double? height;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Glass(
    radius: 24,
    height: height,
    padding: padding ?? const EdgeInsets.fromLTRB(24, 22, 24, 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null) ...[
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Lux.champagne.withValues(alpha: 0.5)),
                  ),
                  child: Icon(icon, size: 18, color: Lux.champagneLight),
                ),
                const SizedBox(width: 12),
              ],
              Flexible(child: Text(title!, style: LuxFonts.serif(size: 24, height: 1.25))),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (height != null) Expanded(child: child) else child,
      ],
    ),
  );
}

/// `.pico`: gold-tinted square with an icon.
class PicoIcon extends StatelessWidget {
  const PicoIcon(this.icon, {super.key, this.size = 64, this.dim = false});
  final IconData icon;
  final double size;
  final bool dim;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: dim ? 0.6 : 1,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        color: Lux.champagne.withValues(alpha: 0.14),
      ),
      child: Icon(icon, size: size * 0.45, color: Lux.champagneLight),
    ),
  );
}

/// `.tog`: 64 × 36, gold when on, knob springs across.
class GoldToggle extends StatelessWidget {
  const GoldToggle({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    child: GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 64,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: value ? null : Colors.white.withValues(alpha: 0.12),
          gradient: value ? Lux.button : null,
          border: Border.all(color: Lux.champagne.withValues(alpha: 0.3)),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: const Cubic(.34, 1.56, .64, 1),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? Lux.flash : Lux.ivory,
              boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 2))],
            ),
          ),
        ),
      ),
    ),
  );
}

/// `.optrow`: label (+ hint) left, control right, hairline below.
/// [stacked]: the control goes under the label (segments in a narrow card, as the design's
/// "In thêm" row).
class OptRow extends StatelessWidget {
  const OptRow({
    super.key,
    required this.label,
    this.hint,
    required this.trailing,
    this.last = false,
    this.stacked = false,
  });
  final String label;
  final String? hint;
  final Widget trailing;
  final bool last;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: LuxFonts.sans(size: 18)),
        if (hint != null) Text(hint!, style: hintStyle()),
      ],
    );
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 60),
      padding: EdgeInsets.symmetric(vertical: stacked ? 12 : 8),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: Lux.champagne.withValues(alpha: 0.14))),
      ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text,
                const SizedBox(height: 10),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: trailing),
              ],
            )
          : Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: 16),
                trailing,
              ],
            ),
    );
  }
}

/// `.seg`: pill group, the chosen one gold.
class GoldSegments<T> extends StatelessWidget {
  const GoldSegments({super.key, required this.options, required this.value, required this.onChanged});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      color: Colors.white.withValues(alpha: 0.035),
      border: Border.all(color: Lux.champagne.withValues(alpha: 0.28)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, (v, label)) in options.indexed) ...[
          if (i > 0) const SizedBox(width: 4),
          GestureDetector(
            onTap: () => onChanged(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 44,
              constraints: const BoxConstraints(minWidth: 64),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: v == value ? Lux.button : null,
              ),
              child: Text(
                label,
                style: LuxFonts.sans(
                  size: 17,
                  weight: v == value ? FontWeight.w600 : FontWeight.w500,
                  color: v == value ? Lux.goldInk : Lux.ivoryA(0.82),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// `.step`: − value +.
class GoldStepper extends StatelessWidget {
  const GoldStepper({super.key, required this.value, required this.min, required this.max, required this.onChanged});
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  Widget _btn(IconData icon, VoidCallback? onTap) => GestureDetector(
    onTap: onTap,
    child: Opacity(
      opacity: onTap == null ? 0.35 : 1,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Lux.champagne.withValues(alpha: 0.5)),
        ),
        child: Icon(icon, size: 22, color: Lux.champagneLight),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _btn(Icons.remove, value > min ? () => onChanged(value - 1) : null),
      SizedBox(
        width: 40,
        child: Text('$value', textAlign: TextAlign.center, style: LuxFonts.serif(size: 26)),
      ),
      _btn(Icons.add, value < max ? () => onChanged(value + 1) : null),
    ],
  );
}

enum PillKind { ok, bad, wait, none }

/// `.pillst` / `.st-*`: status pill with a dot.
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, this.kind, {super.key, this.small = false});
  final String label;
  final PillKind kind;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border, dot) = switch (kind) {
      PillKind.ok => (const Color(0x2478C896), const Color(0xFF9FE0B6), const Color(0x6678C896), kGreen),
      PillKind.bad => (const Color(0x29E0525A), Lux.urgentText, const Color(0x80E0525A), Lux.urgent),
      PillKind.wait => (const Color(0x29E8B04A), const Color(0xFFF3CD84), const Color(0x73E8B04A), Lux.amber),
      PillKind.none => (const Color(0x0DFFFFFF), Lux.ivoryA(0.7), Lux.ivoryA(0.2), Lux.ivoryA(0.5)),
    };
    return Container(
      height: small ? 28 : 34,
      padding: EdgeInsets.symmetric(horizontal: small ? 10 : 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: small ? 8 : 9,
            height: small ? 8 : 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dot,
              boxShadow: [BoxShadow(color: dot, blurRadius: 6)],
            ),
          ),
          SizedBox(width: small ? 7 : 8),
          Text(label, style: LuxFonts.sans(size: small ? 13 : 15, weight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

/// `.chk`: ✓ / ✕, label, value on the right.
class CheckRow extends StatelessWidget {
  const CheckRow({super.key, required this.ok, required this.label, required this.value});
  final bool? ok;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Icon(
          ok == null ? Icons.remove : (ok! ? Icons.check : Icons.close),
          size: 20,
          color: ok == null ? Lux.ivoryA(0.5) : (ok! ? kGreen : kBad),
        ),
        const SizedBox(width: 12),
        Text(label, style: LuxFonts.sans(size: 16)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: LuxFonts.sans(size: 15, color: Lux.ivoryA(0.65)),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

/// `.field` with its `.flabel`.
class AdminField extends StatelessWidget {
  const AdminField({
    super.key,
    required this.controller,
    this.label,
    this.mono = false,
    this.keyboard,
    this.onSubmitted,
    this.onChanged,
  });
  final TextEditingController controller;
  final String? label;
  final bool mono;
  final TextInputType? keyboard;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final style = mono ? monoStyle(size: 21, color: Lux.ivory) : LuxFonts.sans(size: 21);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: Lux.champagne.withValues(alpha: 0.32)),
    );
    final field = SizedBox(
      height: 60,
      child: TextField(
        controller: controller,
        style: style,
        keyboardType: keyboard,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        cursorColor: Lux.champagneLight,
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.04),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          enabledBorder: border,
          focusedBorder: border.copyWith(borderSide: const BorderSide(color: Lux.champagneLight, width: 1.5)),
        ),
      ),
    );
    if (label == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label!, style: LuxFonts.sans(size: 16, color: Lux.ivoryA(0.72))),
        const SizedBox(height: 8),
        field,
      ],
    );
  }
}

/// `.textbtn`: underlined quiet action.
class TextLink extends StatelessWidget {
  const TextLink(this.label, {super.key, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Text(
      label,
      style: LuxFonts.sans(size: 16, color: Lux.ivoryA(0.7)).copyWith(
        decoration: TextDecoration.underline,
        decorationColor: Lux.ivoryA(0.7),
      ),
    ),
  );
}

/// Round outlined icon button (`.icob`: the pencil / print on a frame card).
class RoundIconButton extends StatelessWidget {
  const RoundIconButton(this.icon, {super.key, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? '',
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Lux.champagne.withValues(alpha: 0.5)),
        ),
        child: Icon(icon, size: 20, color: Lux.champagneLight),
      ),
    ),
  );
}

/// Red notice box (printer unreachable).
class AlertBox extends StatelessWidget {
  const AlertBox(this.child, {super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      color: const Color(0x1FE0525A),
      border: Border.all(color: const Color(0x59E0525A)),
    ),
    child: DefaultTextStyle(
      style: LuxFonts.sans(size: 15, color: const Color(0xFFFFD0D3), height: 1.5),
      child: child,
    ),
  );
}

/// Page heading: serif title, subtitle, something on the right.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, required this.subtitle, this.trailing, this.back});
  final String title;
  final Widget subtitle;
  final Widget? trailing;

  /// "← Khung ảnh" above the title.
  final (String, VoidCallback)? back;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (back != null)
              GestureDetector(
                onTap: back!.$2,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back, size: 18, color: Lux.ivoryA(0.7)),
                      const SizedBox(width: 6),
                      Text(back!.$1, style: LuxFonts.sans(size: 16, color: Lux.ivoryA(0.7))),
                    ],
                  ),
                ),
              ),
            Text(title, style: LuxFonts.serif(size: 40, height: 1.15)),
            const SizedBox(height: 4),
            DefaultTextStyle(style: LuxFonts.sans(size: 17, color: Lux.ivoryA(0.65)), child: subtitle),
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

/// `.toast`: glass pill at the top, 2.4 s.
void showToast(BuildContext context, String text, {IconData icon = Icons.check_circle_outline}) {
  final overlay = Overlay.of(context);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      top: 24,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutQuint,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(offset: Offset(0, -12 * (1 - t)), child: child),
            ),
            child: Glass(
              radius: 999,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Lux.champagneLight, size: 22),
                  const SizedBox(width: 12),
                  Text(text, style: LuxFonts.sans(size: 18, weight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Timer(const Duration(milliseconds: 2400), entry.remove);
}

/// `.sheet`: centred glass dialog, 560 wide, with a close button.
Future<T?> showSheet<T>(BuildContext context, {required String title, required Widget Function(BuildContext) body}) =>
    showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: title,
      barrierColor: const Color(0x99000000),
      transitionDuration: const Duration(milliseconds: 340),
      pageBuilder: (context, _, _) => Center(
        child: Material(
          type: MaterialType.transparency,
          child: Glass(
            radius: 30,
            width: 560,
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(title, style: LuxFonts.serif(size: 30))),
                    RoundIconButton(Icons.close, onTap: () => Navigator.of(context).pop()),
                  ],
                ),
                const SizedBox(height: 14),
                body(context),
              ],
            ),
          ),
        ),
      ),
      transitionBuilder: (context, a, _, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutQuint)),
          child: child,
        ),
      ),
    );

/// `.prow`: a row in a sheet list.
class SheetRow extends StatelessWidget {
  const SheetRow({super.key, required this.icon, required this.title, this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withValues(alpha: 0.03),
          border: Border.all(color: Lux.champagne.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            PicoIcon(icon, size: 48),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: LuxFonts.sans(size: 19, weight: FontWeight.w600)),
                  if (subtitle != null) Text(subtitle!, style: monoStyle(size: 13)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Lux.champagneLight),
          ],
        ),
      ),
    ),
  );
}
