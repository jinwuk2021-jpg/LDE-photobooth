import 'package:flutter/material.dart';

import '../booth/booth.dart';
import '../camera/photobooth_sequence.dart';
import '../ui/flip_countdown.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// Six automatic shots: big countdown (5 s, then 3 s), white flash, progress dots.
/// Lensly's Live recorder runs for the whole sequence.
class ShootScreen extends StatefulWidget {
  const ShootScreen({
    super.key,
    required this.booth,
    required this.guest,
    required this.onDone,
    required this.onFailed,
  });
  final Booth booth;
  final GuestSession guest;
  final VoidCallback onDone;
  final VoidCallback onFailed;

  @override
  State<ShootScreen> createState() => _ShootScreenState();
}

class _ShootScreenState extends State<ShootScreen> {
  late final PhotoboothSequence _sequence;
  late BoothState _state = BoothState(total: widget.guest.layout.shots);
  bool _flash = false;

  @override
  void initState() {
    super.initState();
    _sequence = PhotoboothSequence(
      shots: widget.guest.layout.shots,
      capture: _capture,
      onChange: (s) {
        if (!mounted) return;
        setState(() => _state = s);
        if (s.phase == BoothPhase.finished) _finish(ok: true);
      },
      onError: (_) => _finish(ok: false),
    );
    widget.booth.camera.live.start().whenComplete(() {
      if (mounted) _sequence.start();
    });
  }

  @override
  void dispose() {
    _sequence.dispose();
    super.dispose();
  }

  Future<void> _capture(int index) async {
    // Flash first: it is the face light (as in Lensly).
    setState(() => _flash = true);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    try {
      final b = widget.booth;
      widget.guest.shots.add(
        await b.camera.capture(index, cellAspect: widget.guest.layout.cellAspect, skin: b.settings.skin),
      );
    } finally {
      if (mounted) setState(() => _flash = false);
    }
  }

  Future<void> _finish({required bool ok}) async {
    // Every shot's clip is cut (pinned) already: stopping keeps them.
    await widget.booth.camera.live.stop();
    if (!mounted) return;
    ok ? widget.onDone() : widget.onFailed();
  }

  @override
  Widget build(BuildContext context) {
    final counting = _state.phase == BoothPhase.countdown;
    return Stack(
      children: [
        CameraView(widget.booth.camera.preview),
        Positioned(
          top: 28,
          left: 0,
          right: 0,
          child: Column(
            children: [
              ShotDots(total: _state.total, taken: _state.taken, current: _state.shotIndex),
              const SizedBox(height: 12),
              Text(
                'Tấm ${_state.shotIndex + 1} / ${_state.total}',
                style: TextStyles.title.copyWith(color: Palette.paper, shadows: const [Shadow(blurRadius: 8)]),
              ),
            ],
          ),
        ),
        // Top-left corner, out of the faces.
        if (counting) Positioned(left: 28, top: 28, child: FlipCountdown(value: _state.remaining, size: 150)),
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _flash ? 1 : 0,
            duration: Duration(milliseconds: _flash ? 40 : 320),
            child: const ColoredBox(color: Palette.flash, child: SizedBox.expand()),
          ),
        ),
      ],
    );
  }
}
