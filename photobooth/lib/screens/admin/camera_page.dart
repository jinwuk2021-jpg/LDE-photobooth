import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../booth/booth.dart';
import '../../camera/sony_camera.dart';
import '../../ui/lux.dart';
import '../../ui/widgets.dart';
import 'kit.dart';

/// Cài đặt – Máy ảnh: the Sony a6300 on the USB-C port (same layout as the printer page).
class CameraPage extends StatefulWidget {
  const CameraPage({super.key, required this.booth});
  final Booth booth;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  late final VoidCallback _stopLive = widget.booth.camera.sony.watchLive();
  Uint8List? _test;
  String? _testInfo;
  bool _shooting = false;

  @override
  void dispose() {
    _stopLive();
    super.dispose();
  }

  Future<void> _testShot() async {
    setState(() => _shooting = true);
    final sw = Stopwatch()..start();
    try {
      final jpeg = await widget.booth.camera.sony.capture();
      _test = jpeg;
      _testInfo = '${(jpeg.length / 1024).round()} KB · ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} giây';
      if (mounted) showToast(context, 'Chụp thử OK trong ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} giây');
    } catch (e) {
      _testInfo = null;
      if (mounted) showToast(context, 'Chụp thử lỗi: $e', icon: Icons.error_outline);
    }
    if (mounted) setState(() => _shooting = false);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booth;
    final cam = b.camera;
    final sony = cam.sony;
    final on = b.settings.externalCamera;
    return ListenableBuilder(
      listenable: sony,
      builder: (context, _) {
        final (pill, kind) = !on
            ? ('Dùng camera iPad', PillKind.none)
            : switch (sony.state) {
                SonyState.ready => ('Sẵn sàng', PillKind.ok),
                SonyState.connecting => ('Đang kết nối…', PillKind.wait),
                SonyState.absent => ('Chưa cắm máy ảnh', PillKind.bad),
                SonyState.error => ('Lỗi máy ảnh', PillKind.bad),
              };

        final current = AdminCard(
          title: 'Máy ảnh đang dùng',
          icon: Icons.photo_camera_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OptRow(
                label: 'Chụp bằng máy ảnh Sony',
                hint: on ? 'Lỗi tấm nào thì tấm đó dùng camera iPad' : 'Tắt: chụp bằng camera trước của iPad',
                trailing: GoldToggle(value: on, onChanged: (v) => setState(() => b.settings.externalCamera = v)),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  PicoIcon(Icons.photo_camera_outlined, dim: !sony.ready),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sony.name ?? 'Sony a6300',
                          style: LuxFonts.sans(size: 21, weight: FontWeight.w600),
                        ),
                        Text(
                          sony.ready
                              ? 'USB · PC Remote${sony.protocol == null ? '' : ' · giao thức ${sony.protocol}'}'
                              : 'USB · chưa kết nối',
                          style: monoStyle(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (sony.state == SonyState.error || sony.state == SonyState.absent)
                AlertBox(
                  Text(
                    sony.state == SonyState.absent
                        ? 'Chưa thấy máy ảnh. Bật máy, cắm cáp USB (loại có truyền dữ liệu), trên máy ảnh chọn '
                              'Setup → USB Connection → PC Remote.'
                        : (sony.error ?? 'Lỗi máy ảnh'),
                  ),
                )
              else
                Text(
                  sony.ready
                      ? 'Máy ảnh chụp ảnh cho khách, màn chụp hiện hình từ ống kính. Clip Live vẫn quay bằng camera iPad.'
                      : 'Đang bắt tay với máy ảnh…',
                  style: hintStyle(),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GoldButton(
                      label: _shooting ? 'Đang chụp…' : 'Chụp thử',
                      icon: Icons.camera_alt_outlined,
                      height: 60,
                      fontSize: 19,
                      onPressed: sony.ready && !_shooting ? _testShot : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LineButton(
                      label: 'Kết nối lại',
                      icon: Icons.usb,
                      height: 60,
                      fontSize: 19,
                      onPressed: sony.state == SonyState.absent ? null : sony.reconnect,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        final preview = AdminCard(
          title: _test == null ? 'Xem trước' : 'Ảnh chụp thử',
          icon: Icons.visibility_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 3 / 2,
                  child: ColoredBox(
                    color: Colors.black,
                    child: _test != null
                        ? Image.memory(_test!, fit: BoxFit.contain)
                        : ValueListenableBuilder<Uint8List?>(
                            valueListenable: sony.frame,
                            builder: (context, jpeg, _) => jpeg == null
                                ? Center(child: Text('Không có hình', style: hintStyle(size: 16)))
                                : SonyLiveView(jpeg, fit: BoxFit.contain),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (_test != null)
                Row(
                  children: [
                    Expanded(child: Text(_testInfo ?? '', style: hintStyle())),
                    TextLink('Về xem trước', onTap: () => setState(() => _test = null)),
                  ],
                )
              else
                Text('Gắn máy ảnh sát camera iPad, chỉnh ống kính cho khung vừa người đứng.', style: hintStyle()),
            ],
          ),
        );

        final checks = AdminCard(
          title: 'Kiểm tra nhanh',
          icon: Icons.info_outline,
          child: Column(
            children: [
              CheckRow(
                ok: sony.state != SonyState.absent,
                label: 'Đã cắm máy ảnh',
                value: sony.name ?? 'Chưa thấy',
              ),
              CheckRow(ok: sony.ready, label: 'Chế độ PC Remote', value: sony.ready ? 'OK' : '—'),
              ValueListenableBuilder<Uint8List?>(
                valueListenable: sony.frame,
                builder: (context, jpeg, _) =>
                    CheckRow(ok: jpeg != null, label: 'Hình xem trước', value: jpeg != null ? 'Có' : 'Không có'),
              ),
              CheckRow(
                ok: cam.sonyMisses == 0,
                label: 'Ảnh phải dùng camera iPad',
                value: '${cam.sonyMisses} / ${cam.sonyShots + cam.sonyMisses}',
              ),
            ],
          ),
        );

        final log = AdminCard(
          title: 'Nhật ký kết nối',
          icon: Icons.notes,
          child: sony.history.isEmpty
              ? Text('Chưa có gì.', style: hintStyle())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in sony.history.reversed.take(8))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(line, style: monoStyle(size: 13)),
                      ),
                    const SizedBox(height: 6),
                    Text('Gặp lỗi thì chụp màn hình phần này gửi Claude.', style: hintStyle()),
                  ],
                ),
        );

        return ListView(
          padding: const EdgeInsets.fromLTRB(0, 40, 0, 40),
          children: [
            PageHeader(
              title: 'Máy ảnh',
              subtitle: const Text('Sony a6300 cắm cáp USB · chế độ PC Remote'),
              trailing: StatusPill(pill, kind),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 125,
                  child: Column(children: [current, const SizedBox(height: 24), log]),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 100,
                  child: Column(children: [preview, const SizedBox(height: 24), checks]),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
