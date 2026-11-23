import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../booth/booth.dart';
import '../config.dart';
import '../booth/print_layout.dart';
import '../camera/filters.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// Pick the frame's photos (tap order = print order) and a filter, with the
/// print preview beside. "Chụp lại" / "In". A visible countdown: when it runs
/// out the first shots not picked fill the frame and it prints by itself.
class PickScreen extends StatefulWidget {
  const PickScreen({
    super.key,
    required this.booth,
    required this.guest,
    required this.onRetake,
    required this.onPrinted,
  });
  final Booth booth;
  final GuestSession guest;
  final VoidCallback onRetake;
  final ValueChanged<Finished> onPrinted;

  @override
  State<PickScreen> createState() => _PickScreenState();
}

class _PickScreenState extends State<PickScreen> {
  BoothFilter _filter = BoothFilter.values.first;

  /// The shots through [_filter]; null while developing the first time.
  List<ui.Image>? _images;
  final Map<BoothFilter, ui.Image> _thumbs = {};
  int _generation = 0;
  bool _developing = false;
  bool _printing = false;

  /// The shots could not be processed: only "Chụp lại" is left.
  bool _failed = false;

  /// Seconds left to pick; starts once the photos show.
  late int _secondsLeft = widget.booth.settings.pickSeconds;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _develop(_filter);
    _makeThumbs();
  }

  @override
  void dispose() {
    _clock?.cancel();
    final images = _images, thumbs = _thumbs.values.toList();
    // After the last frame that may still paint them.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      images?.forEach((i) => i.dispose());
      for (final t in thumbs) {
        t.dispose();
      }
    });
    super.dispose();
  }

  Future<void> _develop(BoothFilter filter) async {
    final gen = ++_generation;
    setState(() {
      _filter = filter;
      _developing = true;
    });
    final List<ui.Image> images;
    try {
      images = await widget.booth.developAll(widget.guest, filter);
    } catch (_) {
      // Also lands here when "Chụp lại" freed the shots meanwhile.
      if (mounted && gen == _generation) setState(() => _failed = true);
      return;
    }
    if (!mounted || gen != _generation) {
      for (final i in images) {
        i.dispose();
      }
      return;
    }
    final old = _images;
    setState(() {
      _images = images;
      _developing = false;
    });
    SchedulerBinding.instance.addPostFrameCallback((_) => old?.forEach((i) => i.dispose()));
    _clock ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    // Time ran out while a filter was developing.
    if (_secondsLeft <= 0) _timeUp();
  }

  void _tick() {
    if (_printing) return;
    setState(() => _secondsLeft--);
    if (_secondsLeft <= 0) _timeUp();
  }

  void _timeUp() {
    _clock?.cancel();
    if (_developing || _failed || _printing) return;
    widget.guest.fillPicks();
    _print();
  }

  /// One small sample of the first shot per filter, for the filter buttons.
  Future<void> _makeThumbs() async {
    try {
      await _makeThumbsUnsafe();
    } catch (_) {
      // Shots freed by "Chụp lại" or not processable: the buttons stay plain.
    }
  }

  Future<void> _makeThumbsUnsafe() async {
    final base = await widget.guest.shots.first.base;
    const w = 240;
    final h = (w * base.height / base.width).round();
    final rec = ui.PictureRecorder();
    Canvas(rec).drawImageRect(
      base,
      Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final small = await rec.endRecording().toImage(w, h);
    for (final f in BoothFilter.values) {
      final t = await widget.booth.camera.develop(small, f, '0');
      if (!mounted) return t.dispose();
      setState(() => _thumbs[f] = t);
    }
    small.dispose();
  }

  Future<void> _print() async {
    final images = _images;
    if (images == null || !widget.guest.complete || _printing) return;
    setState(() => _printing = true);
    try {
      widget.onPrinted(await widget.booth.finish(widget.guest, _filter, images));
    } catch (e) {
      if (!mounted) return;
      setState(() => _printing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không tạo được ảnh in: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final guest = widget.guest;
    return ColoredBox(
      color: Palette.paper,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 24),
          child: ListenableBuilder(
            listenable: guest,
            builder: (context, _) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _left(guest)),
                const SizedBox(width: 32),
                Expanded(flex: 2, child: _right(guest)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _left(GuestSession guest) {
    final images = _images;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Chọn ${guest.layout.picks} tấm đẹp nhất (${guest.picks.length}/${guest.layout.picks})',
                style: TextStyles.title,
              ),
            ),
            _Clock(seconds: _secondsLeft),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Chạm theo thứ tự muốn in. Chạm lại để bỏ chọn.',
          style: TextStyles.body.copyWith(color: Palette.kraftInk),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _failed
              ? const Center(child: Text('Không xử lý được ảnh. Bấm "Chụp lại" nhé!', style: TextStyles.title))
              : images == null
              ? const Center(child: CircularProgressIndicator(color: Palette.brick))
              : Column(
                  children: [
                    // Two rows: 3 + 3 shots, or 4 + 4 for 6 Cut.
                    for (var row = 0; row < 2; row++)
                      Expanded(
                        child: Row(
                          children: [
                            for (var col = 0; col < (images.length + 1) ~/ 2; col++)
                              Expanded(
                                child: row * ((images.length + 1) ~/ 2) + col < images.length
                                    ? _tile(guest, images, row * ((images.length + 1) ~/ 2) + col)
                                    : const SizedBox(),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        SizedBox(height: 132, child: _filters()),
      ],
    );
  }

  Widget _tile(GuestSession guest, List<ui.Image> images, int i) {
    final order = guest.picks.indexOf(i);
    final picked = order >= 0;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        onTap: () => guest.toggle(i),
        child: Center(
          child: AspectRatio(
            aspectRatio: images[i].width / images[i].height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    border: Border.all(color: picked ? Palette.brick : Palette.paper, width: 6),
                    boxShadow: const [BoxShadow(color: Color(0x401E1A16), blurRadius: 6, offset: Offset(0, 3))],
                  ),
                  child: RawImage(image: images[i], fit: BoxFit.cover),
                ),
                if (picked)
                  Positioned(
                    left: 10,
                    top: 10,
                    child: CircleAvatar(
                      radius: 26,
                      backgroundColor: Palette.brick,
                      child: Text('${order + 1}', style: TextStyles.button.copyWith(fontSize: 32)),
                    ),
                  ),
                if (_developing) const ColoredBox(color: Color(0x33EFE6D0)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filters() {
    return Row(
      children: [
        for (final f in BoothFilter.values)
          Expanded(
            child: GestureDetector(
              onTap: f == _filter ? null : () => _develop(f),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: f == _filter ? Palette.brick : Palette.paperDeep, width: 4),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _thumbs[f] == null
                            ? const ColoredBox(color: Palette.paperDeep)
                            : RawImage(image: _thumbs[f], fit: BoxFit.cover, width: double.infinity),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      f.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyles.label.copyWith(
                        fontSize: 15,
                        fontWeight: f == _filter ? FontWeight.w700 : FontWeight.w400,
                        color: f == _filter ? Palette.brickInk : Palette.coffee,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _right(GuestSession guest) {
    final images = _images;
    final s = widget.booth.settings;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: guest.layout.size.aspectRatio,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  boxShadow: [BoxShadow(color: Color(0x551E1A16), blurRadius: 16, offset: Offset(0, 8))],
                ),
                child: CustomPaint(
                  painter: PrintPainter(
                    PrintSpec(
                      layout: guest.layout,
                      photos: [
                        for (var k = 0; k < guest.layout.picks; k++)
                          k < guest.picks.length && images != null ? images[guest.picks[k]] : null,
                      ],
                      title: s.title,
                      dateLine: s.dateLine,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BigButton(
              label: 'Chụp lại',
              icon: Icons.replay,
              outlined: true,
              fontSize: 28,
              onPressed: _printing ? null : widget.onRetake,
            ),
            const SizedBox(width: 20),
            BigButton(
              label: _printing ? 'Đang xử lý…' : (PRINTING ? 'In' : 'Xong'),
              icon: Icons.print,
              fontSize: 34,
              onPressed: guest.complete && images != null && !_developing && !_printing ? _print : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Seconds left to pick, red for the last 10.
class _Clock extends StatelessWidget {
  const _Clock({required this.seconds});
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final urgent = seconds <= 10;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: urgent ? Palette.brick : Palette.coffee,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, color: Palette.paper, size: 28),
          const SizedBox(width: 8),
          Text('${seconds.clamp(0, 999)} giây', style: TextStyles.button.copyWith(fontSize: 28)),
        ],
      ),
    );
  }
}
