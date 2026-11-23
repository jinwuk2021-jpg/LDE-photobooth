import 'package:flutter/material.dart';

import '../booth/print_layout.dart';
import '../services/settings.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// "Chọn khung": every frame of the menu side by side, drawn like the real print.
class LayoutScreen extends StatelessWidget {
  const LayoutScreen({super.key, required this.settings, required this.onPick, required this.onBack});
  final BoothSettings settings;
  final ValueChanged<BoothLayout> onPick;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Palette.paper,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 24, 40, 32),
          child: Column(
            children: [
              Row(
                children: [
                  BigButton(label: 'Quay lại', icon: Icons.arrow_back, outlined: true, fontSize: 26, onPressed: onBack),
                  const Expanded(
                    child: Text('Chọn khung ảnh', textAlign: TextAlign.center, style: TextStyles.hero),
                  ),
                  const SizedBox(width: 200),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final layout in BoothLayout.values)
                      // The landscape 4 Cut gets more width so all cards look the same height.
                      Expanded(
                        flex: layout.landscape ? 30 : 14,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: _Choice(layout: layout, settings: settings, onTap: () => onPick(layout)),
                        ),
                      ),
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

class _Choice extends StatelessWidget {
  const _Choice({required this.layout, required this.settings, required this.onTap});
  final BoothLayout layout;
  final BoothSettings settings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: layout.size.aspectRatio,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    boxShadow: [BoxShadow(color: Color(0x551E1A16), blurRadius: 16, offset: Offset(0, 8))],
                  ),
                  child: CustomPaint(
                    painter: PrintPainter(
                      PrintSpec(
                        layout: layout,
                        photos: const [],
                        title: settings.title,
                        dateLine: settings.dateLine,
                        qrSlot: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          BigButton(label: layout.label, fontSize: 28, onPressed: onTap),
        ],
      ),
    );
  }
}
