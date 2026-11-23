import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../booth/booth.dart';
import '../booth/print_layout.dart';
import '../camera/skin_smooth.dart';
import '../config.dart';
import '../services/printer.dart';
import '../ui/lux.dart';

/// Asks for the PIN, then opens the admin screen.
Future<void> openAdmin(BuildContext context, Booth booth) async {
  final pin = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Nhân viên', style: LuxFonts.serif(size: 30)),
      content: TextField(
        controller: pin,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        style: LuxFonts.serif(size: 30),
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
  late final _subtitle = TextEditingController(text: widget.booth.settings.subtitle);

  @override
  void dispose() {
    // Saved when leaving, so a half-typed title never reaches a print.
    widget.booth.settings
      ..title = _title.text
      ..dateLine = _date.text
      ..subtitle = _subtitle.text;
    _title.dispose();
    _date.dispose();
    _subtitle.dispose();
    super.dispose();
  }

  Future<void> _pickPrinter() async {
    final picked = await PrinterChannel.pick();
    if (picked != null) await widget.booth.settings.setPrinter(picked.$1, picked.$2);
  }

  /// A print with numbered windows and a QR, to check size and borders.
  /// A [layout] card with numbered windows and a QR, sent exactly like a guest's (4 Cut turned).
  Future<void> _testPrint(BoothLayout layout) async {
    final b = widget.booth;
    final card = await renderPrint(
      PrintSpec(
        layout: layout,
        photos: const [],
        title: _title.text.isEmpty ? 'In thử' : _title.text,
        dateLine: _date.text,
        subtitle: _subtitle.text,
        qrUrl: b.linkFor('testtesttest'),
      ),
    );
    final img = layout.landscape ? await forPrinter(card) : card;
    final dir = Directory(p.join(b.docs.path, 'Booth', 'in-thu'))..createSync(recursive: true);
    final path = await b.camera.saveJpeg(
      img,
      p.join(dir.path, 'in-thu-${layout.name}-${DateTime.now().millisecondsSinceEpoch}.jpg'),
      quality: 95,
    );
    if (!identical(img, card)) img.dispose();
    card.dispose();
    b.prints.add(path);
  }

  Future<void> _checkPrinter() async {
    await widget.booth.prints.check();
    if (!mounted) return;
    final ok = widget.booth.prints.printerOk == true;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(ok ? 'Máy in trả lời: OK' : 'Không liên lạc được máy in')));
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booth;
    return Scaffold(
      backgroundColor: Lux.night,
      appBar: AppBar(
        backgroundColor: Lux.navy,
        title: Text('Quản lý photobooth', style: LuxFonts.serif(size: 30)),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([b.settings, b.prints, b.uploads]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(28),
          children: [
            _section('Máy in'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('In ảnh cho khách', style: LuxFonts.sans(size: 18)),
              subtitle: Text(
                b.settings.printing ? 'Bật: mỗi lượt gửi 1 tấm sang máy in' : 'Tắt: chỉ lưu, upload và hiện QR',
                style: LuxFonts.sans(size: 14, color: Lux.ivoryA(0.7)),
              ),
              value: b.settings.printing,
              onChanged: (v) {
                b.settings.printing = v;
                if (v) b.prints.resume();
              },
            ),
            if (b.settings.printing) ...[
              Text(b.settings.printerName ?? 'Chưa chọn máy in', style: LuxFonts.sans(size: 18)),
              if (b.settings.printerUrl != null)
                Text(b.settings.printerUrl!, style: LuxFonts.sans(size: 13, color: Lux.ivoryA(0.5))),
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
                    onPressed: b.settings.printerUrl == null ? null : _checkPrinter,
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Kiểm tra kết nối'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final l in BoothLayout.values)
                    OutlinedButton.icon(
                      onPressed: b.settings.printerUrl == null ? null : () => _testPrint(l),
                      icon: const Icon(Icons.description_outlined),
                      label: Text('In thử ${l.label}'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Hàng đợi in',
                style: LuxFonts.sans(size: 14, color: Lux.ivoryA(0.7)).copyWith(fontWeight: FontWeight.w700),
              ),
              if (b.prints.jobs.isEmpty) Text('Chưa có lệnh in nào.', style: LuxFonts.sans(size: 18)),
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
                    color: Lux.navy,
                    child: b.startImage.existsSync()
                        ? Image.file(b.startImage, key: ValueKey(version), fit: BoxFit.contain)
                        : Center(
                            child: Text('Chưa có ảnh', style: LuxFonts.sans(size: 14, color: Lux.ivoryA(0.7))),
                          ),
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
              style: LuxFonts.sans(size: 18),
              decoration: const InputDecoration(labelText: 'Tiêu đề (màn chờ + ảnh in), chữ đầu đậm, phần sau nghiêng'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _date,
              style: LuxFonts.sans(size: 18),
              decoration: const InputDecoration(labelText: 'Dòng ngày trên ảnh in'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subtitle,
              style: LuxFonts.sans(size: 18),
              decoration: const InputDecoration(labelText: 'Dòng phụ (cạnh ngày, vd: Tiệc tổng kết cuối năm)'),
            ),

            _section('Ảnh'),
            Row(
              children: [
                Text('Làm mịn da: ', style: LuxFonts.sans(size: 18)),
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
                Text('Thời gian chọn ảnh: ', style: LuxFonts.sans(size: 18)),
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
              style: LuxFonts.sans(size: 18),
            ),
            if (b.uploads.lastError != null)
              Text(
                'Lỗi gần nhất: ${b.uploads.lastError}',
                style: LuxFonts.sans(size: 18).copyWith(color: Lux.urgentText),
              ),
            Text(
              'Máy chủ: $SHARE_API_URL ${BOOTH_KEY.isEmpty ? '· THIẾU BOOTH_KEY' : ''}',
              style: LuxFonts.sans(size: 14, color: Lux.ivoryA(0.7)),
            ),
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
            Text(
              'Ảnh mỗi lượt được lưu trong app Tệp → Trên iPad → Photobooth → Booth.',
              style: LuxFonts.sans(size: 14, color: Lux.ivoryA(0.7)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 10),
    child: Text(title, style: LuxFonts.serif(size: 30)),
  );

  Widget _jobRow(PrintJob job) {
    final t = job.created;
    String two(int n) => n.toString().padLeft(2, '0');
    final (label, color) = switch (job.status) {
      JobStatus.waiting => ('Đang chờ', Lux.ivoryA(0.6)),
      JobStatus.printing => ('Đang in', const Color(0xFF7BD389)),
      JobStatus.done => ('Đã in', const Color(0xFF7BD389)),
      JobStatus.failed => ('Lỗi${job.error == null ? '' : ': ${job.error}'}', Lux.urgentText),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.photo_outlined),
      title: Text(
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}  ·  ${p.basename(p.dirname(job.path))}',
        style: LuxFonts.sans(size: 18),
      ),
      subtitle: Text(
        label,
        style: LuxFonts.sans(size: 14, color: Lux.ivoryA(0.7)).copyWith(color: color),
      ),
      trailing: job.status == JobStatus.failed || job.status == JobStatus.done
          ? OutlinedButton(onPressed: () => widget.booth.prints.retry(job), child: const Text('In lại'))
          : null,
    );
  }
}
