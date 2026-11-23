import 'package:film_camera/film_camera.dart';
import 'package:flutter/material.dart';

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
