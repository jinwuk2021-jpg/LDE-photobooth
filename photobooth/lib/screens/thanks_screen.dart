import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../booth/booth.dart';
import '../booth/print_layout.dart';
import '../config.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// "Đang in!": big QR to the photos and clips, the print beside it.
/// Back to the start after [THANKS_TIMEOUT] or "Xong".
class ThanksScreen extends StatefulWidget {
  const ThanksScreen({super.key, required this.finished, required this.onDone});
  final Finished finished;
  final VoidCallback onDone;

  @override
  State<ThanksScreen> createState() => _ThanksScreenState();
}

class _ThanksScreenState extends State<ThanksScreen> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(THANKS_TIMEOUT, widget.onDone);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Palette.paper,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(PRINTING ? 'Đang in!' : 'Xong rồi!', style: TextStyles.hero),
                    const SizedBox(height: 8),
                    Text(
                      'Quét mã để lấy ảnh & video',
                      textAlign: TextAlign.center,
                      style: TextStyles.title.copyWith(color: Palette.kraftInk),
                    ),
                    const SizedBox(height: 28),
                    SizedBox.square(dimension: 340, child: CustomPaint(painter: QrPainter(widget.finished.url))),
                    const SizedBox(height: 14),
                    Text(
                      'Ảnh có ngay, video Live lên sau 1–2 phút. Trang tự cập nhật, không cần quét lại.',
                      textAlign: TextAlign.center,
                      style: TextStyles.body.copyWith(color: Palette.kraftInk),
                    ),
                    const SizedBox(height: 28),
                    BigButton(label: 'Xong', icon: Icons.check, onPressed: widget.onDone),
                  ],
                ),
              ),
              const SizedBox(width: 40),
              Expanded(
                flex: 2,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: widget.finished.aspect,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        boxShadow: [BoxShadow(color: Color(0x731E1A16), blurRadius: 18, offset: Offset(0, 10))],
                      ),
                      child: Image.file(File(widget.finished.printPath), fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
