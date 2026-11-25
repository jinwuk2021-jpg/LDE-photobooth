import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../booth/booth.dart';
import '../../booth/frames.dart';
import '../../booth/print_layout.dart';
import '../../ui/lux.dart';
import 'kit.dart';

/// 7c · Cài đặt – Khung ảnh: every frame as a card (preview, name, tag, windows, show / hide).
class FramesPage extends StatelessWidget {
  const FramesPage({
    super.key,
    required this.booth,
    required this.onTestPrint,
    required this.onAdd,
    required this.onEdit,
  });
  final Booth booth;
  final void Function(BoothFrame) onTestPrint;

  /// 7d for a new frame / for a custom one.
  final VoidCallback onAdd;
  final void Function(BoothFrame) onEdit;

  @override
  Widget build(BuildContext context) {
    final store = booth.frames;
    final on = store.enabled.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 40, 0, 40),
      children: [
        PageHeader(
          title: 'Khung ảnh',
          subtitle: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Khung đang bật sẽ hiện ở màn "Chọn khung ảnh" · '),
                TextSpan(
                  text: '$on đang bật',
                  style: LuxFonts.sans(size: 17, weight: FontWeight.w600, color: Lux.champagneLight),
                ),
              ],
            ),
          ),
          trailing: GoldButton(
            label: 'Thêm khung',
            icon: Icons.add,
            width: 210,
            height: 60,
            fontSize: 19,
            onPressed: onAdd,
          ),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, box) {
            const gap = 22.0;
            final w = (box.maxWidth - 2 * gap) / 3;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final f in store.all)
                  SizedBox(
                    width: w,
                    child: _FrameCard(
                      booth: booth,
                      frame: f,
                      on: store.isEnabled(f),
                      onToggle: (v) async {
                        if (!await store.setEnabled(f, v) && context.mounted) {
                          showToast(context, 'Phải bật ít nhất 1 khung', icon: Icons.error_outline);
                        }
                      },
                      onTestPrint: () => onTestPrint(f),
                      onEdit: f.builtIn ? null : () => onEdit(f),
                    ),
                  ),
                SizedBox(
                  width: w,
                  height: 310,
                  child: GestureDetector(
                    onTap: onAdd,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        color: Lux.champagne.withValues(alpha: 0.04),
                        border: Border.all(color: Lux.champagne.withValues(alpha: 0.6), width: 1.5),
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Lux.champagne.withValues(alpha: 0.7)),
                            ),
                            child: const Icon(Icons.add, size: 30, color: Lux.champagneLight),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Thêm khung',
                            style: LuxFonts.sans(size: 19, weight: FontWeight.w600, color: Lux.champagneLight),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'File PNG 1200×1776 hoặc 1776×1200, ô ảnh để trong suốt',
                            textAlign: TextAlign.center,
                            style: hintStyle(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FrameCard extends StatelessWidget {
  const _FrameCard({
    required this.booth,
    required this.frame,
    required this.on,
    required this.onToggle,
    required this.onTestPrint,
    this.onEdit,
  });
  final Booth booth;
  final BoothFrame frame;
  final bool on;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTestPrint;

  /// Custom frames only.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: on ? 1 : 0.6,
    duration: const Duration(milliseconds: 200),
    child: Glass(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 160,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withValues(alpha: 0.03),
            ),
            child: FramePreview(booth: booth, frame: frame),
          ),
          const SizedBox(height: 14),
          Text(frame.name, style: LuxFonts.sans(size: 20, weight: FontWeight.w600), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: Lux.champagne.withValues(alpha: 0.16),
                ),
                child: Text(
                  frame.builtIn ? 'Mặc định' : 'PNG riêng',
                  style: LuxFonts.sans(size: 12, weight: FontWeight.w600, color: Lux.champagneLight, spacing: 0.7),
                ),
              ),
              const SizedBox(width: 8),
              Text('${frame.picks} ô', style: LuxFonts.sans(size: 15, color: Lux.ivoryA(0.65))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              GoldToggle(value: on, onChanged: onToggle),
              const SizedBox(width: 12),
              Expanded(
                child: Text(on ? 'Đang hiện' : 'Đang ẩn', style: LuxFonts.sans(size: 15, color: Lux.ivoryA(0.7))),
              ),
              if (onEdit != null) ...[
                RoundIconButton(Icons.edit_outlined, tooltip: 'Sửa khung', onTap: onEdit),
                const SizedBox(width: 8),
              ],
              RoundIconButton(
                Icons.print_outlined,
                tooltip: 'In thử',
                onTap: booth.settings.printing && booth.settings.printerUrl != null ? onTestPrint : null,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// The frame as it prints (numbered windows, live title / date), rendered once per text.
class FramePreview extends StatefulWidget {
  const FramePreview({super.key, required this.booth, required this.frame});
  final Booth booth;
  final BoothFrame frame;

  static final _cache = <String, Future<ui.Image>>{};

  @override
  State<FramePreview> createState() => _FramePreviewState();
}

class _FramePreviewState extends State<FramePreview> {
  late Future<ui.Image> _image = _load();

  Future<ui.Image> _load() {
    final s = widget.booth.settings;
    final key = '${widget.frame.id}|${s.title}|${s.dateLine}|${s.subtitle}';
    return FramePreview._cache.putIfAbsent(
      key,
      () => renderPrint(
        PrintSpec(
          frame: widget.frame,
          photos: const [],
          title: s.title,
          dateLine: s.dateLine,
          subtitle: s.subtitle,
          qrUrl: widget.booth.linkFor('testtesttest'),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(FramePreview old) {
    super.didUpdateWidget(old);
    if (old.frame.id != widget.frame.id) _image = _load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ui.Image>(
    future: _image,
    builder: (context, snap) => snap.data == null
        ? const SizedBox.expand()
        : Center(
            child: AspectRatio(
              aspectRatio: widget.frame.size.aspectRatio,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 8))],
                ),
                child: RawImage(image: snap.data, fit: BoxFit.contain),
              ),
            ),
          ),
  );
}
