import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../booth/booth.dart';
import '../config.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'admin_screen.dart';

/// Start screen: the event picture (from admin), "Chạm để bắt đầu".
/// Hidden admin: 5 taps in the top-right corner, then the PIN.
class IdleScreen extends StatefulWidget {
  const IdleScreen({super.key, required this.booth, required this.onStart});
  final Booth booth;
  final VoidCallback onStart;

  @override
  State<IdleScreen> createState() => _IdleScreenState();
}

class _IdleScreenState extends State<IdleScreen> {
  int _cornerTaps = 0;
  DateTime _firstTap = DateTime(0);
  Timer? _check;

  @override
  void initState() {
    super.initState();
    widget.booth.prints.check();
    _check = Timer.periodic(const Duration(seconds: 60), (_) => widget.booth.prints.check());
  }

  @override
  void dispose() {
    _check?.cancel();
    super.dispose();
  }

  void _corner() {
    final now = DateTime.now();
    if (now.difference(_firstTap) > const Duration(seconds: 3)) {
      _firstTap = now;
      _cornerTaps = 0;
    }
    if (++_cornerTaps >= 5) {
      _cornerTaps = 0;
      openAdmin(context, widget.booth);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booth;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onStart,
      child: Stack(
        children: [
          ValueListenableBuilder(
            valueListenable: b.startImageVersion,
            builder: (_, version, _) => _Backdrop(file: b.startImage, version: version),
          ),
          Positioned(
            left: 48,
            right: 48,
            bottom: 56,
            child: ValueListenableBuilder(
              valueListenable: b.startImageVersion,
              builder: (_, _, _) => Column(
                children: [
                  // The event picture usually carries the title already.
                  if (!b.startImage.existsSync())
                    ListenableBuilder(
                      listenable: b.settings,
                      builder: (_, _) => Text(
                        b.settings.title,
                        textAlign: TextAlign.center,
                        style: TextStyles.hero.copyWith(fontSize: 84),
                      ),
                    ),
                  const SizedBox(height: 28),
                  BigButton(
                    label: 'Chạm để bắt đầu',
                    icon: Icons.photo_camera,
                    fontSize: 44,
                    onPressed: widget.onStart,
                  ),
                ],
              ),
            ),
          ),
          // Staff badge: printer and uploads.
          Positioned(left: 20, top: 20, child: _StaffBadge(booth: b)),
          // Hidden admin corner.
          Positioned(
            right: 0,
            top: 0,
            width: 110,
            height: 110,
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _corner),
          ),
        ],
      ),
    );
  }
}

class _StaffBadge extends StatelessWidget {
  const _StaffBadge({required this.booth});
  final Booth booth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([booth.prints, booth.uploads, booth.settings]),
      builder: (context, _) {
        final ok = booth.settings.printerUrl == null ? false : booth.prints.printerOk;
        final printerColor = switch (ok) {
          true => const Color(0xFF6FBF73),
          false => Palette.brick,
          null => Palette.mustard,
        };
        final failed = booth.prints.failedCount;
        final pending = booth.uploads.pendingSessions;
        final failing = booth.uploads.failingSessions;
        return DecoratedBox(
          decoration: BoxDecoration(color: const Color(0x991E1A16), borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (PRINTING) ...[
                  Icon(Icons.circle, size: 12, color: printerColor),
                  const SizedBox(width: 6),
                  Text(
                    booth.settings.printerUrl == null
                        ? 'Chưa chọn máy in'
                        : 'Máy in ${switch (ok) {
                                true => 'ok',
                                false => 'lỗi',
                                null => 'chưa kiểm tra',
                              }}'
                              '${failed > 0 ? ' · $failed lệnh lỗi' : ''}',
                    style: TextStyles.label.copyWith(color: Palette.paper, fontSize: 12),
                  ),
                  const SizedBox(width: 14),
                ],
                Icon(Icons.cloud_upload_outlined, size: 14, color: failing > 0 ? Palette.mustard : Palette.paper),
                const SizedBox(width: 6),
                Text(
                  pending == 0 ? 'đã lên hết' : '$pending chờ${failing > 0 ? ' ($failing đang thử lại)' : ''}',
                  style: TextStyles.label.copyWith(color: Palette.paper, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The event picture whole in the middle, the same picture blurred behind it so any
/// shape fills the screen. Paper when none is set.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.file, required this.version});
  final File file;
  final int version;

  @override
  Widget build(BuildContext context) {
    if (!file.existsSync()) return const ColoredBox(color: Palette.paper, child: SizedBox.expand());
    // Same path after a change: drop the cached decode.
    final image = FileImage(file);
    if (version > 0) image.evict();
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Image(
            image: image,
            fit: BoxFit.cover,
            color: const Color(0x55000000),
            colorBlendMode: BlendMode.darken,
          ),
        ),
        Image(image: image, fit: BoxFit.contain),
      ],
    );
  }
}
