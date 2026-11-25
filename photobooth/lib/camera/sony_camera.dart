import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ptp.dart';

enum SonyState {
  /// Nothing on the USB-C port.
  absent,

  /// Plugged in, opening the session / "PC Remote" handshake.
  connecting,

  /// Takes pictures and live view.
  ready,

  /// Plugged in but not usable ([SonyCamera.error] says why).
  error,
}

/// A Sony camera (a6300) on the USB-C port in "PC Remote" mode, driven with Sony's PTP
/// extension (SDIO) as libgphoto2 does: handshake, half / full press, picture from the camera's
/// buffer (object 0xFFFFC001), live view frames (object 0xFFFFC002).
///
/// Every PTP command goes through one queue, so live view frames simply wait while a picture
/// is taken and downloaded.
class SonyCamera extends ChangeNotifier {
  SonyCamera(this._t, {this.onLog, this.pollEvery = const Duration(milliseconds: 60)});

  final PtpTransport _t;
  final void Function(String line)? onLog;

  /// Pause between buffer checks while a picture is being made.
  final Duration pollEvery;

  SonyState state = SonyState.absent;

  /// USB name of the camera ("ILCE-6300").
  String? name;

  /// Why it is not ready.
  String? error;

  /// Sony's protocol version (from the handshake).
  int? protocol;

  /// Last few lines of what happened (admin shows them).
  final List<String> history = [];

  /// Latest live view JPEG (null when there is none).
  final ValueNotifier<Uint8List?> frame = ValueNotifier(null);

  bool get ready => state == SonyState.ready;

  StreamSubscription<PtpDeviceEvent>? _sub;
  Future<void> _queue = Future.value();
  int _liveUsers = 0;
  bool _liveRunning = false;
  bool _handshaking = false;
  bool _isSony = false;

  void _log(String s) {
    history.add(s);
    if (history.length > 30) history.removeAt(0);
    onLog?.call(s);
    debugPrint('[sony] $s');
  }

  void _set(SonyState s, {String? err}) {
    state = s;
    error = err;
    if (s != SonyState.ready) frame.value = null;
    notifyListeners();
  }

  /// Starts watching the USB-C port. Called once from main().
  Future<void> start() async {
    _sub ??= _t.events.listen(_onEvent);
    try {
      _log('start: ${await _t.start()}');
    } catch (e) {
      _log('start failed: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    frame.dispose();
    super.dispose();
  }

  void _onEvent(PtpDeviceEvent e) {
    switch (e) {
      case PtpAdded():
        name = e.name;
        _log('plugged in: ${e.name} (USB ${_hex(e.vendorId)}:${_hex(e.productId)})');
        _isSony = e.vendorId == Ptp.sonyVendorId;
        if (!_isSony) {
          _set(SonyState.error, err: 'Không phải máy ảnh Sony (${e.name})');
        } else {
          _set(SonyState.connecting);
          if (e.open) unawaited(connect());
        }
      case PtpOpened():
        if (e.error != null) {
          _log('session failed: ${e.error}');
          _set(SonyState.error, err: 'Không mở được kết nối: ${e.error}');
        } else if (_isSony) {
          unawaited(connect());
        }
      case PtpRemoved():
        _log('unplugged');
        name = null;
        _isSony = false;
        _set(SonyState.absent);
      case PtpEvent():
        break;
    }
  }

  /// One command at a time on the cable.
  Future<T> _serial<T>(Future<T> Function() f) {
    final run = _queue.then((_) => f());
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<PtpResponse> _cmd(int code, [List<int> params = const [], Uint8List? out]) async {
    final r = await _t.send(code, params, out);
    if (!r.ok) throw PtpError(code, r.code);
    return r;
  }

  /// "PC Remote" handshake (libgphoto2 camera_init for Sony): SDIO connect 1, 2, the extension's
  /// property list, connect 3, then wait until the camera reports its properties.
  Future<void> connect() async {
    if (_handshaking) return;
    _handshaking = true;
    _set(SonyState.connecting);
    try {
      await _serial(() async {
        await _cmd(Ptp.sdioConnect, [1, 0, 0]);
        await _cmd(Ptp.sdioConnect, [2, 0, 0]);
        final info = await _cmd(Ptp.sdioGetExtDeviceInfo, [0xC8]);
        protocol = info.data.length >= 2 ? info.data[0] | info.data[1] << 8 : null;
        await _cmd(Ptp.sdioConnect, [3, 0, 0]);
        for (var i = 0; ; i++) {
          try {
            final props = await _props();
            if (props.isNotEmpty) break;
          } catch (e) {
            if (i >= 20) rethrow;
          }
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      });
      _log('ready (protocol ${protocol ?? "?"})');
      _set(SonyState.ready);
      _pumpLive();
    } catch (e) {
      _log('handshake failed: $e');
      _set(SonyState.error, err: _explain(e));
    } finally {
      _handshaking = false;
    }
  }

  /// Staff "Kết nối lại": a new session and handshake.
  Future<void> reconnect() async {
    _log('reconnect');
    _set(SonyState.connecting);
    try {
      await _t.reopen();
    } catch (e) {
      _log('reopen failed: $e');
    }
    // The "opened" event starts the handshake; a session that was still open needs it now.
    await Future<void>.delayed(const Duration(seconds: 2));
    if (state == SonyState.connecting && !_handshaking) await connect();
  }

  Future<Map<int, int>> _props() async {
    final r = await _cmd(Ptp.sdioGetAllExtDevicePropInfo);
    return parseSonyProps(r.data);
  }

  /// Pictures in the camera's buffer, or null when the properties cannot be read.
  Future<int?> _inMemory() async {
    try {
      final v = (await _props())[Ptp.propObjectInMemory];
      return v == null ? null : (v > 0x8000 ? v - 0x8000 : 0);
    } catch (_) {
      return null;
    }
  }

  Future<void> _press(int prop, int value) =>
      _cmd(Ptp.sdioSetControlDeviceB, [prop], Uint8List.fromList([value & 0xFF, value >> 8]));

  /// Takes a picture and returns its JPEG (set the camera to JPEG, not RAW).
  Future<Uint8List> capture({Duration timeout = const Duration(seconds: 8)}) {
    if (!ready) return Future.error(StateError(error ?? 'Máy ảnh chưa sẵn sàng'));
    final sw = Stopwatch()..start();
    return _serial(() async {
      // A picture left in the buffer (an earlier one that timed out) would come back instead.
      for (var i = 0; i < 5 && ((await _inMemory()) ?? 0) > 0; i++) {
        await _download();
        _log('dropped an old picture from the buffer');
      }
      await _press(Ptp.propAutoFocus, 2);
      await _press(Ptp.propCapture, 2);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await _press(Ptp.propCapture, 1);
      await _press(Ptp.propAutoFocus, 1);
      final deadline = DateTime.now().add(timeout);
      while (true) {
        final n = await _inMemory();
        // Properties unreadable: ask for the picture itself until it is there.
        if (n == null) {
          final info = await _t.send(Ptp.getObjectInfo, [Ptp.capturedObject]);
          if (info.ok && info.data.length >= 12 && _u32(info.data, 8) > 0) break;
        } else if (n > 0) {
          break;
        }
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('Máy ảnh không trả ảnh sau ${timeout.inSeconds} giây (kiểm tra lấy nét / thẻ / pin)');
        }
        await Future<void>.delayed(pollEvery);
      }
      final jpeg = await _download();
      _log('picture ${(jpeg.length / 1024).round()} KB in ${sw.elapsedMilliseconds} ms');
      return jpeg;
    }).catchError((Object e) {
      _log('capture failed: $e');
      // Unplugged or switched off mid-picture: not usable until it is back.
      if (e is PlatformException && e.code == 'closed') _set(SonyState.error, err: 'Mất kết nối máy ảnh');
      throw e;
    });
  }

  Future<Uint8List> _download() async {
    await _cmd(Ptp.getObjectInfo, [Ptp.capturedObject]);
    final r = await _cmd(Ptp.getObject, [Ptp.capturedObject]);
    final jpeg = extractJpeg(r.data);
    if (jpeg == null) throw const FormatException('Ảnh từ máy ảnh không phải JPEG (tắt RAW trên máy)');
    return jpeg;
  }

  /// One live view frame (JPEG), or null.
  Future<Uint8List?> liveFrame() => _serial(() async {
    final r = await _t.send(Ptp.getObject, [Ptp.liveViewObject]);
    return r.ok ? extractJpeg(r.data) : null;
  });

  /// Live view frames into [frame] while at least one screen watches. Returns the stop call.
  VoidCallback watchLive() {
    _liveUsers++;
    _pumpLive();
    var stopped = false;
    return () {
      if (stopped) return;
      stopped = true;
      _liveUsers--;
    };
  }

  Future<void> _pumpLive() async {
    if (_liveRunning) return;
    _liveRunning = true;
    var misses = 0;
    try {
      while (_liveUsers > 0 && ready) {
        Uint8List? jpg;
        try {
          jpg = await liveFrame();
        } catch (_) {}
        if (jpg != null) {
          misses = 0;
          frame.value = jpg;
        } else if (++misses >= 10) {
          // The screen falls back to the iPad camera; keep trying a little slower.
          frame.value = null;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    } finally {
      _liveRunning = false;
      if (_liveUsers == 0) frame.value = null;
    }
  }

  static String _hex(int v) => v.toRadixString(16).padLeft(4, '0');

  static String _explain(Object e) => switch (e) {
    PtpError(code: Ptp.sdioConnect) || PtpError(code: Ptp.sdioGetExtDeviceInfo) =>
      'Máy ảnh không vào chế độ điều khiển. Trên máy: Cài đặt → Kết nối USB → PC Remote',
    TimeoutException() => '$e',
    _ => 'Lỗi máy ảnh: $e',
  };
}

/// A PTP command the camera answered with something other than OK.
class PtpError implements Exception {
  const PtpError(this.code, this.response);
  final int code;
  final int response;

  @override
  String toString() => 'lệnh 0x${code.toRadixString(16)} → 0x${response.toRadixString(16)}';
}

int _u32(Uint8List d, int o) => d[o] | d[o + 1] << 8 | d[o + 2] << 16 | d[o + 3] << 24;

/// The JPEG inside [data] (live view frames carry a header before it), or null.
Uint8List? extractJpeg(Uint8List data) {
  var start = -1;
  for (var i = 0; i + 2 < data.length; i++) {
    if (data[i] == 0xFF && data[i + 1] == 0xD8 && data[i + 2] == 0xFF) {
      start = i;
      break;
    }
  }
  if (start < 0) return null;
  var end = data.length;
  for (var i = data.length - 2; i > start; i--) {
    if (data[i] == 0xFF && data[i + 1] == 0xD9) {
      end = i + 2;
      break;
    }
  }
  return Uint8List.sublistView(data, start, end);
}

/// Current values of the numeric properties in a Sony "GetAllExtDevicePropInfo" (0x9209) data
/// phase (libgphoto2 ptp_unpack_Sony_DPD). Newer bodies send a second enumeration list after
/// the first; tried when the plain layout does not parse.
Map<int, int> parseSonyProps(Uint8List data) {
  try {
    return _parseProps(data, twoLists: false);
  } on Object {
    return _parseProps(data, twoLists: true);
  }
}

const _types = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 0xFFFF};

Map<int, int> _parseProps(Uint8List data, {required bool twoLists}) {
  final r = PtpReader(data);
  final count = r.u32();
  r.skip(4); // 64-bit count
  if (count > 2000) throw const FormatException('too many properties');
  final out = <int, int>{};
  for (var i = 0; i < count; i++) {
    final code = r.u16();
    final type = r.u16();
    if (!_types.contains(type & ~0x4000) && type != 0xFFFF) {
      throw FormatException('type 0x${type.toRadixString(16)}');
    }
    r.skip(2); // get/set, enabled
    _value(r, type); // factory default
    final current = _value(r, type);
    final form = r.u8();
    switch (form) {
      case 0:
        break;
      case 1:
        for (var k = 0; k < 3; k++) {
          _value(r, type);
        }
      case 2:
        for (var list = 0; list < (twoLists ? 2 : 1); list++) {
          final n = r.u16();
          for (var k = 0; k < n; k++) {
            _value(r, type);
          }
        }
      default:
        throw FormatException('form $form');
    }
    if (current != null) out[code] = current;
  }
  return out;
}

int? _value(PtpReader r, int type) {
  if (type == 0xFFFF) {
    r.skip(r.u8() * 2);
    return null;
  }
  if (type & 0x4000 != 0) {
    final n = r.u32();
    r.skip(n * _size(type & ~0x4000));
    return null;
  }
  final size = _size(type);
  if (size == 16) {
    r.skip(16);
    return null;
  }
  return r.s(size, signed: type.isOdd);
}

int _size(int type) => switch (type) {
  1 || 2 => 1,
  3 || 4 => 2,
  5 || 6 => 4,
  7 || 8 => 8,
  9 || 10 => 16,
  _ => throw FormatException('type 0x${type.toRadixString(16)}'),
};
