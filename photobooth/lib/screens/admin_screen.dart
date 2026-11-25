import 'package:flutter/material.dart';

import '../booth/booth.dart';
import '../booth/frames.dart';
import '../camera/sony_camera.dart';
import '../ui/lux.dart';
import '../ui/sparkle.dart';
import 'admin/camera_page.dart';
import 'admin/event_page.dart';
import 'admin/frame_edit_page.dart';
import 'admin/frames_page.dart';
import 'admin/history_page.dart';
import 'admin/kit.dart';
import 'admin/printer_page.dart';

/// Opens the staff screen (hold the start screen's gear 3 s; no PIN).
Future<void> openAdmin(BuildContext context, Booth booth) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdminScreen(booth: booth)));

enum AdminTab { printer, camera, frames, event, history }

/// 7 · Cài đặt (design "LPE Sum Up – Photobooth", SettingsPrinter / Frames / History): a side bar
/// with the sections and "Về màn chờ", the section on the right.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.booth, this.initial = AdminTab.printer});
  final Booth booth;
  final AdminTab initial;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late AdminTab _tab = widget.initial;

  /// 7d open: (frame being edited or null for a new one).
  (BoothFrame?,)? _editing;

  @override
  Widget build(BuildContext context) {
    final b = widget.booth;
    // Built inside the ListenableBuilder below: a page made once out here was the same widget
    // on every change, so Flutter skipped it and toggles only showed after switching tabs.
    Widget page() => switch (_tab) {
      AdminTab.printer => PrinterPage(booth: b),
      AdminTab.camera => CameraPage(booth: b),
      AdminTab.frames when _editing != null => FrameEditPage(
        booth: b,
        frame: _editing!.$1,
        onDone: () => setState(() => _editing = null),
      ),
      AdminTab.frames => FramesPage(
        booth: b,
        onTestPrint: (f) => sendTestPrint(context, b, f),
        onAdd: () => setState(() => _editing = (null,)),
        onEdit: (f) => setState(() => _editing = (f,)),
      ),
      AdminTab.event => EventPage(booth: b),
      AdminTab.history => HistoryPage(booth: b),
    };
    return Scaffold(
      backgroundColor: Lux.night,
      body: DecoratedBox(
        decoration: Lux.backdrop,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const SparkleBackground(level: SparkleLevel.low, seed: 71),
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SideBar(
                  booth: b,
                  tab: _tab,
                  onTab: (t) => setState(() {
                    _tab = t;
                    _editing = null;
                  }),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 32, right: 40),
                    child: ListenableBuilder(
                      listenable: Listenable.merge([b.settings, b.prints, b.frames, b.camera.sony]),
                      builder: (context, _) => AnimatedSwitcher(
                        duration: const Duration(milliseconds: 380),
                        reverseDuration: const Duration(milliseconds: 120),
                        transitionBuilder: luxTransition,
                        child: KeyedSubtree(key: ValueKey((_tab, _editing)), child: page()),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SideBar extends StatelessWidget {
  const _SideBar({required this.booth, required this.tab, required this.onTab});
  final Booth booth;
  final AdminTab tab;
  final ValueChanged<AdminTab> onTab;

  @override
  Widget build(BuildContext context) {
    final b = booth;
    return Container(
      width: 272,
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xBF141A33), Color(0xD90B0B12)],
        ),
        border: Border(right: BorderSide(color: Lux.champagne.withValues(alpha: 0.22))),
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([b.settings, b.prints, b.camera.sony]),
        builder: (context, _) {
          final s = b.settings;
          final printerDot = !s.printing || s.printerUrl == null
              ? null
              : (b.prints.printerOk == true ? kGreen : (b.prints.printerOk == false ? Lux.urgent : null));
          final cameraDot = !s.externalCamera
              ? null
              : (b.camera.sony.state == SonyState.ready ? kGreen : Lux.urgent);
          final historyDot = b.prints.failedCount > 0 ? Lux.urgent : null;
          final items = [
            (AdminTab.printer, Icons.print_outlined, 'Máy in', printerDot),
            (AdminTab.camera, Icons.photo_camera_outlined, 'Máy ảnh', cameraDot),
            (AdminTab.frames, Icons.image_outlined, 'Khung ảnh', null),
            (AdminTab.event, Icons.celebration_outlined, 'Sự kiện', null),
            (AdminTab.history, Icons.history, 'Lịch sử in', historyDot),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text('NHÂN VIÊN', style: LuxFonts.eyebrow(size: 12)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 0, 26),
                child: GoldText(
                  'Cài đặt',
                  align: TextAlign.left,
                  style: LuxFonts.serif(size: 38, height: 1.15),
                ),
              ),
              for (final (t, icon, label, dot) in items) ...[
                _NavItem(icon: icon, label: label, on: t == tab, dot: dot, onTap: () => onTab(t)),
                const SizedBox(height: 8),
              ],
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text('Mở lại: giữ nút ⚙ ở màn chờ 3 giây.', style: hintStyle()),
              ),
              LineButton(
                label: 'Về màn chờ',
                icon: Icons.arrow_back,
                height: 60,
                fontSize: 18,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// `.nav` / `.nav.on`.
class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.on, required this.onTap, this.dot});
  final IconData icon;
  final String label;
  final bool on;
  final Color? dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = on ? Lux.goldInk : Lux.ivoryA(0.78);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: on ? Lux.button : null,
          color: on ? null : Colors.transparent,
          boxShadow: on ? const [BoxShadow(color: Color(0x40D4AF6A), blurRadius: 18, offset: Offset(0, 6))] : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: fg),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: LuxFonts.sans(size: 19, weight: on ? FontWeight.w600 : FontWeight.w500, color: fg),
              ),
            ),
            if (dot != null)
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dot,
                  boxShadow: [BoxShadow(color: dot!, blurRadius: 8)],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

