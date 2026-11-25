import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// A PTP response: its code (0x2001 = OK), parameters and the data phase that came back.
class PtpResponse {
  PtpResponse(this.code, {this.params = const [], Uint8List? data}) : data = data ?? Uint8List(0);

  final int code;
  final List<int> params;
  final Uint8List data;

  bool get ok => code == Ptp.ok;

  @override
  String toString() => 'PTP 0x${code.toRadixString(16)} (${data.length} B)';
}

/// What the USB side reports.
sealed class PtpDeviceEvent {
  const PtpDeviceEvent();
}

/// A camera was plugged in (or was there when the app started).
class PtpAdded extends PtpDeviceEvent {
  const PtpAdded(this.name, this.vendorId, this.productId, {this.open = false});
  final String name;
  final int vendorId;
  final int productId;

  /// The session is open already.
  final bool open;
}

/// The PTP session opened ([error] null) or could not.
class PtpOpened extends PtpDeviceEvent {
  const PtpOpened(this.error);
  final String? error;
}

class PtpRemoved extends PtpDeviceEvent {
  const PtpRemoved();
}

/// An event packet from the camera.
class PtpEvent extends PtpDeviceEvent {
  const PtpEvent(this.code, this.params);
  final int code;
  final List<int> params;
}

/// Sends PTP commands to the camera on the USB-C port.
abstract class PtpTransport {
  Stream<PtpDeviceEvent> get events;

  /// Starts looking for cameras (asks the iPad's permission once).
  Future<String> start();

  /// One PTP transaction. [out]: data sent to the camera (the command has a data-out phase).
  Future<PtpResponse> send(int code, [List<int> params = const [], Uint8List? out]);

  /// Closes and opens the session again (after a camera that stopped answering).
  Future<void> reopen();
}

/// The native side: ios/Runner/AppDelegate.swift (BoothPtp, ImageCaptureCore).
class ChannelPtpTransport implements PtpTransport {
  static const _ch = MethodChannel('booth/ptp');
  static const _ev = EventChannel('booth/ptp/events');

  @override
  late final Stream<PtpDeviceEvent> events = _ev.receiveBroadcastStream().map((e) {
    final m = (e as Map).cast<String, Object?>();
    return switch (m['event']) {
      'added' => PtpAdded(
        m['name'] as String? ?? '',
        (m['vendor'] as num?)?.toInt() ?? 0,
        (m['product'] as num?)?.toInt() ?? 0,
        open: m['open'] == true,
      ),
      'opened' => PtpOpened(m['error'] as String?),
      'event' => PtpEvent((m['code'] as num?)?.toInt() ?? 0, [
        for (final p in (m['params'] as List?) ?? const []) (p as num).toInt(),
      ]),
      _ => const PtpRemoved(),
    };
  });

  @override
  Future<String> start() async => await _ch.invokeMethod<String>('start') ?? '';

  @override
  Future<PtpResponse> send(int code, [List<int> params = const [], Uint8List? out]) async {
    final r = await _ch.invokeMapMethod<String, Object?>('send', {'code': code, 'params': params, 'out': out});
    return PtpResponse(
      (r?['code'] as num?)?.toInt() ?? 0,
      params: [for (final p in (r?['params'] as List?) ?? const []) (p as num).toInt()],
      data: r?['data'] as Uint8List?,
    );
  }

  @override
  Future<void> reopen() => _ch.invokeMethod<bool>('reopen');
}

/// PTP and Sony "PC Remote" (SDIO) codes, as in libgphoto2's ptp.h.
abstract final class Ptp {
  static const ok = 0x2001;
  static const getObjectInfo = 0x1008;
  static const getObject = 0x1009;

  static const sonyVendorId = 0x054C;
  static const sdioConnect = 0x9201;
  static const sdioGetExtDeviceInfo = 0x9202;
  static const sdioSetControlDeviceB = 0x9207;
  static const sdioGetAllExtDevicePropInfo = 0x9209;

  /// Half press (1 = up, 2 = down).
  static const propAutoFocus = 0xD2C1;

  /// Full press (1 = up, 2 = down).
  static const propCapture = 0xD2C2;

  /// Pictures waiting in the camera's buffer: 0x8000 + n.
  static const propObjectInMemory = 0xD215;

  /// The last picture taken, and the live view frame.
  static const capturedObject = 0xFFFFC001;
  static const liveViewObject = 0xFFFFC002;
}

/// Little-endian reader over a PTP data phase.
class PtpReader {
  PtpReader(Uint8List bytes) : _d = ByteData.sublistView(bytes);
  final ByteData _d;
  int pos = 0;

  int get remaining => _d.lengthInBytes - pos;

  int u8() => _d.getUint8(pos++);
  int u16() {
    final v = _d.getUint16(pos, Endian.little);
    pos += 2;
    return v;
  }

  int u32() {
    final v = _d.getUint32(pos, Endian.little);
    pos += 4;
    return v;
  }

  int s(int size, {required bool signed}) {
    final v = switch (size) {
      1 => signed ? _d.getInt8(pos) : _d.getUint8(pos),
      2 => signed ? _d.getInt16(pos, Endian.little) : _d.getUint16(pos, Endian.little),
      4 => signed ? _d.getInt32(pos, Endian.little) : _d.getUint32(pos, Endian.little),
      _ => _d.getInt64(pos, Endian.little),
    };
    pos += size;
    return v;
  }

  void skip(int n) {
    if (n < 0 || n > remaining) throw const FormatException('PTP data too short');
    pos += n;
  }
}
