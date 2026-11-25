import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/camera/ptp.dart';
import 'package:photobooth/camera/sony_camera.dart';

/// Little-endian builder for fake PTP data phases.
class _B {
  final b = BytesBuilder();
  void u8(int v) => b.addByte(v & 0xFF);
  void u16(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(int v) => b.add([for (var i = 0; i < 4; i++) (v >> (8 * i)) & 0xFF]);
  Uint8List get bytes => b.toBytes();
}

/// One property in Sony's 0x9209 layout: code, type, get/set, enabled, default, current, form.
void _prop(_B b, int code, int value, {int form = 0, bool twoLists = false}) {
  b
    ..u16(code)
    ..u16(4) // UINT16
    ..u8(1)
    ..u8(1)
    ..u16(0)
    ..u16(value)
    ..u8(form);
  if (form == 1) {
    b
      ..u16(0)
      ..u16(100)
      ..u16(1);
  } else if (form == 2) {
    b
      ..u16(2)
      ..u16(1)
      ..u16(2);
    if (twoLists) {
      b
        ..u16(1)
        ..u16(1);
    }
  }
}

final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 0xFF, 0xD9]);

/// A Sony body in PC Remote: the shutter puts a picture in its buffer after [shotDelay] polls.
class FakeSony implements PtpTransport {
  final ctrl = StreamController<PtpDeviceEvent>.broadcast(sync: true);
  final calls = <String>[];
  final presses = <(int, int)>[];
  int inMemory = 0;
  int shotDelay = 2;
  int _pending = -1;
  bool refuseConnect = false;
  bool neverDelivers = false;
  bool twoLists = false;
  int liveFrames = 0;

  @override
  Stream<PtpDeviceEvent> get events => ctrl.stream;

  @override
  Future<String> start() async => 'ok';

  @override
  Future<void> reopen() async {}

  Uint8List _props() {
    final b = _B()
      ..u32(3)
      ..u32(0);
    _prop(b, 0x5007, 40, form: 1); // aperture-like, range
    _prop(b, 0xD20D, 1, form: 2, twoLists: twoLists); // an enumeration
    _prop(b, Ptp.propObjectInMemory, inMemory == 0 ? 0 : 0x8000 + inMemory);
    return b.bytes;
  }

  @override
  Future<PtpResponse> send(int code, [List<int> params = const [], Uint8List? out]) async {
    await Future<void>.delayed(Duration.zero);
    switch (code) {
      case Ptp.sdioConnect:
        calls.add('connect ${params.first}');
        return PtpResponse(refuseConnect ? 0x2005 : Ptp.ok, data: Uint8List(8));
      case Ptp.sdioGetExtDeviceInfo:
        calls.add('extinfo');
        return PtpResponse(Ptp.ok, data: (_B()..u16(0xC8)).bytes);
      case Ptp.sdioGetAllExtDevicePropInfo:
        if (_pending >= 0 && --_pending < 0 && !neverDelivers) inMemory++;
        return PtpResponse(Ptp.ok, data: _props());
      case Ptp.sdioSetControlDeviceB:
        final v = out![0] | out[1] << 8;
        presses.add((params.first, v));
        if (params.first == Ptp.propCapture && v == 2) _pending = shotDelay;
        return PtpResponse(Ptp.ok);
      case Ptp.getObjectInfo:
        return PtpResponse(inMemory > 0 ? Ptp.ok : 0x2009, data: Uint8List(52));
      case Ptp.getObject when params.first == Ptp.capturedObject:
        if (inMemory == 0) return PtpResponse(0x2009);
        inMemory--;
        return PtpResponse(Ptp.ok, data: _jpeg);
      case Ptp.getObject when params.first == Ptp.liveViewObject:
        liveFrames++;
        return PtpResponse(Ptp.ok, data: Uint8List.fromList([0, 0, 0, 8, 9, 9, 9, 9, ..._jpeg, 0, 0]));
    }
    return PtpResponse(0x2005);
  }
}

Future<SonyCamera> _ready(FakeSony fake) async {
  final cam = SonyCamera(fake, pollEvery: Duration.zero);
  await cam.start();
  fake.ctrl.add(const PtpAdded('ILCE-6300', Ptp.sonyVendorId, 0x0994));
  fake.ctrl.add(const PtpOpened(null));
  await _until(() => cam.state != SonyState.connecting);
  return cam;
}

Future<void> _until(bool Function() ok) async {
  for (var i = 0; i < 500 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  test('handshake: SDIO connect 1, 2, ext info, 3, then ready', () async {
    final fake = FakeSony();
    final cam = await _ready(fake);
    expect(cam.state, SonyState.ready);
    expect(cam.name, 'ILCE-6300');
    expect(cam.protocol, 0xC8);
    expect(fake.calls, ['connect 1', 'connect 2', 'extinfo', 'connect 3']);
  });

  test('a session already open when the app starts: handshake straight away', () async {
    final fake = FakeSony();
    final cam = SonyCamera(fake, pollEvery: Duration.zero);
    await cam.start();
    fake.ctrl.add(const PtpAdded('ILCE-6300', Ptp.sonyVendorId, 0x0994, open: true));
    await _until(() => cam.ready);
    expect(cam.ready, isTrue);
  });

  test('capture: half press, full press, release; waits for the buffer, returns the JPEG', () async {
    final fake = FakeSony()..shotDelay = 3;
    final cam = await _ready(fake);
    final jpeg = await cam.capture();
    expect(jpeg, _jpeg);
    expect(fake.presses, [
      (Ptp.propAutoFocus, 2),
      (Ptp.propCapture, 2),
      (Ptp.propCapture, 1),
      (Ptp.propAutoFocus, 1),
    ]);
    expect(fake.inMemory, 0, reason: 'downloaded out of the buffer');
  });

  test('an old picture left in the buffer is dropped before the shot', () async {
    final fake = FakeSony()..inMemory = 1;
    final cam = await _ready(fake);
    expect(await cam.capture(), _jpeg);
    expect(fake.inMemory, 0);
    expect(cam.history.any((l) => l.contains('dropped')), isTrue);
  });

  test('no picture in time: TimeoutException, camera stays usable', () async {
    final fake = FakeSony()..neverDelivers = true;
    final cam = await _ready(fake);
    await expectLater(cam.capture(timeout: const Duration(milliseconds: 50)), throwsA(isA<TimeoutException>()));
    expect(cam.ready, isTrue);
    fake.neverDelivers = false;
    expect(await cam.capture(), _jpeg);
  });

  test('cable pulled mid-shot: error state, then absent', () async {
    final fake = _Unplugged();
    final cam = await _ready(fake);
    await expectLater(cam.capture(), throwsA(isA<PlatformException>()));
    expect(cam.state, SonyState.error);
    fake.ctrl.add(const PtpRemoved());
    expect(cam.state, SonyState.absent);
    expect(cam.name, isNull);
  });

  test('camera not in PC Remote (SDIO refused): explains what to set', () async {
    final cam = await _ready(FakeSony()..refuseConnect = true);
    expect(cam.state, SonyState.error);
    expect(cam.error, contains('PC Remote'));
    await expectLater(cam.capture(), throwsA(isA<StateError>()));
  });

  test('a camera that is not a Sony is refused', () async {
    final fake = FakeSony();
    final cam = SonyCamera(fake);
    await cam.start();
    fake.ctrl.add(const PtpAdded('Canon EOS', 0x04A9, 1));
    fake.ctrl.add(const PtpOpened(null));
    await _until(() => false);
    expect(cam.state, SonyState.error);
    expect(cam.error, contains('Không phải'));
    expect(fake.calls, isEmpty);
  });

  test('live view: frames while watched (header stripped), none after; a shot waits its turn', () async {
    final fake = FakeSony();
    final cam = await _ready(fake);
    final stop = cam.watchLive();
    await _until(() => cam.frame.value != null);
    expect(cam.frame.value, _jpeg);
    expect(await cam.capture(), _jpeg);
    stop();
    await _until(() => cam.frame.value == null);
    final n = fake.liveFrames;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(fake.liveFrames, n);
  });

  group('parsing', () {
    test('extractJpeg skips headers and trailing bytes; null without a JPEG', () {
      expect(extractJpeg(Uint8List.fromList([1, 2, ..._jpeg, 7, 7])), _jpeg);
      expect(extractJpeg(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('Sony properties: range, enumeration, strings, arrays; second enum list on newer bodies', () {
      for (final two in [false, true]) {
        final b = _B()
          ..u32(4)
          ..u32(0);
        _prop(b, 0x5007, 40, form: 1);
        _prop(b, 0xD20D, 1, form: 2, twoLists: two);
        // a string property: factory "", current "A"
        b
          ..u16(0xD2FF)
          ..u16(0xFFFF)
          ..u8(0)
          ..u8(1)
          ..u8(0)
          ..u8(2)
          ..u16(0x41)
          ..u16(0)
          ..u8(0);
        _prop(b, Ptp.propObjectInMemory, 0x8001);
        final props = parseSonyProps(b.bytes);
        expect(props[0x5007], 40);
        expect(props[0xD20D], 1);
        expect(props.containsKey(0xD2FF), isFalse);
        expect(props[Ptp.propObjectInMemory], 0x8001, reason: 'twoLists=$two');
      }
    });
  });
}

class _Unplugged extends FakeSony {
  @override
  Future<PtpResponse> send(int code, [List<int> params = const [], Uint8List? out]) {
    if (code == Ptp.sdioSetControlDeviceB) throw PlatformException(code: 'closed', message: 'Chưa kết nối máy ảnh');
    return super.send(code, params, out);
  }
}
