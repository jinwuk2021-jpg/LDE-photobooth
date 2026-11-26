import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/printer.dart';
import 'package:photobooth/services/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  late SharedPreferences prefs;
  late BoothSettings settings;

  setUp(() async {
    docs = Directory.systemTemp.createTempSync('prints');
    SharedPreferences.setMockInitialValues({'printerUrl': 'ipps://SELPHY._ipps._tcp.local.', 'printerName': 'SELPHY'});
    prefs = await SharedPreferences.getInstance();
    settings = BoothSettings(prefs);
  });
  tearDown(() => docs.deleteSync(recursive: true));

  String card(String name) => (File('${docs.path}/$name')..writeAsBytesSync([1])).path;

  test('printer away: the job stops as an error, is not resent when the printer is back, "In lại" sends it', () {
    fakeAsync((async) {
      var online = false;
      final sent = <String>[];
      final q = PrintQueue(
        prefs,
        settings,
        docs,
        reachable: (_) async => online,
        send: (_, path, _) async {
          sent.add(path.split('/').last);
          return null;
        },
      )..start(watchLifecycle: false);
      async.flushMicrotasks();
      expect(q.printerOk, isFalse);
      q.add(card('a.jpg'));
      async.flushMicrotasks();
      expect(sent, isEmpty);
      expect(q.jobs.single.status, JobStatus.failed);
      expect(q.jobs.single.error, PrintQueue.notConnected);
      online = true;
      async.elapse(const Duration(minutes: 5));
      expect(q.printerOk, isTrue);
      expect(sent, isEmpty, reason: 'never resent by itself');
      q.retry(q.jobs.single);
      async.flushMicrotasks();
      expect(sent, ['a.jpg']);
      expect(q.jobs.single.status, JobStatus.done);
      q.dispose();
    });
  });

  test('queue: one at a time in order; a failed job stops alone, the next ones still print; send time kept', () {
    fakeAsync((async) {
      final t0 = DateTime(2026, 12, 23, 20);
      final sent = <String>[];
      final pending = <Completer<String?>>[];
      var inFlight = 0, most = 0;
      final q = PrintQueue(
        prefs,
        settings,
        docs,
        now: () => t0.add(async.elapsed),
        reachable: (_) async => true,
        send: (_, path, _) {
          sent.add(path.split('/').last);
          most = math.max(most, ++inFlight);
          final c = Completer<String?>();
          pending.add(c);
          return c.future.whenComplete(() => inFlight--);
        },
      );
      for (final n in ['1.jpg', '2.jpg', '3.jpg']) {
        q.add(card(n));
      }
      async.flushMicrotasks();
      expect(sent, ['1.jpg'], reason: 'the next waits for the first');
      async.elapse(const Duration(seconds: 9));
      pending[0].complete(null);
      async.flushMicrotasks();
      expect(sent, ['1.jpg', '2.jpg']);
      pending[1].complete('Hết giấy');
      async.flushMicrotasks();
      expect(sent, ['1.jpg', '2.jpg', '3.jpg'], reason: 'an error does not hold the queue');
      pending[2].complete(null);
      async.flushMicrotasks();
      expect(most, 1);
      final byName = {for (final j in q.jobs) j.path: j};
      expect(byName['1.jpg']!.status, JobStatus.done);
      expect(byName['1.jpg']!.sendTime, const Duration(seconds: 9));
      expect(byName['2.jpg']!.status, JobStatus.failed);
      expect(byName['2.jpg']!.error, 'Hết giấy');
      expect(byName['3.jpg']!.status, JobStatus.done);
      async.elapse(const Duration(minutes: 30));
      expect(sent, hasLength(3), reason: 'the failed one is not resent');
      q.dispose();
    });
  });

  test('watchdog: every 15 s while away, every 60 s once the printer answers', () {
    fakeAsync((async) {
      var online = false;
      var asks = 0;
      final q = PrintQueue(
        prefs,
        settings,
        docs,
        reachable: (_) async {
          asks++;
          return online;
        },
        send: (_, _, _) async => null,
      )..start(watchLifecycle: false);
      async.flushMicrotasks();
      expect(asks, 1);
      async.elapse(const Duration(seconds: 60));
      expect(asks, 5);
      online = true;
      async.elapse(const Duration(seconds: 15));
      expect(asks, 6);
      async.elapse(const Duration(seconds: 59));
      expect(asks, 6);
      async.elapse(const Duration(seconds: 1));
      expect(asks, 7);
      q.dispose();
    });
  });

  test('a refused job is never resent by itself (it may still have printed); "In lại" sends it once', () {
    fakeAsync((async) {
      var sends = 0;
      final q = PrintQueue(
        prefs,
        settings,
        docs,
        reachable: (_) async => true,
        send: (_, _, _) async {
          sends++;
          return 'Máy in không nhận lệnh';
        },
      )..start(watchLifecycle: false);
      q.add(card('a.jpg'));
      async.flushMicrotasks();
      expect(sends, 1);
      expect(q.jobs.single.status, JobStatus.failed);
      expect(q.jobs.single.error, 'Máy in không nhận lệnh');
      // The watchdog keeps finding the printer: still nothing more comes out.
      async.elapse(const Duration(minutes: 10));
      expect(sends, 1);
      q.retry(q.jobs.single);
      async.flushMicrotasks();
      expect(sends, 2);
      async.elapse(const Duration(minutes: 10));
      expect(sends, 2);
      q.dispose();
    });
  });

  test('a relaunch never prints yesterday\'s waiting jobs', () async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final path = card('y.jpg');
    await prefs.setString('printJobs', jsonEncode([PrintJob(path: path.split('/').last, created: yesterday).toJson()]));
    var sends = 0;
    final q = PrintQueue(
      prefs,
      settings,
      docs,
      reachable: (_) async => true,
      send: (_, _, _) async {
        sends++;
        return null;
      },
    )..load();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(sends, 0);
    expect(q.jobs.single.status, JobStatus.failed);
    expect(q.jobs.single.error, PrintQueue.tooLate);
  });

  test('a job that timed out is not resent (it may have printed)', () {
    fakeAsync((async) {
      var sends = 0;
      final q = PrintQueue(
        prefs,
        settings,
        docs,
        reachable: (_) async => true,
        send: (_, _, _) {
          sends++;
          return Future<String?>.delayed(const Duration(minutes: 10), () => null);
        },
      );
      q.add(card('a.jpg'));
      async.elapse(PrintQueue.printTimeout + const Duration(seconds: 1));
      expect(q.jobs.single.status, JobStatus.failed);
      async.elapse(const Duration(minutes: 10));
      expect(sends, 1);
      q.dispose();
    });
  });

  test('jobs go one at a time, in order, and survive a relaunch', () async {
    final sent = <String>[];
    var online = true;
    final q = PrintQueue(
      prefs,
      settings,
      docs,
      reachable: (_) async => online,
      send: (_, path, _) async {
        sent.add(path.split('/').last);
        return null;
      },
    );
    await settings.setPrinter('', '');
    await prefs.remove('printerUrl');
    q
      ..add(card('1.jpg'))
      ..add(card('2.jpg'));
    await Future<void>.delayed(Duration.zero);
    expect(q.jobs.map((j) => j.status), [JobStatus.failed, JobStatus.failed]);
    await settings.setPrinter('ipps://SELPHY._ipps._tcp.local.', 'SELPHY');
    final again = PrintQueue(
      prefs,
      settings,
      docs,
      reachable: (_) async => true,
      send: (_, path, _) async {
        sent.add(path.split('/').last);
        return null;
      },
    )..load();
    for (final j in again.jobs.reversed) {
      again.retry(j);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(sent, ['1.jpg', '2.jpg']);
    expect(again.jobs.map((j) => j.status), [JobStatus.done, JobStatus.done]);
  });

  test('jobs whose picture is gone are dropped, at launch and when their turn comes', () async {
    // Saved by an earlier run: one card still there, two deleted (a cleaned-up test session).
    final kept = card('kept.jpg');
    await prefs.setString(
      'printJobs',
      '[${[
        for (final (name, status) in [('gone1.jpg', 'failed'), ('kept.jpg', 'failed'), ('gone2.jpg', 'waiting')]) '{"path":"$name","created":"2026-11-26T00:45:35.000","status":"$status"}',
      ].join(',')}]',
    );
    final sent = <String>[];
    Completer<String?>? hold;
    final q = PrintQueue(
      prefs,
      settings,
      docs,
      reachable: (_) async => true,
      send: (_, path, _) {
        sent.add(path);
        return (hold = Completer<String?>()).future;
      },
    )..load();
    expect(q.jobs.map((j) => j.path), ['kept.jpg']);
    expect(q.failedCount, 1);
    expect(prefs.getString('printJobs'), isNot(contains('gone')));

    // Deleted while waiting behind a print in progress: gone from the queue, the next one still prints.
    final first = card('first.jpg');
    q.add(first);
    final doomed = card('doomed.jpg');
    q.add(doomed);
    final next = card('next.jpg');
    q.add(next);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(sent, [first]);
    File(doomed).deleteSync();
    hold!.complete(null);
    for (var i = 0; i < 20 && sent.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    hold!.complete(null);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(sent, [first, next]);
    expect(q.jobs.map((j) => j.path), isNot(contains('doomed.jpg')));
    expect(q.failedCount, 1, reason: 'only the old kept.jpg failure');
    expect(kept, isNotEmpty);
    q.dispose();
  });
}
