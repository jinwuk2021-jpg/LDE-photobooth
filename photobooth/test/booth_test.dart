import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photobooth/booth/booth.dart';
import 'package:photobooth/booth/frames.dart';
import 'package:photobooth/booth/print_layout.dart';
import 'package:photobooth/camera/photobooth_sequence.dart';
import 'package:photobooth/services/upload_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('6 shots: 5 s before the first, 3 s before each next', () {
    fakeAsync((async) {
      final ticks = <(int, int)>[];
      final taken = <int>[];
      var shot = 0;
      final seq = PhotoboothSequence(
        capture: (i) async => taken.add(i),
        onChange: (s) => shot = s.shotIndex,
        onTick: (n) => ticks.add((shot, n)),
      );
      seq.start();
      async.elapse(const Duration(seconds: 4));
      expect(taken, isEmpty);
      async.elapse(const Duration(seconds: 1));
      expect(taken, [0]);
      async.elapse(const Duration(seconds: 3 * 5));
      expect(taken, [0, 1, 2, 3, 4, 5]);
      expect(seq.state.phase, BoothPhase.finished);
      expect(ticks.where((t) => t.$1 == 0).map((t) => t.$2), [5, 4, 3, 2, 1]);
      expect(ticks.where((t) => t.$1 == 1).map((t) => t.$2), [3, 2, 1]);
    });
  });

  late FrameStore store;
  late List<BoothFrame> frames;
  BoothFrame byId(String id) => store.byId(id)!;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = FrameStore(await SharedPreferences.getInstance());
    await store.load();
    frames = store.all;
  });

  test('picks keep tap order, as many as the frame has, tap again to remove', () {
    final g = GuestSession(byId('lpe_4cut_black'));
    for (final i in [5, 0, 3, 2, 1]) {
      g.toggle(i);
    }
    expect(g.picks, [5, 0, 3, 2]);
    expect(g.complete, isTrue);
    g.toggle(0);
    expect(g.picks, [5, 3, 2]);
    expect(g.complete, isFalse);
    final two = GuestSession(byId('lpe_2cut_ivory'));
    for (final i in [4, 1, 3]) {
      two.toggle(i);
    }
    expect(two.picks, [4, 1]);
  });

  test('2 spare shots: the windows + 2', () {
    expect({for (final f in frames) f.label: f.shots}, {'2 Cut': 4, '3 Cut': 5, '4 Cut': 6, '6 Cut': 8});
  });

  test('layout.json: one window per photo, fractions of the card', () {
    for (final frame in frames) {
      final j = layoutJson(frame);
      final rects = j['rects']! as List;
      expect(rects, hasLength(frame.picks));
      for (final r in rects.cast<List<double>>()) {
        expect(r.every((v) => v >= 0 && v <= 1), isTrue);
        expect(r[0] + r[2] <= 1 && r[1] + r[3] <= 1, isTrue);
      }
      expect(j['aspect'], closeTo(frame.size.aspectRatio, 0.001));
    }
  });

  test('session ids are valid Worker ids', () {
    final id = Booth.newSessionId();
    expect(id, matches(RegExp(r'^[abcdefghjkmnpqrstuvwxyz23456789]{12}$')));
  });

  group('frames', () {
    test('8 built-ins, ivory and black of each cut; the 4 of before are on by default', () {
      expect(frames.map((f) => f.id), builtInFrameIds);
      expect({for (final f in frames) '${f.picks}${f.paper.name}'}, hasLength(8));
      expect(store.enabled.map((f) => f.id), ['lpe_2cut_ivory', 'lpe_3cut_ivory', 'lpe_4cut_black', 'lpe_6cut_ivory']);
      expect(frames.where((f) => f.landscape).map((f) => f.picks).toSet(), {4});
    });

    test('frame.json round-trips', () {
      for (final f in frames) {
        final again = BoothFrame.fromJson(
          jsonDecode(jsonEncode(f.toJson(enabled: f.enabledByDefault))) as Map<String, dynamic>,
        );
        expect(again.toJson(enabled: again.enabledByDefault), f.toJson(enabled: f.enabledByDefault));
      }
    });

    test('show / hide, remembered, the last one stays on', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(await store.setEnabled(byId('lpe_2cut_black'), true), isTrue);
      for (final id in ['lpe_2cut_ivory', 'lpe_3cut_ivory', 'lpe_4cut_black', 'lpe_6cut_ivory']) {
        expect(await store.setEnabled(byId(id), false), isTrue);
      }
      expect(store.enabled.map((f) => f.id), ['lpe_2cut_black']);
      expect(await store.setEnabled(byId('lpe_2cut_black'), false), isFalse);
      expect(store.enabled.map((f) => f.id), ['lpe_2cut_black']);
      final again = FrameStore(prefs);
      await again.load();
      expect(again.enabled.map((f) => f.id), ['lpe_2cut_black']);
    });

    test('custom frames load from Documents/frames with their PNG', () async {
      final docs = Directory.systemTemp.createTempSync('frames');
      addTearDown(() => docs.deleteSync(recursive: true));
      final dir = Directory('${docs.path}/frames/my_frame')..createSync(recursive: true);
      final png = await _holePng(const Size(1200, 1776), [const Rect.fromLTWH(100, 100, 1000, 700)]);
      File('${dir.path}/frame.png').writeAsBytesSync(png);
      File('${dir.path}/frame.json').writeAsStringSync(
        jsonEncode({
          'id': 'my_frame',
          'name': 'Khung công ty',
          'orientation': 'portrait',
          'size': [1200, 1776],
          'slots': [
            {'x': 100, 'y': 100, 'w': 1000, 'h': 700},
          ],
          'qr': {'x': 948, 'y': 1544, 'size': 180},
          'enabled': true,
          'builtIn': false,
        }),
      );
      Directory('${docs.path}/frames/broken').createSync();
      final s = FrameStore(await SharedPreferences.getInstance(), docs: docs);
      await s.load();
      final mine = s.byId('my_frame')!;
      expect(mine.builtIn, isFalse);
      expect(mine.label, 'Khung công ty');
      expect((mine.overlay!.width, mine.overlay!.height), (1200, 1776));
      expect(s.all, hasLength(9));
    });
  });

  group('print layout', () {
    // The handoff's frame.json geometry (= the design's coordinates).
    const want = {
      2: [Rect.fromLTWH(72, 72, 1056, 704), Rect.fromLTWH(72, 800, 1056, 704)],
      3: [Rect.fromLTWH(300, 87, 828, 518), Rect.fromLTWH(300, 629, 828, 518), Rect.fromLTWH(300, 1171, 828, 518)],
      4: [
        Rect.fromLTWH(116, 56, 760, 428),
        Rect.fromLTWH(900, 56, 760, 428),
        Rect.fromLTWH(116, 508, 760, 428),
        Rect.fromLTWH(900, 508, 760, 428),
      ],
      6: [
        Rect.fromLTWH(72, 72, 516, 459),
        Rect.fromLTWH(612, 72, 516, 459),
        Rect.fromLTWH(72, 555, 516, 459),
        Rect.fromLTWH(612, 555, 516, 459),
        Rect.fromLTWH(72, 1038, 516, 459),
        Rect.fromLTWH(612, 1038, 516, 459),
      ],
    };

    for (final id in builtInFrameIds) {
      test('$id: windows, title and QR fit the card and never overlap', () {
        final frame = byId(id);
        final card = Offset.zero & frame.size;
        expect(frame.slots, want[frame.picks]);
        final decor = builtInDecor(frame);
        // 3 Cut's title is turned inside its band; the others sit under the photos.
        final boxes = [...frame.slots, frame.qr, if (decor.band == null) decor.title];
        for (final r in boxes) {
          expect(card.contains(r.topLeft) && card.contains(r.bottomRight - const Offset(1, 1)), isTrue, reason: '$r');
        }
        for (var i = 0; i < boxes.length; i++) {
          for (var j = i + 1; j < boxes.length; j++) {
            final x = boxes[i].intersect(boxes[j]);
            expect(x.width <= 0 || x.height <= 0, isTrue, reason: '${boxes[i]} × ${boxes[j]}');
          }
        }
        // QR: 180 px (15 mm), at least 40 px (3.3 mm) from every edge.
        expect((frame.qr.width, frame.qr.height), (180.0, 180.0));
        expect(
          frame.qr.left >= 40 &&
              frame.qr.top >= 40 &&
              card.right - frame.qr.right >= 40 &&
              card.bottom - frame.qr.bottom >= 40,
          isTrue,
          reason: '${frame.qr}',
        );
        // Each card holds the same postcard, landscape or not.
        expect({frame.size.width, frame.size.height}, {1200.0, 1776.0});
      });
    }

    test('print colours: richer = more saturated and contrasty, greys stay grey, black stays black', () {
      List<double> apply(List<double> m, List<double> rgb) => [
        for (var r = 0; r < 3; r++)
          (m[r * 5] * rgb[0] + m[r * 5 + 1] * rgb[1] + m[r * 5 + 2] * rgb[2] + m[r * 5 + 4]).clamp(0, 255).toDouble(),
      ];
      for (final c in PrintColor.values) {
        final m = printMatrix(saturation: c.saturation, contrast: c.contrast);
        final grey = apply(m, [128, 128, 128]);
        for (final v in grey) {
          expect(v, closeTo(128, 0.01), reason: c.name);
        }
        expect(apply(m, [0, 0, 0]), everyElement(0.0), reason: c.name);
      }
      // A muted skin tone: further from grey and with a wider light / dark spread as the level rises.
      double spread(PrintColor c) {
        final m = printMatrix(saturation: c.saturation, contrast: c.contrast);
        final o = apply(m, [200, 150, 130]);
        return o[0] - o[2];
      }

      final spreads = PrintColor.values.map(spread).toList();
      for (var i = 1; i < spreads.length; i++) {
        expect(spreads[i], greaterThan(spreads[i - 1]));
      }
      expect(PrintColor.byName(null), PrintColor.rich);
      // Brightness is a gain: black stays black.
      expect(apply(printMatrix(brighten: 0.1), [0, 0, 0]), everyElement(0.0));
      expect(apply(printMatrix(brighten: 0.1), [100, 100, 100]).first, closeTo(110, 0.01));
    });

    test('cover crop: fills the window, centred across, biased 10 % up', () {
      // A 3:2 photo into a square: the sides go.
      expect(coverSource(const Size(300, 200), const Size(100, 100)), const Rect.fromLTWH(50, 0, 200, 200));
      // A tall photo into a wide window: 40 % of the spare height above, 60 % below.
      final r = coverSource(const Size(200, 400), const Size(200, 100));
      expect(r, const Rect.fromLTWH(0, 120, 200, 100));
    });

    test('printer copy: always portrait (either turn), brightened when asked', () async {
      final landscape = await _solid(40, 20, const Color(0xFF808080));
      for (final ccw in [false, true]) {
        final out = await forPrinter(landscape, counterClockwise: ccw);
        expect((out.width, out.height), (20, 40));
      }
      final portrait = await _solid(20, 40, const Color(0xFF808080));
      final same = await forPrinter(portrait);
      expect((same.width, same.height), (20, 40));
      Future<int> red(ui.Image img) async => (await img.toByteData())!.getUint8(0);
      final lifted = await forPrinter(portrait, brighten: 0.1);
      expect(await red(lifted), greaterThan(await red(same)));
      final darker = await forPrinter(portrait, brighten: -0.1);
      expect(await red(darker), lessThan(await red(same)));
    });

    test('renders every frame with photos in the windows; landscape is turned portrait for the printer', () async {
      final out = Platform.environment['PRINT_OUT'];
      final red = await _solid(600, 400, const Color(0xFFFF0000));
      for (final frame in frames) {
        final img = await renderPrint(
          PrintSpec(
            frame: frame,
            photos: List.filled(frame.picks, red),
            title: 'LPE Sum Up',
            dateLine: '23.11.2026',
            qrUrl: 'https://lenslycam.com/lde/b/abcdefghjkmn',
          ),
        );
        expect((img.width, img.height), (frame.size.width.round(), frame.size.height.round()));
        for (final s in frame.slots) {
          expect(await _pixel(img, s.center), 0xFFFF0000, reason: '${frame.id} $s');
        }
        // QR: white quiet zone in the corner of its square.
        expect(await _pixel(img, frame.qr.topLeft + const Offset(3, 3)), 0xFFFFFFFF, reason: frame.id);
        final printed = frame.landscape ? await forPrinter(img) : img;
        expect((printed.width, printed.height), (1200, 1776));
        if (out != null) {
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$out/print_${frame.id}.png').writeAsBytesSync(png!.buffer.asUint8List());
        }
      }
    });

    test('Bo góc: the photo windows get rounded corners, the middle stays the photo', () async {
      final red = await _solid(40, 30, const Color(0xFFFF0000));
      final frame = frames.firstWhere((f) => f.id == 'lpe_4cut_black');
      final img = await renderPrint(
        PrintSpec(
          frame: frame,
          photos: List.filled(frame.picks, red),
          title: 'LPE Sum Up',
          dateLine: '23.11.2026',
          photoRadius: 60,
        ),
      );
      for (final s in frame.slots) {
        expect(await _pixel(img, s.center), 0xFFFF0000);
        expect(await _pixel(img, s.topLeft + const Offset(4, 4)), isNot(0xFFFF0000), reason: 'rounded corner $s');
        expect(await _pixel(img, s.topCenter + const Offset(0, 4)), 0xFFFF0000, reason: 'straight edge $s');
      }
    });

    test('custom frame: photo shows through the hole only, the PNG covers the rest', () async {
      const size = Size(1200, 1776);
      const hole = Rect.fromLTWH(100, 100, 1000, 700);
      final overlay = await decodePng(await _holePng(size, [hole]));
      final frame = BoothFrame(
        id: 'x',
        name: 'x',
        size: size,
        slots: const [hole],
        qr: const Rect.fromLTWH(948, 1544, 180, 180),
        overlay: overlay,
      );
      final img = await renderPrint(
        PrintSpec(frame: frame, photos: [await _solid(300, 200, const Color(0xFFFF0000))], title: '', dateLine: ''),
      );
      expect(await _pixel(img, hole.center), 0xFFFF0000);
      expect(await _pixel(img, hole.topLeft + const Offset(1, 1)), 0xFFFF0000);
      expect(await _pixel(img, hole.topLeft - const Offset(1, 1)), _near(0xFF2040A0));
      expect(await _pixel(img, const Offset(600, 1200)), _near(0xFF2040A0));
    });
  });

  group('upload queue', () {
    late Directory docs;
    setUp(() => docs = Directory.systemTemp.createTempSync('booth'));
    tearDown(() => docs.deleteSync(recursive: true));

    File file(String name) => File('${docs.path}/$name')..writeAsBytesSync([1, 2, 3]);
    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

    test('print first, then photos, then clips; survives a relaunch', () async {
      final state = File('${docs.path}/state.json');
      final t = DateTime(2026);
      // Saved by an earlier run, clips first on purpose.
      state.writeAsStringSync(
        jsonEncode([
          for (final n in ['1.mp4', '1.jpg', 'print.jpg', '2.jpg'])
            UploadItem(
              session: 'abcdefghjkmn',
              name: n,
              path: file(n).path.split('/').last,
              title: 'T',
              created: t,
            ).toJson(),
        ]),
      );
      final sent = <String>[];
      final q = UploadQueue(
        docs: docs,
        stateFile: state,
        key: 'k',
        client: MockClient((r) async {
          sent.add(r.url.pathSegments.last);
          return http.Response('{}', 201);
        }),
      )..load();
      await settle();
      expect(sent, ['print.jpg', '1.jpg', '2.jpg', '1.mp4']);
      expect(q.items, isEmpty);
      expect(jsonDecode(state.readAsStringSync()), isEmpty);
    });

    test('a failure is retried later, "Thử lại tất cả" sends it now', () async {
      var fail = true;
      final q = UploadQueue(
        docs: docs,
        stateFile: File('${docs.path}/state.json'),
        key: 'k',
        client: MockClient((r) async => fail ? http.Response('', 500) : http.Response('{}', 201)),
      );
      q.add('abcdefghjkmn', 'print.jpg', file('print.jpg').path, 'T');
      await settle();
      expect(q.items.single.attempts, 1);
      expect(q.items.single.nextAt.difference(DateTime.now()).inSeconds, inInclusiveRange(3, 5));
      expect(q.pendingSessions, 1);
      expect(q.failingSessions, 1);
      fail = false;
      q.retryAll();
      await settle();
      expect(q.items, isEmpty);
    });

    test('clips leave the iPad once online, only when asked (start screen), also after a relaunch', () async {
      final state = File('${docs.path}/state.json');
      var fail = true;
      UploadQueue queue() => UploadQueue(
        docs: docs,
        stateFile: state,
        key: 'k',
        client: MockClient((r) async => fail && r.url.path.endsWith('2.mp4') ? http.Response('', 500) : http.Response('{}', 201)),
      );
      final q = queue();
      for (final n in ['print.jpg', '1.jpg', '1.mp4', '2.mp4']) {
        q.add('abcdefghjkmn', n, file(n).path, 'T');
      }
      await settle();
      expect(q.items.map((i) => i.name), ['2.mp4'], reason: '2.mp4 failed once');
      // Online, but the guest may still be on the QR screen: nothing deleted yet.
      expect(File('${docs.path}/1.mp4').existsSync(), isTrue);

      // Start screen: only the clip that is online goes; photos and print stay for "In lại".
      expect(q.deleteUploadedClips(), 1);
      expect(File('${docs.path}/1.mp4').existsSync(), isFalse);
      expect(File('${docs.path}/2.mp4').existsSync(), isTrue);
      expect(File('${docs.path}/1.jpg').existsSync(), isTrue);
      expect(File('${docs.path}/print.jpg').existsSync(), isTrue);

      // 2.mp4 goes up; the app is relaunched before the start screen: still deleted then.
      fail = false;
      q.retryAll();
      await settle();
      expect(q.items, isEmpty);
      final again = queue()..load();
      expect(again.deleteUploadedClips(), 1);
      expect(File('${docs.path}/2.mp4').existsSync(), isFalse);
      expect(again.deleteUploadedClips(), 0);
    });
  });
}

Future<ui.Image> _solid(int w, int h, Color c) {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = c);
  return rec.endRecording().toImage(w, h);
}

/// Within 2 per channel of [argb] (PNG colour round trips).
Matcher _near(int argb) => predicate<int>(
  (v) => [0, 8, 16, 24].every((s) => ((v >> s & 0xFF) - (argb >> s & 0xFF)).abs() <= 2),
  'near 0x${argb.toRadixString(16)}',
);

/// ARGB of [img] at [at].
Future<int> _pixel(ui.Image img, Offset at) async {
  final data = (await img.toByteData())!;
  final i = (at.dy.floor() * img.width + at.dx.floor()) * 4;
  return data.getUint8(i + 3) << 24 | data.getUint8(i) << 16 | data.getUint8(i + 1) << 8 | data.getUint8(i + 2);
}

/// A blue PNG of [size] with fully transparent [holes].
Future<Uint8List> _holePng(Size size, List<Rect> holes) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF2040A0));
  for (final h in holes) {
    c.drawRect(h, Paint()..blendMode = BlendMode.clear);
  }
  final img = await rec.endRecording().toImage(size.width.round(), size.height.round());
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}
