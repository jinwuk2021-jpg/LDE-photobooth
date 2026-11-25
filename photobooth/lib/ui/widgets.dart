import 'package:film_camera/film_camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../booth/booth.dart';
import 'lux.dart';

/// The front camera full screen, mirrored like a mirror (the plugin never mirrors, as in Lensly).
class CameraView extends StatelessWidget {
  const CameraView(this.info, {super.key});
  final PreviewInfo? info;

  @override
  Widget build(BuildContext context) {
    final i = info;
    if (i == null) return const ColoredBox(color: Lux.night);
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: i.width.toDouble(),
          height: i.height.toDouble(),
          child: Transform.flip(flipX: true, child: Texture(textureId: i.textureId)),
        ),
      ),
    );
  }
}

/// What the guest sees while shooting: the Sony's live view when it is the camera taking the
/// photos (what you see is what is printed), else the iPad's front camera. Mirrored either way.
class BoothPreview extends StatefulWidget {
  const BoothPreview(this.booth, {super.key});
  final Booth booth;

  @override
  State<BoothPreview> createState() => _BoothPreviewState();
}

class _BoothPreviewState extends State<BoothPreview> {
  VoidCallback? _stopLive;

  @override
  void initState() {
    super.initState();
    if (widget.booth.settings.externalCamera) _stopLive = widget.booth.camera.sony.watchLive();
  }

  @override
  void dispose() {
    _stopLive?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cam = widget.booth.camera;
    return ValueListenableBuilder<Uint8List?>(
      valueListenable: cam.sony.frame,
      builder: (context, jpeg, _) => jpeg == null || _stopLive == null
          ? ValueListenableBuilder<PreviewInfo?>(
              valueListenable: cam.previewInfo,
              builder: (context, info, _) => CameraView(info),
            )
          : SonyLiveView(jpeg),
    );
  }
}

/// One Sony live view JPEG, full screen, mirrored.
class SonyLiveView extends StatelessWidget {
  const SonyLiveView(this.jpeg, {super.key, this.fit = BoxFit.cover});
  final Uint8List jpeg;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Transform.flip(
    flipX: true,
    child: Image.memory(jpeg, fit: fit, gaplessPlayback: true, width: double.infinity, height: double.infinity),
  );
}
