import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../booth/booth.dart';
import '../../camera/skin_smooth.dart';
import '../../ui/lux.dart';
import 'frames_page.dart';
import 'kit.dart';

/// Cài đặt – Sự kiện: the text on every card and the start screen, the start picture, and how
/// guests are photographed (skin, pick time).
class EventPage extends StatefulWidget {
  const EventPage({super.key, required this.booth});
  final Booth booth;

  @override
  State<EventPage> createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> {
  late final _title = TextEditingController(text: widget.booth.settings.title);
  late final _date = TextEditingController(text: widget.booth.settings.dateLine);
  late final _subtitle = TextEditingController(text: widget.booth.settings.subtitle);

  @override
  void dispose() {
    _save();
    _title.dispose();
    _date.dispose();
    _subtitle.dispose();
    super.dispose();
  }

  /// Saved on "Lưu" and when leaving, so a half-typed title never reaches a print.
  void _save() {
    widget.booth.settings
      ..title = _title.text
      ..dateLine = _date.text
      ..subtitle = _subtitle.text;
  }

  bool get _dirty {
    final s = widget.booth.settings;
    return _title.text.trim() != s.title || _date.text.trim() != s.dateLine || _subtitle.text.trim() != s.subtitle;
  }

  Future<void> _pickStart() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2732,
      maxHeight: 2732,
      imageQuality: 92,
    );
    if (x != null) await widget.booth.setStartImage(x.path);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booth;
    final s = b.settings;
    final preview = b.frames.enabled.first;

    final text = AdminCard(
      title: 'Chữ trên tấm in',
      icon: Icons.text_fields,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminField(controller: _title, label: 'Tiêu đề (chữ đầu đậm, phần sau nghiêng)', onChanged: (_) => setState(() {})),
          const SizedBox(height: 16),
          AdminField(controller: _date, label: 'Dòng ngày', onChanged: (_) => setState(() {})),
          const SizedBox(height: 16),
          AdminField(controller: _subtitle, label: 'Dòng phụ (cạnh ngày)', onChanged: (_) => setState(() {})),
          const SizedBox(height: 18),
          GoldButton(
            label: _dirty ? 'Lưu' : 'Đã lưu',
            icon: Icons.check,
            height: 60,
            fontSize: 19,
            onPressed: _dirty
                ? () {
                    FocusScope.of(context).unfocus();
                    setState(_save);
                    showToast(context, 'Đã lưu chữ trên tấm in');
                  }
                : null,
          ),
        ],
      ),
    );

    final card = AdminCard(
      title: 'Tấm in mẫu',
      icon: Icons.photo_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 300,
            child: FramePreview(key: ValueKey('${s.title}|${s.dateLine}|${s.subtitle}'), booth: b, frame: preview),
          ),
          const SizedBox(height: 10),
          Text('${preview.name} · cập nhật sau khi bấm Lưu', style: hintStyle()),
        ],
      ),
    );

    final start = AdminCard(
      title: 'Ảnh màn chờ',
      icon: Icons.wallpaper,
      child: ValueListenableBuilder(
        valueListenable: b.startImageVersion,
        builder: (context, version, _) {
          final has = b.startImage.existsSync();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: ColoredBox(
                    color: Colors.white.withValues(alpha: 0.03),
                    child: has
                        ? Image.file(b.startImage, key: ValueKey(version), fit: BoxFit.cover)
                        : Center(child: Text('Chưa có ảnh', style: hintStyle(size: 16))),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GoldButton(
                      label: has ? 'Đổi ảnh' : 'Chọn ảnh',
                      icon: Icons.image_outlined,
                      height: 60,
                      fontSize: 19,
                      onPressed: _pickStart,
                    ),
                  ),
                  if (has) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: LineButton(
                        label: 'Bỏ ảnh',
                        height: 60,
                        fontSize: 19,
                        onPressed: () => b.setStartImage(null),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );

    final shoot = AdminCard(
      title: 'Chụp ảnh',
      icon: Icons.face_retouching_natural,
      child: Column(
        children: [
          OptRow(
            label: 'Làm mịn da',
            stacked: true,
            trailing: GoldSegments<SkinSmooth>(
              options: [for (final v in SkinSmooth.values) (v, v.label)],
              value: s.skin,
              onChanged: (v) => s.skin = v,
            ),
          ),
          OptRow(
            label: 'Thời gian chọn ảnh',
            hint: 'Hết giờ app tự chọn đủ và in',
            last: true,
            stacked: true,
            trailing: GoldSegments<int>(
              options: const [(30, '30s'), (45, '45s'), (60, '60s'), (90, '90s')],
              value: s.pickSeconds,
              onChanged: (v) => s.pickSeconds = v,
            ),
          ),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 40, 0, 40),
      children: [
        const PageHeader(
          title: 'Sự kiện',
          subtitle: Text('Chữ trên tấm in và màn chờ, ảnh sự kiện, cách chụp cho khách'),
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 125,
              child: Column(children: [text, const SizedBox(height: 24), shoot]),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 100,
              child: Column(children: [card, const SizedBox(height: 24), start]),
            ),
          ],
        ),
      ],
    );
  }
}
