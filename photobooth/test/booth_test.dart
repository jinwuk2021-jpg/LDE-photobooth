import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photobooth/booth/booth.dart';
import 'package:photobooth/booth/print_layout.dart';
import 'package:photobooth/camera/photobooth_sequence.dart';
import 'package:photobooth/services/upload_queue.dart';

void main() {
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

  test('picks keep tap order, as many as the frame has, tap again to remove', () {
    final g = GuestSession(BoothLayout.cut4);
    for (final i in [5, 0, 3, 2, 1]) {
      g.toggle(i);
    }
    expect(g.picks, [5, 0, 3, 2]);
    expect(g.complete, isTrue);
    g.toggle(0);
    expect(g.picks, [5, 3, 2]);
    expect(g.complete, isFalse);
    final two = GuestSession(BoothLayout.cut2);
    for (final i in [4, 1, 3]) {
      two.toggle(i);
    }
    expect(two.picks, [4, 1]);
  });

  test('2 spare shots, at least 6', () {
    expect({for (final l in BoothLayout.values) l.label: l.shots}, {'2 Cut': 6, '3 Cut': 6, '4 Cut': 6, '6 Cut': 8});
  });

  test('layout.json: one window per photo, fractions of the card', () {
    for (final layout in BoothLayout.values) {
      final j = layoutJson(layout);
      final rects = j['rects']! as List;
      expect(rects, hasLength(layout.picks));
      for (final r in rects.cast<List<double>>()) {
        expect(r.every((v) => v >= 0 && v <= 1), isTrue);
        expect(r[0] + r[2] <= 1 && r[1] + r[3] <= 1, isTrue);
      }
      expect(j['aspect'], closeTo(layout.size.aspectRatio, 0.001));
    }
  });

  test('session ids are valid Worker ids', () {
    final id = Booth.newSessionId();
    expect(id, matches(RegExp(r'^[abcdefghjkmnpqrstuvwxyz23456789]{12}$')));
  });

  group('print layout', () {
    for (final layout in BoothLayout.values) {
      test('${layout.label}: windows, title and QR fit the card and never overlap', () {
        final card = Offset.zero & layout.size;
        final g = PrintGeometry.of(layout);
        expect(g.cells, hasLength(layout.picks));
        // 3 Cut's title is turned inside its band; the others sit under the photos.
        final boxes = [...g.cells, g.qr, if (g.band == null) g.title];
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
        expect((g.qr.width, g.qr.height), (180.0, 180.0));
        expect(g.qr.left >= 40 && g.qr.top >= 40 && card.right - g.qr.right >= 40 && card.bottom - g.qr.bottom >= 40, isTrue, reason: '${g.qr}');
        // Each card holds the same postcard, landscape or not.
        expect({layout.size.width, layout.size.height}, {1200.0, 1776.0});
      });
    }

    test('printer copy: always portrait (either turn), brightened when asked', () async {
      Future<ui.Image> solid(int w, int h, Color c) {
        final rec = ui.PictureRecorder();
        Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = c);
        return rec.endRecording().toImage(w, h);
      }

      final landscape = await solid(40, 20, const Color(0xFF808080));
      for (final ccw in [false, true]) {
        final out = await forPrinter(landscape, counterClockwise: ccw);
        expect((out.width, out.height), (20, 40));
      }
      final portrait = await solid(20, 40, const Color(0xFF808080));
      final same = await forPrinter(portrait);
      expect((same.width, same.height), (20, 40));
      Future<int> red(ui.Image img) async => (await img.toByteData())!.getUint8(0);
      final lifted = await forPrinter(portrait, brighten: 0.1);
      expect(await red(lifted), greaterThan(await red(same)));
    });

    test('renders every frame; 4 Cut is turned portrait for the printer', () async {
      final out = Platform.environment['PRINT_OUT'];
      for (final layout in BoothLayout.values) {
        final img = await renderPrint(
          PrintSpec(
            layout: layout,
            photos: const [],
            title: 'Tiệc cuối năm',
            dateLine: '23.11.2026',
            qrUrl: 'https://lenslycam.com/lde/b/abcdefghjkmn',
          ),
        );
        expect((img.width, img.height), (layout.size.width.round(), layout.size.height.round()));
        final printed = layout.landscape ? await forPrinter(img) : img;
        expect((printed.width, printed.height), (1200, 1776));
        if (out != null) {
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$out/print_${layout.name}.png').writeAsBytesSync(png!.buffer.asUint8List());
        }
      }
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
  });
}
