import 'dart:async';

import '../config.dart';

enum BoothPhase { idle, countdown, capturing, finished, cancelled }

class BoothState {
  const BoothState({
    this.phase = BoothPhase.idle,
    this.shotIndex = 0,
    this.remaining = 0,
    this.taken = 0,
    this.total = SHOTS,
  });

  final BoothPhase phase;

  /// 0-based index of the shot being counted down / taken.
  final int shotIndex;

  /// Seconds left on the countdown (shown as the big flip number).
  final int remaining;

  /// Shots captured so far.
  final int taken;
  final int total;

  bool get running => phase == BoothPhase.countdown || phase == BoothPhase.capturing;

  BoothState copyWith({BoothPhase? phase, int? shotIndex, int? remaining, int? taken}) => BoothState(
    phase: phase ?? this.phase,
    shotIndex: shotIndex ?? this.shotIndex,
    remaining: remaining ?? this.remaining,
    taken: taken ?? this.taken,
    total: total,
  );

  @override
  String toString() => 'Booth($phase shot=$shotIndex rem=$remaining taken=$taken/$total)';
}

/// The automatic photobooth: one press → N × (countdown, flash, shot) with
/// no further taps. Pure Dart timing so it is testable with fake_async.
class PhotoboothSequence {
  PhotoboothSequence({
    required this.capture,
    this.shots = SHOTS,
    this.countdownFor = defaultCountdown,
    this.onTick,
    this.onChange,
    this.onError,
  }) : _state = BoothState(total: shots);

  /// Takes shot [index]. Called at countdown zero (after the flash starts).
  final Future<void> Function(int index) capture;
  final int shots;

  /// Seconds counted down before shot [index].
  final int Function(int index) countdownFor;

  static int defaultCountdown(int index) => index == 0 ? FIRST_COUNTDOWN : NEXT_COUNTDOWN;

  /// Each countdown second, with the number displayed (beep here).
  final void Function(int remaining)? onTick;
  final void Function(BoothState state)? onChange;
  final void Function(Object error)? onError;

  BoothState _state;
  BoothState get state => _state;
  Timer? _timer;
  int _generation = 0;

  void _set(BoothState s) {
    _state = s;
    onChange?.call(s);
  }

  void start() {
    if (_state.running) return;
    _generation++;
    _set(BoothState(total: shots));
    _countdown(0);
  }

  void _countdown(int index) {
    final countdown = countdownFor(index);
    _set(_state.copyWith(phase: BoothPhase.countdown, shotIndex: index, remaining: countdown));
    onTick?.call(countdown);
    final gen = _generation;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (gen != _generation) return t.cancel();
      final left = _state.remaining - 1;
      if (left > 0) {
        _set(_state.copyWith(remaining: left));
        onTick?.call(left);
      } else {
        t.cancel();
        _shoot(index, gen);
      }
    });
  }

  Future<void> _shoot(int index, int gen) async {
    _set(_state.copyWith(phase: BoothPhase.capturing, remaining: 0));
    try {
      await capture(index);
    } catch (e) {
      if (gen != _generation) return;
      onError?.call(e);
      cancel();
      return;
    }
    if (gen != _generation) return; // cancelled while capturing
    final taken = index + 1;
    _set(_state.copyWith(taken: taken));
    if (taken >= shots) {
      _set(_state.copyWith(phase: BoothPhase.finished));
    } else {
      _countdown(index + 1);
    }
  }

  /// Stops the sequence. Returns how many shots were already taken so the
  /// UI can ask whether to keep them.
  int cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    if (_state.running) _set(_state.copyWith(phase: BoothPhase.cancelled));
    return _state.taken;
  }

  void reset() {
    cancel();
    _set(BoothState(total: shots));
  }

  void dispose() {
    _generation++;
    _timer?.cancel();
  }
}
