import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../booth/booth.dart';
import '../camera/photobooth_sequence.dart';
import '../config.dart';
import '../ui/lux.dart';
import '../ui/strings.dart';
import '../ui/sparkle.dart';
import '../ui/widgets.dart';

/// 3 · Shooting: the mirrored camera full screen with a vignette, a glass status pill (dots +
/// "Tấm x / n"), 3 s "Chuẩn bị nhé!", then a flip countdown in the top-left glass card
/// (5 s first, 3 s after), a white flash and a gold spark burst per shot.
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

class _ShootScreenState extends State<ShootScreen> with TickerProviderStateMixin {
  late final PhotoboothSequence _sequence;
  late BoothState _state = BoothState(total: widget.guest.frame.shots);

  /// White flash: 40 ms up, 120 ms held, 260 ms down.
  late final AnimationController _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  /// Spark burst right after the flash (760 ms).
  late final AnimationController _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 760));

  /// "Chuẩn bị" bar (3 s) and the nudging arrow.
  late final AnimationController _ready = AnimationController(vsync: this, duration: READY_DELAY)..forward();
  late final AnimationController _nudge = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _sequence = PhotoboothSequence(
      shots: widget.guest.frame.shots,
      capture: _capture,
      onChange: (s) {
        if (!mounted) return;
        setState(() => _state = s);
        if (s.phase == BoothPhase.finished) _finish(ok: true);
      },
      onError: (_) => _finish(ok: false),
    );
    // Live starts now (the encoder warms up), the countdown after READY_DELAY.
    Future.wait([widget.booth.camera.live.start().catchError((_) {}), Future<void>.delayed(READY_DELAY)])
        .whenComplete(() {
          if (mounted) _sequence.start();
        });
  }

  @override
  void dispose() {
    _sequence.dispose();
    _flash.dispose();
    _burst.dispose();
    _ready.dispose();
    _nudge.dispose();
    super.dispose();
  }

  Future<void> _capture(int index) async {
    // Flash first: it is the face light (as in Lensly).
    HapticFeedback.mediumImpact();
    _flash.forward(from: 0);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    try {
      final b = widget.booth;
      widget.guest.shots.add(
        await b.camera.capture(index, cellAspect: widget.guest.frame.cellAspect, skin: b.settings.skin),
      );
    } finally {
      if (mounted) _burst.forward(from: 0);
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
    final getReady = _state.phase == BoothPhase.idle;
    final counting = _state.phase == BoothPhase.countdown;
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraView(widget.booth.camera.preview),
        // Vignette + a darker top for the pill.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(radius: 0.9, colors: [Color(0x000B0B12), Color(0x9E0B0B12)], stops: [0.55, 1]),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x730B0B12), Color(0x000B0B12)],
              stops: [0, 0.22],
            ),
          ),
        ),
        const SparkleBackground(level: SparkleLevel.low, seed: 33),
        if (getReady) ...[
          const ColoredBox(color: Color(0x610B0B12)),
          Positioned(
            left: 0,
            right: 0,
            top: 250,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.92, end: 1),
              duration: const Duration(milliseconds: 480),
              curve: Curves.easeOutQuint,
              builder: (context, s, child) => Transform.scale(scale: s, child: child),
              child: Column(
                children: [
                  GoldText(T.now.getReady, style: LuxFonts.serif(size: 112, weight: FontWeight.w700, height: 1.1)),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _nudge,
                        builder: (context, child) => Transform.translate(
                          offset: Offset(0, -8 * Curves.easeInOut.transform(_nudge.value)),
                          child: child,
                        ),
                        child: const Icon(Icons.arrow_upward_rounded, color: Lux.champagneLight, size: 40),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        T.now.lookAtCamera,
                        style: LuxFonts.sans(
                          size: 38,
                          weight: FontWeight.w500,
                          color: Lux.ivory,
                        ).copyWith(shadows: const [Shadow(color: Color(0x99000000), blurRadius: 16)]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 64,
            child: Center(
              child: Container(
                width: 360,
                height: 4,
                decoration: BoxDecoration(color: Lux.ivoryA(0.18), borderRadius: BorderRadius.circular(2)),
                alignment: Alignment.centerLeft,
                child: AnimatedBuilder(
                  animation: _ready,
                  builder: (context, _) => FractionallySizedBox(
                    widthFactor: _ready.value,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: const LinearGradient(colors: Lux.metal, stops: Lux.metalStops),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        Positioned(
          top: 26,
          left: 0,
          right: 0,
          child: Center(
            child: _StatusPill(state: _state, ready: getReady),
          ),
        ),
        if (counting) Positioned(left: 36, top: 36, child: _CountdownCard(value: _state.remaining)),
        AnimatedBuilder(
          animation: _burst,
          builder: (context, _) => SparkBurst(progress: _burst.value),
        ),
        AnimatedBuilder(
          animation: _flash,
          builder: (context, _) {
            final ms = _flash.value * 420;
            final a = ms < 40 ? ms / 40 : (ms < 160 ? 1.0 : 1 - const Cubic(.2, .8, .2, 1).transform((ms - 160) / 260));
            return IgnorePointer(
              child: ColoredBox(color: Lux.flash.withValues(alpha: _flash.isAnimating ? a.clamp(0, 1) : 0)),
            );
          },
        ),
      ],
    );
  }
}

/// Dots (done = gold pop, current = pulsing ring) | "Tấm 2 / 6" (or "Sắp chụp 6 tấm").
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state, required this.ready});
  final BoothState state;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final dim = LuxFonts.sans(size: 22, weight: FontWeight.w600, color: Lux.ivoryA(0.7));
    final gold = LuxFonts.sans(size: 22, weight: FontWeight.w600);
    return Glass(
      radius: 999,
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < state.total; i++) ...[
            _Dot(done: i < state.taken, current: i == state.shotIndex && i >= state.taken),
            if (i < state.total - 1) const SizedBox(width: 12),
          ],
          const SizedBox(width: 20),
          Container(width: 1, height: 26, color: const Color(0x73D4AF6A)),
          const SizedBox(width: 20),
          if (ready) ...[
            Text(T.now.aboutToTake, style: dim),
            GoldText(T.now.photos(state.total), style: gold, sweep: false),
          ] else ...[
            if (T.now.shot.isNotEmpty) Text(T.now.shot, style: dim),
            GoldText('${state.shotIndex + 1}', style: gold, sweep: false),
            Text(' / ${state.total}', style: dim),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot({required this.done, required this.current});
  final bool done;
  final bool current;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: widget.done ? Lux.button : null,
        border: Border.all(
          color: widget.done || widget.current ? Lux.champagneLight : Lux.ivoryA(0.45),
          width: widget.current ? 2 : 1.5,
        ),
        boxShadow: widget.done ? const [BoxShadow(color: Color(0xBFF5E1A4), blurRadius: 10)] : null,
      ),
    );
    if (!widget.current) {
      return widget.done
          ? TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.4, end: 1),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              builder: (context, s, child) => Transform.scale(scale: s, child: child),
              child: dot,
            )
          : dot;
    }
    // Current: a ring ripples out 8 pt every 1.2 s.
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 14 + 16 * _pulse.value,
            height: 14 + 16 * _pulse.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Lux.champagneLight.withValues(alpha: 0.6 * (1 - _pulse.value))),
            ),
          ),
          child!,
        ],
      ),
      child: dot,
    );
  }
}

/// Glass card (220 × 272) with the number flipping in (rotateX 90° → −8° → 0, 420 ms) and a gold
/// ring flaring out each second.
class _CountdownCard extends StatelessWidget {
  const _CountdownCard({required this.value});
  final int value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 272,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Glass(
            width: 220,
            height: 272,
            radius: 30,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 272 * 0.46,
                  child: Container(color: const Color(0x09FFF6DA)),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  top: 272 * 0.46,
                  child: Container(height: 1, color: const Color(0x8C000000)),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 22,
                  child: Text(
                    T.now.seconds,
                    textAlign: TextAlign.center,
                    style: LuxFonts.eyebrow(color: Lux.ivoryA(0.7)),
                  ),
                ),
              ],
            ),
          ),
          // Ring flare, restarted by the key on each new second.
          Positioned(
            left: 110 - 95,
            top: 272 * 0.46 - 95,
            child: TweenAnimationBuilder<double>(
              key: ValueKey('ring$value'),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: const Cubic(.2, .7, .3, 1),
              builder: (context, p, _) => IgnorePointer(
                child: Transform.scale(
                  scale: 0.6 + 1.3 * p,
                  child: Container(
                    width: 190,
                    height: 190,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Lux.champagneLight.withValues(alpha: 0.95 * (1 - p)), width: 3),
                      boxShadow: [
                        BoxShadow(color: Lux.champagneLight.withValues(alpha: 0.6 * (1 - p)), blurRadius: 30),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 20,
            height: 190,
            child: Center(
              child: TweenAnimationBuilder<double>(
                key: ValueKey('n$value'),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 420),
                curve: const Cubic(.2, .9, .3, 1.2),
                builder: (context, p, child) => Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 1 / 700)
                    ..rotateX((1 - p) * math.pi / 2),
                  child: child,
                ),
                child: GoldText(
                  '$value',
                  style: LuxFonts.serif(size: 180, weight: FontWeight.w700, height: 1),
                  sweep: false,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
