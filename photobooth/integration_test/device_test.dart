// On-device checks (camera, Live clips, shaders, native JPEG / Photos / AirPrint channel, upload
// to the real share Worker). Needs the iPad plugged in and unlocked:
//
//   flutter test integration_test/device_test.dart -d <iPad> --dart-define-from-file=booth_defines.json
//
// Leaves the booth as it found it: printer, frames and print queue are restored, the test
// sessions' folders are deleted. Their prints stay in the Photos album and on the server (30 days).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:photobooth/booth/booth.dart';
import 'package:photobooth/booth/frames.dart';
import 'package:photobooth/booth/print_layout.dart';
import 'package:photobooth/camera/filters.dart';
import 'package:photobooth/config.dart';
import 'package:photobooth/main.dart';
import 'package:photobooth/screens/admin_screen.dart';
import 'package:photobooth/screens/pick_screen.dart';
import 'package:photobooth/screens/shoot_screen.dart';
import 'package:photobooth/screens/thanks_screen.dart';
import 'package:photobooth/services/printer.dart';
import 'package:photobooth/ui/lux.dart';
import 'package:photobooth/ui/strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nobody answers here (TEST-NET-1): stands in for a SELPHY that is off.
const _deadPrinter = 'ipp://192.0.2.10:631/ipp/print';

/// Release builds' print() does not reach `devicectl --console`: also written to Documents/device_test.log
/// (`xcrun devicectl device copy from --domain-type appDataContainer ...`).
File? _logFile;
void log(String s) {
  debugPrint('[device] $s');
  _logFile?.writeAsStringSync('${DateTime.now().toIso8601String().substring(11, 19)} $s\n', mode: FileMode.append, flush: true);
}

/// testWidgets that logs PASS / FAIL (with the error) to the log file.
void check(String name, Future<void> Function(WidgetTester) body, {Duration timeout = const Duration(minutes: 10)}) {
  testWidgets(name, (t) async {
    log('START $name');
    try {
      await body(t);
      log('PASS  $name');
    } catch (e, st) {
      log('FAIL  $name\n$e\n${st.toString().split('\n').take(12).join('\n')}');
      rethrow;
    }
  }, timeout: Timeout(timeout));
}

Future<void> waitFor(WidgetTester t, bool Function() ok, {required Duration timeout, String what = ''}) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('timed out after ${timeout.inSeconds}s waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await t.pump();
  }
}

Finder byClass(String name) => find.byWidgetPredicate((w) => w.runtimeType.toString() == name);

Future<(int, int)> imageSize(String path) async {
  final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
  final img = (await codec.getNextFrame()).image;
  codec.dispose();
  final r = (img.width, img.height);
  img.dispose();
  return r;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  late Booth booth;
  late SharedPreferences prefs;
  final saved = <String, Object?>{};
  final created = <Directory>[];
  const keep = ['printerUrl', 'printerName', 'printJobs', 'framesEnabled', 'printing'];

  setUpAll(() async {
    prefs = await SharedPreferences.getInstance();
    for (final k in keep) {
      saved[k] = prefs.get(k);
    }
    booth = await createBooth();
    _logFile = File(p.join(booth.docs.path, 'device_test.log'))..writeAsStringSync('');
    await LuxFonts.warmUp();
    // The camera is opened by the app's Home (as at launch), once: init() runs only once per process.
    // Printing on, with a printer that never answers: jobs must wait, not fail or vanish.
    booth.settings.printing = true;
    await booth.settings.setPrinter(_deadPrinter, 'SELPHY (test, tắt)');
  });

  tearDownAll(() async {
    booth.prints.dispose();
    for (final k in keep) {
      final v = saved[k];
      if (v == null) {
        await prefs.remove(k);
      } else if (v is String) {
        await prefs.setString(k, v);
      } else if (v is bool) {
        await prefs.setBool(k, v);
      } else if (v is List<String>) {
        await prefs.setStringList(k, v);
      }
    }
    for (final d in created) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    log('restored ${keep.join(", ")}; deleted ${created.length} test session folder(s)');
    log('DONE');
  });

  check('native printer channel: an unreachable printer is reported, never hangs', (t) async {
    final sw = Stopwatch()..start();
    // The queue gives up after PrintQueue.contactTimeout; here: how long iOS itself takes.
    final up = await PrinterChannel.reachable(_deadPrinter).timeout(const Duration(minutes: 3), onTimeout: () {
      log('reachable($_deadPrinter): no answer from iOS after 3 min');
      return false;
    });
    log('reachable($_deadPrinter) = $up in ${sw.elapsedMilliseconds} ms');
    expect(up, isFalse);
    expect(await PrinterChannel.reachable('not a url').timeout(const Duration(seconds: 30)), isFalse);
  });

  Future<Finished> guest(WidgetTester t, BoothFrame frame, {BoothFilter? filter}) async {
    await booth.frames.setEnabled(frame, true);
    final enabled = booth.frames.enabled;
    // Start screen (the first time Home also opens the camera, as at launch).
    await waitFor(t, () => find.text(T.now.start).evaluate().isNotEmpty, timeout: const Duration(seconds: 20), what: 'start');
    await t.tap(find.text(T.now.start));
    await waitFor(t, () => byClass('_FrameCard').evaluate().length == enabled.length, timeout: const Duration(seconds: 5), what: 'frames');
    final card = byClass('_FrameCard').at(enabled.indexOf(frame));
    await t.ensureVisible(card);
    await t.tap(card);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text(T.now.startShooting));
    final shotSw = Stopwatch()..start();
    await waitFor(t, () => find.byType(ShootScreen).evaluate().isNotEmpty, timeout: const Duration(seconds: 5), what: 'shoot');
    // 3 s ready + 5 s + 3 s per next shot, plus capture time.
    final shootBudget = Duration(seconds: 3 + 5 + 3 * frame.shots + 4 * frame.shots + 10);
    await waitFor(
      t,
      () => find.byType(PickScreen).evaluate().isNotEmpty,
      timeout: shootBudget,
      what: '${frame.shots} shots',
    );
    log('${frame.id}: ${frame.shots} shots in ${shotSw.elapsed.inMilliseconds} ms');
    // Heat: the camera is off while the guest picks.
    await waitFor(t, () => booth.camera.preview == null, timeout: const Duration(seconds: 5), what: 'camera off at the picker');
    await waitFor(t, () => byClass('_ShotTile').evaluate().length == frame.shots, timeout: const Duration(seconds: 30), what: 'developed tiles');
    if (filter != null) {
      await t.tap(byClass('_FilterChip').at(BoothFilter.values.indexOf(filter)));
      await t.pump(const Duration(milliseconds: 300));
    }
    // Pick the last shots first: the print order is the tap order.
    for (var i = frame.shots - 1; i >= frame.shots - frame.picks; i--) {
      await t.tap(byClass('_ShotTile').at(i));
      await t.pump(const Duration(milliseconds: 150));
    }
    await waitFor(t, () => find.text(T.now.print).evaluate().isNotEmpty, timeout: const Duration(seconds: 20), what: 'In button');
    // The button is enabled once the filter has been developed.
    await Future<void>.delayed(const Duration(seconds: 2));
    await t.pump();
    final printSw = Stopwatch()..start();
    await t.tap(find.text(T.now.print));
    await waitFor(t, () => find.byType(ThanksScreen).evaluate().isNotEmpty, timeout: const Duration(seconds: 30), what: 'thanks');
    log('${frame.id}: In → thanks in ${printSw.elapsedMilliseconds} ms');
    final thanks = t.widget<ThanksScreen>(find.byType(ThanksScreen));
    return thanks.finished;
  }

  Future<void> checkSession(WidgetTester t, Finished f, BoothFrame frame) async {
    final id = f.url.split('/').last;
    final dir = File(f.printPath).parent;
    created.add(dir);
    log('${frame.id}: ${f.url}  (${p.relative(dir.path, from: booth.docs.path)})');
    expect(f.url, startsWith('${SHARE_API_URL.replaceAll(RegExp(r'/+$'), '')}/b/'));
    expect(f.printed, isTrue);
    expect(File(p.join(dir.path, 'link.txt')).readAsStringSync().trim(), f.url);

    // Print as designed (landscape for 4 Cut) and the printer's copy (always portrait).
    final (pw, ph) = await imageSize(f.printPath);
    expect(pw > ph, frame.landscape, reason: 'print.jpg orientation');
    final printerCopy = p.join(dir.path, 'print_may_in.jpg');
    final (cw, ch) = await imageSize(printerCopy);
    expect(ch > cw, isTrue, reason: 'printer copy must be portrait');
    log('${frame.id}: print.jpg ${pw}x$ph, print_may_in.jpg ${cw}x$ch');

    // Photos in tap order (last shots first) and their Live clips.
    for (var k = 1; k <= frame.picks; k++) {
      final (w, h) = await imageSize(p.join(dir.path, '$k.jpg'));
      expect((w / h - frame.cellAspect).abs() < 0.02, isTrue, reason: '$k.jpg aspect ${w / h} vs cell ${frame.cellAspect}');
    }
    await waitFor(
      t,
      () => [for (var k = 1; k <= frame.picks; k++) File(p.join(dir.path, '$k.mp4'))].every((f) => f.existsSync() && f.lengthSync() > 50000),
      timeout: Duration(seconds: 25 * frame.picks),
      what: 'Live clips',
    );
    for (var k = 1; k <= frame.picks; k++) {
      log('${frame.id}: $k.mp4 ${(File(p.join(dir.path, '$k.mp4')).lengthSync() / 1024).round()} KB');
    }

    // The print waits for the (switched off) printer instead of failing.
    final job = booth.prints.jobs.firstWhere((j) => j.path == p.relative(printerCopy, from: booth.docs.path));
    // Jobs go in order: only the first waiting one is held up with the reason, the rest queue behind it.
    final first = booth.prints.jobs.lastWhere((j) => j.status == JobStatus.waiting);
    await waitFor(t, () => first.error == PrintQueue.waitingForPrinter, timeout: const Duration(seconds: 30), what: 'print job waiting');
    expect(job.status, JobStatus.waiting);
    expect(booth.prints.printerOk, isFalse);

    // Everything reaches the real Worker and the guest page serves it.
    await waitFor(
      t,
      () => booth.uploads.items.every((i) => i.session != id),
      timeout: const Duration(minutes: 3),
      what: 'uploads (${booth.uploads.lastError ?? "no error"})',
    );
    final status = jsonDecode((await http.get(Uri.parse('${f.url}/status.json'))).body) as Map;
    log('${frame.id}: status.json $status');
    expect(status['n'], greaterThanOrEqualTo(1 + 2 * frame.picks));
    final page = await http.get(Uri.parse(f.url));
    expect(page.statusCode, 200);
    for (final name in ['print.jpg', '1.jpg', '1.mp4']) {
      final r = await http.head(Uri.parse('${f.url}/$name'));
      expect(r.statusCode, 200, reason: name);
      log('${frame.id}: $name ${r.headers['content-type']} ${r.headers['content-length']} B');
    }
  }

  check('guest flows on the device: 2 Cut (filter changed), then 4 Cut (landscape)', (t) async {
    lang.value = Lang.vi;
    await t.pumpWidget(BoothApp(booth: booth));
    await waitFor(t, () => find.text(T.now.start).evaluate().isNotEmpty, timeout: const Duration(seconds: 20), what: 'start');
    // Heat: the camera stays off on the start screen.
    expect(booth.camera.preview, isNull);

    // Staff: a tap on the gear only shows the hint; holding it 3 s opens admin.
    await waitFor(t, () => find.byIcon(Icons.settings).evaluate().isNotEmpty, timeout: const Duration(seconds: 20), what: 'gear');
    await t.tap(find.byIcon(Icons.settings));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(AdminScreen), findsNothing);
    expect(find.byType(ShootScreen), findsNothing, reason: 'the gear never starts a guest');
    final hold = await t.startGesture(t.getCenter(find.byIcon(Icons.settings)));
    await Future<void>.delayed(ADMIN_HOLD + const Duration(milliseconds: 400));
    await t.pump();
    await hold.up();
    await waitFor(t, () => find.byType(AdminScreen).evaluate().isNotEmpty, timeout: const Duration(seconds: 3), what: 'admin');
    log('gear: hold ${ADMIN_HOLD.inSeconds} s opens admin');
    await t.tap(find.text('Về màn chờ'));
    await waitFor(t, () => find.byType(AdminScreen).evaluate().isEmpty, timeout: const Duration(seconds: 3), what: 'admin closed');

    final two = booth.frames.all.firstWhere((f) => f.id == 'lpe_2cut_ivory');
    final f2 = await guest(t, two, filter: BoothFilter.values.last);
    await checkSession(t, f2, two);
    await t.tap(find.text(T.now.done));

    final four = booth.frames.all.firstWhere((f) => f.id == 'lpe_4cut_black');
    final f4 = await guest(t, four);
    await checkSession(t, f4, four);
    // Both prints wait for the printer, none lost.
    expect(booth.prints.waitingCount, greaterThanOrEqualTo(2));
  });

  check('every filter develops on the GPU; every frame renders and saves', (t) async {
    // One more shot straight from the camera.
    final frame = booth.frames.all.firstWhere((f) => f.id == 'lpe_6cut_ivory');
    await booth.camera.wake();
    await booth.camera.live.start();
    final shot = await booth.camera.capture(0, cellAspect: frame.cellAspect, skin: booth.settings.skin);
    await booth.camera.live.stop();
    // Sharpness: the format's biggest stills (2304 × 1296 on the M4 front camera; 1920 × 1080 before).
    final (rw, rh) = await imageSize(shot.rawPath);
    log('raw still ${rw}x$rh');
    expect(rw > rh ? rw : rh, greaterThan(1920), reason: 'still ${rw}x$rh');
    final base = await shot.base;
    final out = Directory(p.join(booth.docs.path, 'Booth', 'device-test'))..createSync(recursive: true);
    created.add(out);
    final developed = <ui.Image>[];
    for (final filter in BoothFilter.values) {
      final sw = Stopwatch()..start();
      final img = await booth.camera.develop(base, filter, '0');
      expect((img.width, img.height), (base.width, base.height));
      final path = await booth.camera.saveJpeg(img, p.join(out.path, '${filter.name}.jpg'));
      expect(File(path).lengthSync(), greaterThan(10000));
      log('filter ${filter.name}: ${sw.elapsedMilliseconds} ms');
      developed.add(img);
    }
    for (final fr in booth.frames.all) {
      final sw = Stopwatch()..start();
      final card = await renderPrint(
        PrintSpec(
          frame: fr,
          photos: [for (var i = 0; i < fr.picks; i++) developed[i % developed.length]],
          title: booth.settings.title,
          dateLine: booth.settings.dateLine,
          subtitle: booth.settings.subtitle,
          qrUrl: booth.linkFor('testtesttest'),
          scanHint: T.now.printScanHint,
        ),
      );
      final printPath = await booth.camera.saveJpeg(card, p.join(out.path, '${fr.id}.jpg'), quality: 95);
      final copy = await booth.printerCopy(card, p.join(out.path, '${fr.id}_may_in.jpg'));
      final (w, h) = await imageSize(copy);
      expect(h > w, isTrue, reason: '${fr.id} printer copy portrait');
      expect(File(printPath).lengthSync(), greaterThan(50000));
      log('frame ${fr.id}: card ${card.width}x${card.height}, printer ${w}x$h, ${sw.elapsedMilliseconds} ms');
      card.dispose();
    }
    for (final img in developed) {
      img.dispose();
    }
    booth.camera.release([shot]);
    await booth.camera.sleep();
    expect(booth.camera.preview, isNull);
  });
}
