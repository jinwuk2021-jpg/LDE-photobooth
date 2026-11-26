// "In thêm 1 tấm" on the thank-you screen: one extra copy per tap up to the Settings limit,
// "Đang in thêm…" while it waits / prints, hidden when the limit is 0 or printing is off.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photobooth/booth/booth.dart';
import 'package:photobooth/booth/frames.dart';
import 'package:photobooth/camera/booth_camera.dart';
import 'package:photobooth/camera/ptp.dart';
import 'package:photobooth/screens/thanks_screen.dart';
import 'package:photobooth/services/printer.dart';
import 'package:photobooth/services/settings.dart';
import 'package:photobooth/services/upload_queue.dart';
import 'package:photobooth/ui/strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoCamera implements PtpTransport {
  @override
  Stream<PtpDeviceEvent> get events => const Stream.empty();
  @override
  Future<String> start() async => 'test';
  @override
  Future<PtpResponse> send(int code, [List<int> params = const [], Uint8List? out]) async => PtpResponse(0x2019);
  @override
  Future<void> reopen() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  late List<Completer<String?>> printing;

  Future<Booth> booth({int extraMax = 1}) async {
    docs = Directory.systemTemp.createTempSync('thanks');
    SharedPreferences.setMockInitialValues({
      'printerUrl': 'ipp://192.168.0.23/ipp/print',
      'printerName': 'SELPHY',
      'extraPrintMax': extraMax,
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = BoothSettings(prefs);
    printing = [];
    final prints = PrintQueue(
      prefs,
      settings,
      docs,
      reachable: (_) async => true,
      send: (_, _, _) {
        final c = Completer<String?>();
        printing.add(c);
        return c.future;
      },
    );
    return Booth(
      docs: docs,
      settings: settings,
      camera: BoothCamera(ptp: _NoCamera()),
      uploads: UploadQueue(docs: docs, stateFile: File(p.join(docs.path, 'q.json')), key: ''),
      prints: prints,
      frames: FrameStore(prefs, docs: docs),
    );
  }

  Finished finished({bool printing = true}) {
    final card = File(p.join(docs.path, 'print_may_in.jpg'))..writeAsBytesSync([1]);
    // A 1 × 1 PNG for the floating print.
    final shown = File(p.join(docs.path, 'print.png'))
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==',
        ),
      );
    return Finished(
      'https://lenslycam.com/lde/b/abcdefghjkmn',
      shown.path,
      1200 / 1776,
      printed: printing,
      printerCopy: printing ? card.path : null,
    );
  }

  Future<void> show(WidgetTester t, Booth b, Finished f) async {
    t.view.physicalSize = const Size(1194, 834);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThanksScreen(booth: b, finished: f, onDone: () {}),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 800));
  }

  testWidgets('one tap = one copy: printing… then done, disabled at the limit', (t) async {
    final b = await t.runAsync(() => booth(extraMax: 1));
    await show(t, b!, finished());
    expect(find.text(T.now.printOneMore), findsOneWidget);
    await t.tap(find.text(T.now.printOneMore));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
    expect(b.prints.jobs, hasLength(1));
    expect(find.text(T.now.printingMore), findsOneWidget);
    printing.single.complete(null);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
    expect(b.prints.jobs.single.status, JobStatus.done);
    expect(find.text(T.now.printedMore), findsOneWidget);
    await t.tap(find.text(T.now.printedMore));
    await t.pump();
    expect(b.prints.jobs, hasLength(1));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('limit 2: the button comes back once, then stays done', (t) async {
    final b = await t.runAsync(() => booth(extraMax: 2));
    await show(t, b!, finished());
    for (var i = 0; i < 2; i++) {
      await t.tap(find.text(T.now.printOneMore));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      printing.last.complete(null);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    expect(b.prints.jobs, hasLength(2));
    expect(find.text(T.now.printedMore), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('no button with the limit at 0 or printing off', (t) async {
    final b = await t.runAsync(() => booth(extraMax: 0));
    await show(t, b!, finished());
    expect(find.text(T.now.printOneMore), findsNothing);
    await t.pumpWidget(const SizedBox());
    final b2 = await t.runAsync(() => booth(extraMax: 3));
    await show(t, b2!, finished(printing: false));
    expect(find.text(T.now.printOneMore), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
