import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../booth/booth.dart';
import '../../booth/frames.dart';
import '../../booth/print_layout.dart';
import '../../services/printer.dart';
import '../../services/settings.dart';
import '../../ui/lux.dart';
import 'kit.dart';

/// 7a / 7b · Cài đặt – Máy in (connected / unreachable).
class PrinterPage extends StatefulWidget {
  const PrinterPage({super.key, required this.booth});
  final Booth booth;

  @override
  State<PrinterPage> createState() => _PrinterPageState();
}

class _PrinterPageState extends State<PrinterPage> {
  late final _ip = TextEditingController(text: _ipOf(widget.booth.settings.printerUrl) ?? '');
  bool _checking = false;

  Booth get b => widget.booth;

  static String? _ipOf(String? url) {
    final host = url == null ? null : Uri.tryParse(url)?.host;
    return host != null && RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host) ? host : null;
  }

  @override
  void dispose() {
    _ip.dispose();
    super.dispose();
  }

  Future<void> _check({bool toast = true}) async {
    setState(() => _checking = true);
    await b.prints.check();
    if (!mounted) return;
    setState(() => _checking = false);
    if (toast) {
      showToast(
        context,
        b.prints.printerOk == true ? 'Máy in trả lời: OK' : 'Không liên lạc được máy in',
        icon: b.prints.printerOk == true ? Icons.check_circle_outline : Icons.error_outline,
      );
    }
  }

  Future<void> _pick() async {
    final picked = await PrinterChannel.pick();
    if (picked == null) return;
    await b.settings.setPrinter(picked.$1, picked.$2);
    b.prints.resume();
    await _check(toast: false);
    if (mounted) showToast(context, 'Đã chọn ${picked.$2}');
  }

  Future<void> _connectIp() async {
    final ip = _ip.text.trim();
    if (!RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(ip)) {
      showToast(context, 'IP không hợp lệ (ví dụ 192.168.0.23)', icon: Icons.error_outline);
      return;
    }
    FocusScope.of(context).unfocus();
    await b.settings.setPrinter('ipp://$ip/ipp/print', 'Máy in $ip');
    b.prints.resume();
    await _check();
  }

  Future<void> _forget() async {
    await b.settings.forgetPrinter();
    b.prints.forget();
    if (mounted) showToast(context, 'Đã quên máy in');
  }

  Future<void> _testPrint(BoothFrame frame) => sendTestPrint(context, b, frame);

  void _chooseTestFrame() => showSheet<void>(
    context,
    title: 'In thử khung nào?',
    body: (ctx) => Column(
      children: [
        for (final f in b.frames.enabled)
          SheetRow(
            icon: Icons.photo_outlined,
            title: f.name,
            subtitle: '${f.picks} ô · ${f.landscape ? 'ngang' : 'dọc'}',
            onTap: () {
              Navigator.of(ctx).pop();
              _testPrint(f);
            },
          ),
        Text('In ra một tấm có ô đánh số và QR thử, đúng như tấm của khách.', style: hintStyle()),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = b.settings;
    final q = b.prints;
    final hasPrinter = s.printerUrl != null;
    final off = hasPrinter && q.printerOk == false;
    final (pill, kind) = !s.printing
        ? ('Đang tắt in', PillKind.none)
        : !hasPrinter
        ? ('Chưa chọn máy in', PillKind.none)
        : switch (q.printerOk) {
            true => ('Sẵn sàng', PillKind.ok),
            false => ('Mất kết nối', PillKind.bad),
            null => ('Đang kiểm tra…', PillKind.wait),
          };
    String two(int n) => n.toString().padLeft(2, '0');
    final seen = q.lastSeen;

    final current = AdminCard(
      title: 'Máy in đang dùng',
      icon: Icons.print_outlined,
      child: !hasPrinter
          ? Column(
              children: [
                const SizedBox(height: 8),
                const PicoIcon(Icons.print_outlined, dim: true),
                const SizedBox(height: 10),
                Text('Chưa chọn máy in', style: LuxFonts.sans(size: 19)),
                Text('Bấm tìm, hoặc nhập IP ở ô bên dưới.', style: hintStyle()),
                const SizedBox(height: 18),
                GoldButton(
                  label: 'Tìm máy in AirPrint',
                  icon: Icons.search,
                  height: 60,
                  fontSize: 19,
                  width: double.infinity,
                  onPressed: _pick,
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const PicoIcon(Icons.print_outlined),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.printerName ?? '',
                            style: LuxFonts.sans(size: 21, weight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(s.printerUrl!, style: monoStyle(), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (off)
                  const AlertBox(
                    Text(
                      'Không liên lạc được máy in. Kiểm tra máy đang bật, không ở chế độ ngủ và đang vào '
                      'cùng Wi-Fi với iPad. App tự thử lại mỗi 15 giây.',
                    ),
                  )
                else
                  Text(
                    q.printerOk == true
                        ? 'Đã lưu. Mở app là tự kết nối lại, khách bấm "In" là in ngay không hỏi.'
                              '${seen == null ? '' : ' Trả lời lúc ${two(seen.hour)}:${two(seen.minute)}:${two(seen.second)}.'}'
                        : 'Đang hỏi máy in…',
                    style: hintStyle(),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: off
                          ? GoldButton(
                              label: _checking ? 'Đang thử…' : 'Thử lại',
                              icon: Icons.refresh,
                              height: 60,
                              fontSize: 19,
                              onPressed: _checking ? null : _check,
                            )
                          : GoldButton(
                              label: 'In thử',
                              icon: Icons.print_outlined,
                              height: 60,
                              fontSize: 19,
                              onPressed: s.printing ? _chooseTestFrame : null,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: LineButton(
                        label: off ? 'Tìm máy in' : 'Chọn máy khác',
                        icon: Icons.search,
                        height: 60,
                        fontSize: 19,
                        onPressed: _pick,
                      ),
                    ),
                  ],
                ),
                if (!off) ...[const SizedBox(height: 12), TextLink('Quên máy in này', onTap: _forget)],
              ],
            ),
    );

    final manual = AdminCard(
      title: 'Kết nối thủ công bằng IP',
      icon: Icons.wifi,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Địa chỉ IP của máy in', style: LuxFonts.sans(size: 16, color: Lux.ivoryA(0.72))),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AdminField(
                  controller: _ip,
                  mono: true,
                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                  onSubmitted: (_) => _connectIp(),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              GoldButton(label: 'Kết nối', width: 130, height: 60, fontSize: 19, onPressed: _connectIp),
            ],
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'App sẽ dùng '),
                TextSpan(
                  text: 'ipp://${_ip.text.trim().isEmpty ? '…' : _ip.text.trim()}/ipp/print',
                  style: monoStyle(color: Lux.champagneLight),
                ),
                const TextSpan(text: '.'),
              ],
            ),
            style: hintStyle(),
          ),
          const SizedBox(height: 6),
          Text(
            'IP xem trong mục thông tin Wi-Fi trên màn hình SELPHY. Nên đặt IP cố định cho máy in trên '
            'hotspot/router để lần sau khỏi nhập lại.',
            style: hintStyle(),
          ),
        ],
      ),
    );

    final whenPrinting = AdminCard(
      title: 'Khi in',
      icon: Icons.check,
      child: Column(
        children: [
          OptRow(
            label: 'Tự in khi khách bấm In',
            hint: s.printing ? 'Không hiện hộp thoại' : 'Tắt: chỉ lưu, upload và hiện QR',
            trailing: GoldToggle(
              value: s.printing,
              onChanged: (v) {
                s.printing = v;
                if (v) q.check();
              },
            ),
          ),
          OptRow(
            label: 'Số bản mỗi lượt',
            trailing: GoldStepper(value: s.printCopies, min: 1, max: 3, onChanged: (v) => s.printCopies = v),
          ),
          OptRow(
            label: 'Nút "In thêm 1 tấm"',
            hint: 'Số tấm khách được in thêm ở màn cảm ơn',
            stacked: true,
            trailing: GoldSegments<int>(
              options: const [(0, 'Tắt'), (1, '1'), (2, '2'), (3, '3')],
              value: s.extraPrintMax,
              onChanged: (v) => s.extraPrintMax = v,
            ),
          ),
          OptRow(
            label: 'Gửi in nhanh',
            hint: s.printPaper == PrintPaper.postcard && s.printFill
                ? 'Gửi thẳng file ảnh (nhẹ, nhanh). Nếu in ra lệch / có viền lạ thì tắt'
                      '${q.lastSendTime == null ? '' : ' · lần gần nhất ${q.lastSendTime!.inSeconds} giây'}'
                : 'Chỉ dùng cho Postcard + Tràn lề',
            trailing: GoldToggle(value: s.printFast, onChanged: (v) => s.printFast = v),
          ),
          OptRow(
            label: 'Khổ giấy',
            hint: 'Postcard 100×148 (SELPHY) · 2L 127×178 · L 89×127',
            stacked: true,
            trailing: GoldSegments<PrintPaper>(
              options: [for (final p in PrintPaper.values) (p, p.label)],
              value: s.printPaper,
              onChanged: (v) => s.printPaper = v,
            ),
          ),
          OptRow(
            label: 'Kiểu in',
            hint: s.printFill
                ? 'Phủ kín tờ giấy khi giấy đúng tỉ lệ tấm in (Postcard); khổ khác vẫn nằm trọn trong giấy'
                : 'Nằm trọn trong vùng in, có viền',
            last: true,
            stacked: true,
            trailing: GoldSegments<bool>(
              options: const [(true, 'Tràn lề'), (false, 'Có viền')],
              value: s.printFill,
              onChanged: (v) => s.printFill = v,
            ),
          ),
        ],
      ),
    );

    final checks = AdminCard(
      title: 'Kiểm tra nhanh',
      icon: Icons.info_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckRow(ok: s.printing, label: 'In ảnh cho khách', value: s.printing ? 'Đang bật' : 'Đang tắt'),
          CheckRow(ok: hasPrinter, label: 'Đã chọn máy in', value: hasPrinter ? (s.printerName ?? '') : 'Chưa'),
          CheckRow(
            ok: hasPrinter ? q.printerOk : false,
            label: 'Máy in phản hồi',
            value: q.printerOk == true && q.lastLatency != null
                ? '${q.lastLatency!.inMilliseconds} ms'
                : (q.printerOk == false ? 'Không phản hồi' : '—'),
          ),
          CheckRow(
            ok: q.waitingCount == 0,
            label: 'Hàng đợi in',
            value: q.waitingCount == 0 ? '0 lượt chờ' : '${q.waitingCount} lượt đang chờ',
          ),
          CheckRow(ok: q.failedCount == 0, label: 'Lệnh lỗi', value: '${q.failedCount}'),
          if (off) ...[
            const SizedBox(height: 8),
            Text(
              'Nếu "Mạng cục bộ" bị tắt: Cài đặt iPad → Quyền riêng tư → Mạng cục bộ → bật cho Photobooth.',
              style: hintStyle(),
            ),
          ],
        ],
      ),
    );

    final colour = AdminCard(
      title: 'Màu tấm in',
      icon: Icons.palette_outlined,
      child: Column(
        children: [
          OptRow(
            label: 'Độ đậm màu',
            hint: 'SELPHY in hơi nhạt; ảnh trên web không bị ảnh hưởng',
            trailing: GoldSegments<PrintColor>(
              options: [for (final c in PrintColor.values) (c, c.label)],
              value: s.printColor,
              onChanged: (v) => s.printColor = v,
            ),
          ),
          OptRow(
            label: 'Độ sáng',
            hint: 'Ảnh in ra tối thì tăng, bị bạc thì giảm',
            trailing: GoldSegments<int>(
              options: const [(-10, '−10%'), (-5, '−5%'), (0, '0'), (5, '+5%'), (10, '+10%')],
              value: s.printBrighten,
              onChanged: (v) => s.printBrighten = v,
            ),
          ),
          OptRow(
            label: 'Xoay 4 Cut theo chiều ngược lại',
            hint: 'Bật khi tấm 4 Cut in ra bị lộn đầu',
            last: true,
            trailing: GoldToggle(value: s.turnCounterClockwise, onChanged: (v) => s.turnCounterClockwise = v),
          ),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 40, 0, 40),
      children: [
        PageHeader(
          title: 'Máy in',
          subtitle: const Text('AirPrint · iPad và máy in phải cùng một mạng Wi-Fi'),
          trailing: StatusPill(pill, kind),
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 125, child: Column(children: [current, const SizedBox(height: 24), manual])),
            const SizedBox(width: 24),
            Expanded(flex: 100, child: Column(children: [whenPrinting, const SizedBox(height: 24), checks])),
          ],
        ),
        const SizedBox(height: 24),
        colour,
      ],
    );
  }
}

/// A card of [frame] with numbered windows and a test QR, sent exactly like a guest's
/// (landscape turned, admin colours).
Future<void> sendTestPrint(BuildContext context, Booth b, BoothFrame frame) async {
  final s = b.settings;
  final card = await renderPrint(
    PrintSpec(
      frame: frame,
      photos: const [],
      title: s.title.isEmpty ? 'In thử' : s.title,
      dateLine: s.dateLine,
      subtitle: s.subtitle,
      qrUrl: b.linkFor('testtesttest'),
    ),
  );
  final dir = Directory(p.join(b.docs.path, 'Booth', 'in-thu'))..createSync(recursive: true);
  final path = await b.printerCopy(
    card,
    p.join(dir.path, 'in-thu-${frame.id}-${DateTime.now().millisecondsSinceEpoch}.jpg'),
  );
  card.dispose();
  b.prints.add(path);
  if (context.mounted) showToast(context, 'Đã gửi in thử ${frame.name}', icon: Icons.print_outlined);
}
