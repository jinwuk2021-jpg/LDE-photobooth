import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../booth/booth.dart';
import '../booth/print_layout.dart';
import '../camera/skin_smooth.dart';
import '../config.dart';
import '../services/printer.dart';
import '../ui/tokens.dart';

/// Asks for the PIN, then opens the admin screen.
Future<void> openAdmin(BuildContext context, Booth booth) async {
  final pin = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Nhân viên', style: TextStyles.title),
      content: TextField(
        controller: pin,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        style: TextStyles.title,
        decoration: const InputDecoration(hintText: 'Mã PIN'),
        onSubmitted: (v) => Navigator.pop(context, v == ADMIN_PIN),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
        TextButton(onPressed: () => Navigator.pop(context, pin.text == ADMIN_PIN), child: const Text('Mở')),
      ],
    ),
  );
  pin.dispose();
  if (ok == true && context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdminScreen(booth: booth)));
  }
}

/// Hidden staff screen: printer, event text, skin smoothing, uploads.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.booth});
  final Booth booth;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late final _title = TextEditingController(text: widget.booth.settings.title);
  late final _date = TextEditingController(text: widget.booth.settings.dateLine);

  @override
  void dispose() {
    // Saved when leaving, so a half-typed title never reaches a print.
    widget.booth.settings
      ..title = _title.text
      ..dateLine = _date.text;
    _title.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _pickPrinter() async {
    final picked = await PrinterChannel.pick();
    if (picked != null) await widget.booth.settings.setPrinter(picked.$1, picked.$2);
  }

  /// A print with numbered windows and a QR, to check size and borders.
  Future<void> _testPrint() async {
    final b = widget.booth;
    final img = await renderPrint(
      PrintSpec(
        layout: BoothLayout.cut2,
        photos: const [null, null, null, null],
        title: _title.text.isEmpty ? 'In thử' : _title.text,
        dateLine: _date.text,
        qrUrl: b.linkFor('testtesttest'),
      ),
    );
    final dir = Directory(p.join(b.docs.path, 'Booth', 'in-thu'))..createSync(recursive: true);
    final path = await b.camera.saveJpeg(img, p.join(dir.path, 'in-thu-${DateTime.now().millisecondsSinceEpoch}.jpg'));
    img.dispose();
    b.prints.add(path);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booth;
    return Scaffold(
      backgroundColor: Palette.paper,
      appBar: AppBar(
        backgroundColor: Palette.paperDeep,
        title: const Text('Quản lý photobooth', style: TextStyles.title),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([b.settings, b.prints, b.uploads]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(28),
          children: [
            _section('Máy in'),
            if (!PRINTING)
              const Text('Đang tắt in (PRINTING = false trong lib/config.dart).', style: TextStyles.body)
            else ...[
              Text(b.settings.printerName ?? 'Chưa chọn máy in', style: TextStyles.body),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _pickPrinter,
                    icon: const Icon(Icons.print),
                    label: const Text('Chọn máy in'),
                  ),
                  OutlinedButton.icon(
                    onPressed: b.settings.printerUrl == null ? null : _testPrint,
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('In thử'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text('Hàng đợi in', style: TextStyles.label.copyWith(fontWeight: FontWeight.w700)),
              if (b.prints.jobs.isEmpty) const Text('Chưa có lệnh in nào.', style: TextStyles.body),
              for (final job in b.prints.jobs.take(20)) _jobRow(job),
            ],

            _section('Màn chờ'),
            ValueListenableBuilder(
              valueListenable: b.startImageVersion,
              builder: (context, version, _) => Row(
                children: [
                  Container(
                    width: 240,
                    height: 160,
                    color: Palette.paperDeep,
                    child: b.startImage.existsSync()
                        ? Image.file(b.startImage, key: ValueKey(version), fit: BoxFit.contain)
                        : const Center(child: Text('Chưa có ảnh', style: TextStyles.label)),
                  ),
                  const SizedBox(width: 20),
                  FilledButton.icon(
                    onPressed: () async {
                      final x = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 2732,
                        maxHeight: 2732,
                        imageQuality: 92,
                      );
                      if (x != null) await b.setStartImage(x.path);
                    },
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Chọn ảnh sự kiện'),
                  ),
                  const SizedBox(width: 12),
                  if (b.startImage.existsSync())
                    OutlinedButton(onPressed: () => b.setStartImage(null), child: const Text('Bỏ ảnh')),
                ],
              ),
            ),

            _section('Sự kiện'),
            TextField(
              controller: _title,
              style: TextStyles.body,
              decoration: const InputDecoration(labelText: 'Tiêu đề (màn chờ + ảnh in)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _date,
              style: TextStyles.body,
              decoration: const InputDecoration(labelText: 'Dòng ngày trên ảnh in'),
            ),

            _section('Ảnh'),
            Row(
              children: [
                const Text('Làm mịn da: ', style: TextStyles.body),
                SegmentedButton<SkinSmooth>(
                  segments: [for (final s in SkinSmooth.values) ButtonSegment(value: s, label: Text(s.label))],
                  selected: {b.settings.skin},
                  onSelectionChanged: (v) => b.settings.skin = v.first,
                ),
              ],
            ),

            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Thời gian chọn ảnh: ', style: TextStyles.body),
                SegmentedButton<int>(
                  segments: [
                    for (final s in const [30, 60, 90, 120]) ButtonSegment(value: s, label: Text('${s}s')),
                  ],
                  selected: {b.settings.pickSeconds},
                  onSelectionChanged: (v) => b.settings.pickSeconds = v.first,
                ),
              ],
            ),

            _section('Upload'),
            Text(
              '${b.uploads.pendingSessions} lượt đang chờ · ${b.uploads.failingSessions} lượt đang lỗi / thử lại'
              ' · ${b.uploads.items.length} file',
              style: TextStyles.body,
            ),
            if (b.uploads.lastError != null)
              Text('Lỗi gần nhất: ${b.uploads.lastError}', style: TextStyles.body.copyWith(color: Palette.brickInk)),
            Text('Máy chủ: $SHARE_API_URL ${BOOTH_KEY.isEmpty ? '· THIẾU BOOTH_KEY' : ''}', style: TextStyles.label),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: b.uploads.items.isEmpty ? null : b.uploads.retryAll,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại tất cả'),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Ảnh mỗi lượt được lưu trong app Tệp → Trên iPad → Photobooth → Booth.',
              style: TextStyles.label,
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 10),
    child: Text(title, style: TextStyles.title),
  );

  Widget _jobRow(PrintJob job) {
    final t = job.created;
    String two(int n) => n.toString().padLeft(2, '0');
    final (label, color) = switch (job.status) {
      JobStatus.waiting => ('Đang chờ', Palette.kraftInk),
      JobStatus.printing => ('Đang in', Palette.moss),
      JobStatus.done => ('Đã in', Palette.moss),
      JobStatus.failed => ('Lỗi${job.error == null ? '' : ': ${job.error}'}', Palette.brickInk),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.photo_outlined),
      title: Text(
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}  ·  ${p.basename(p.dirname(job.path))}',
        style: TextStyles.body,
      ),
      subtitle: Text(label, style: TextStyles.label.copyWith(color: color)),
      trailing: job.status == JobStatus.failed || job.status == JobStatus.done
          ? OutlinedButton(onPressed: () => widget.booth.prints.retry(job), child: const Text('In lại'))
          : null,
    );
  }
}
