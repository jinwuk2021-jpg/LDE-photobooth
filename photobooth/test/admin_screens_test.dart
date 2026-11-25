// Every staff page builds at iPad size (1194 × 834) with real fonts and sample data, with no
// layout overflow. With ADMIN_SHOTS=<dir> it also writes each page as a PNG to compare with the
// design ("LPE Sum Up – Photobooth", 7 · Cài đặt).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:photobooth/booth/booth.dart';
import 'package:photobooth/booth/frames.dart';
import 'package:photobooth/booth/print_layout.dart';
import 'package:photobooth/camera/booth_camera.dart';
import 'package:photobooth/camera/ptp.dart';
import 'package:photobooth/screens/admin/kit.dart';
import 'package:photobooth/screens/admin_screen.dart';
import 'package:photobooth/services/printer.dart';
import 'package:photobooth/services/settings.dart';
import 'package:photobooth/services/upload_queue.dart';
import 'package:photobooth/ui/lux.dart';
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

Future<void> _loadIcons() async {
  final flutterRoot = p.dirname(p.dirname('${Platform.resolvedExecutable.split('/bin/cache/')[0]}/bin/x'));
  final f = File(p.join(flutterRoot, 'bin', 'cache', 'artifacts', 'material_fonts', 'MaterialIcons-Regular.otf'));
  if (!f.existsSync()) return;
  final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final out = Platform.environment['ADMIN_SHOTS'];

  var printerUp = true;

  Future<Booth> booth(WidgetTester t) async {
    final docs = Directory.systemTemp.createTempSync('admin');
    SharedPreferences.setMockInitialValues({
      'printerUrl': 'ipp://192.168.0.23/ipp/print',
      'printerName': 'Canon SELPHY CP1500',
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = BoothSettings(prefs);
    final frames = FrameStore(prefs, docs: docs);
    await frames.load();
    final prints = PrintQueue(prefs, settings, docs, reachable: (_) async => printerUp, send: (_, _, _) async => null);
    final b = Booth(
      docs: docs,
      settings: settings,
      camera: BoothCamera(ptp: _NoCamera()),
      uploads: UploadQueue(docs: docs, stateFile: File(p.join(docs.path, 'q.json')), key: ''),
      prints: prints,
      frames: frames,
    );
    // Six past guests, newest last.
    await t.runAsync(() async {
      for (var i = 0; i < 6; i++) {
        final f = frames.all[i % frames.all.length];
        final dir = Directory(p.join(docs.path, 'Booth', '2026-12-23', '21-${(20 + i * 5).toString().padLeft(2, '0')}-00'))
          ..createSync(recursive: true);
        final card = await renderPrint(
          PrintSpec(frame: f, photos: const [], title: 'LPE Sum Up', dateLine: '23.12.2026', qrUrl: b.linkFor('x$i')),
        );
        final png = await card.toByteData(format: ui.ImageByteFormat.png);
        File(p.join(dir.path, 'print.jpg')).writeAsBytesSync(png!.buffer.asUint8List());
        File(p.join(dir.path, 'print_may_in.jpg')).writeAsBytesSync(png.buffer.asUint8List());
        File(p.join(dir.path, 'layout.json')).writeAsStringSync(jsonEncode(layoutJson(f)));
        File(p.join(dir.path, 'link.txt')).writeAsStringSync(b.linkFor('abcdefgh${i}xyz'));
        if (i != 2) prints.add(p.join(dir.path, 'print_may_in.jpg'));
        card.dispose();
      }
      await prints.check();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    return b;
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
      await t.pump(const Duration(milliseconds: 400));
    }
  }

  /// Real time passes (file reads, the frame scan on its isolate) until [f] shows.
  Future<void> waitFor(WidgetTester t, Finder f) async {
    for (var i = 0; i < 100 && f.evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> shot(WidgetTester t, String name) async {
    await settle(t);
    if (out == null) return;
    final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
    final png = await t.runAsync(() async {
      final img = await boundary.toImage();
      return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    });
    Directory(out).createSync(recursive: true);
    File(p.join(out, '$name.png')).writeAsBytesSync(png!);
  }

  {
    testWidgets('every staff page builds at iPad size, printer up then down', (t) async {
      await t.runAsync(() async {
        LuxFonts.enabled = true;
        GoogleFonts.config.allowRuntimeFetching = false;
        await _loadIcons();
      });
      t.view
        ..physicalSize = const Size(1194, 834)
        ..devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final b = await booth(t);
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(brightness: Brightness.dark),
          home: RepaintBoundary(key: const ValueKey('shot'), child: AdminScreen(booth: b)),
        ),
      );
      await t.runAsync(() => GoogleFonts.pendingFonts().catchError((_) => <void>[]));
      await shot(t, '1-may-in');
      expect(find.text('Sẵn sàng'), findsWidgets);

      // A toggle shows its new state at once (it used to wait for a tab switch).
      final toggle = find.byType(GoldToggle).first;
      final before = t.widget<GoldToggle>(toggle).value;
      for (final want in [!before, before]) {
        await t.tap(toggle);
        await t.pump();
        expect(t.widget<GoldToggle>(find.byType(GoldToggle).first).value, want);
      }

      for (final (label, name) in [
        ('Máy ảnh', '2-may-anh'),
        ('Khung ảnh', '3-khung-anh'),
        ('Sự kiện', '4-su-kien'),
        ('Lịch sử in', '5-lich-su'),
      ]) {
        await t.tap(find.text(label).first);
        await shot(t, name);
      }
      expect(find.text('In lại'), findsWidgets);

      // The SELPHY goes away: 7b.
      printerUp = false;
      await t.runAsync(b.prints.check);
      await t.tap(find.text('Máy in').first);
      await shot(t, '1b-may-in-mat-ket-noi');
      expect(find.text('Mất kết nối'), findsWidgets);
      expect(find.text('Thử lại'), findsOneWidget);
      // 7d: a custom frame (pink card, 4 holes, busy pattern bottom-right) edited.
      await t.runAsync(() async {
        final rec = ui.PictureRecorder();
        final c = Canvas(rec);
        c.drawRect(const Rect.fromLTWH(0, 0, 1776, 1200), Paint()..color = const Color(0xFFF0D6CE));
        for (var x = 1500.0; x < 1776; x += 12) {
          c.drawRect(Rect.fromLTWH(x, 900, 6, 300), Paint()..color = const Color(0xFF5A3A36));
        }
        for (final r in const [
          Rect.fromLTWH(116, 56, 760, 428),
          Rect.fromLTWH(900, 56, 760, 428),
          Rect.fromLTWH(116, 508, 760, 428),
          Rect.fromLTWH(900, 508, 760, 428),
        ]) {
          c.drawRect(r, Paint()..blendMode = BlendMode.clear);
        }
        final img = await rec.endRecording().toImage(1776, 1200);
        final png = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        await b.frames.saveCustom(
          name: 'Hồng champagne',
          png: png,
          card: const Size(1776, 1200),
          slots: const [Rect.fromLTWH(116, 56, 760, 428)],
          qr: const Rect.fromLTWH(60, 980, 180, 180),
        );
      });
      await t.tap(find.text('Khung ảnh').first);
      await settle(t);
      expect(find.text('PNG riêng'), findsOneWidget);
      await t.ensureVisible(find.byIcon(Icons.edit_outlined));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byIcon(Icons.edit_outlined));
      await waitFor(t, find.text('Tìm thấy 4 ô trong suốt'));
      await shot(t, '3b-sua-khung');
      expect(find.text('Sửa khung'), findsOneWidget);
      expect(find.text('Tìm thấy 4 ô trong suốt'), findsOneWidget);
      // "Tự nhận": the QR leaves the saved spot for a plain one off the stripes.
      await t.tap(find.text('Tự nhận'));
      await settle(t);
      expect(find.textContaining('Chỗ QR trống ở'), findsOneWidget);
      await t.tap(find.byType(GoldToggle).first);
      await waitFor(t, find.byType(RawImage));
      await shot(t, '3c-anh-mau');
      await t.ensureVisible(find.text('Lưu khung'));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('Lưu khung'));
      await waitFor(t, find.text('Thêm khung'));
      final saved = b.frames.all.firstWhere((f) => !f.builtIn);
      expect(saved.slots.length, 4);
      expect(saved.qr.right <= 1500 || saved.qr.bottom <= 900, isTrue, reason: 'QR off the stripes: ${saved.qr}');
      // A new frame: the empty picker state.
      await t.tap(find.text('Thêm khung').first);
      await shot(t, '3d-them-khung');
      expect(find.text('Chọn file PNG khung'), findsOneWidget);
      await t.tap(find.text('Huỷ'));
      await settle(t);

      // History: delete one guest (asked first), then "Dọn máy" clears the rest (all online).
      await t.tap(find.text('Lịch sử in').first);
      await settle(t);
      expect(find.textContaining('6 lượt trên iPad này'), findsOneWidget);
      await t.tap(find.byIcon(Icons.delete_outline).first);
      await settle(t);
      await shot(t, '5b-xoa-luot');
      expect(find.text('Xoá lượt 6?'), findsOneWidget);
      await t.tap(find.text('Xoá'));
      await settle(t);
      expect(find.textContaining('5 lượt trên iPad này'), findsOneWidget);
      expect(Directory(p.join(b.docs.path, 'Booth', '2026-12-23', '21-45-00')).existsSync(), isFalse);
      await t.tap(find.text('Dọn máy'));
      await settle(t);
      await shot(t, '5c-don-may');
      await t.tap(find.text('Xoá 5 lượt'));
      await settle(t);
      expect(find.text('Chưa có lượt chụp nào.'), findsOneWidget);
      expect(b.prints.jobs, isEmpty, reason: 'their print jobs go with them');

      await t.tap(find.text('Về màn chờ'));
      await t.pump(const Duration(milliseconds: 500));
      b.prints.dispose();
    });
  }
}
