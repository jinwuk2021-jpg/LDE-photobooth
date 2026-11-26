import 'dart:convert';
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

  test('printer away: the job waits (not failed) and goes by itself when the printer is back', () {
    fakeAsync((async) {
      var online = false;
      final sent = <String>[];
      final q = PrintQueue(
        prefs,
        settings,
        docs,
        reachable: (_) async => online,
        send: (_, path, _) async {
          sent.add(path);
          return null;
        },
      )..start(watchLifecycle: false);
      async.flushMicrotasks();
      expect(q.printerOk, isFalse);
      q.add(card('a.jpg'));
      async.flushMicrotasks();
      expect(sent, isEmpty);
      expect(q.jobs.single.status, JobStatus.waiting);
      expect(q.jobs.single.error, PrintQueue.waitingForPrinter);
      async.elapse(const Duration(seconds: 45));
      expect(sent, isEmpty);
      expect(q.jobs.single.status, JobStatus.waiting);
      online = true;
      async.elapse(PrintQueue.offlineEvery);
      expect(sent, hasLength(1));
      expect(q.jobs.single.status, JobStatus.done);
      expect(q.printerOk, isTrue);
      expect(q.lastSeen, isNotNull);
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

  test('printer back after a long time: old waiting jobs are not printed by themselves', () {
    fakeAsync((async) {
      final t0 = DateTime(2026, 12, 23, 20);
      var online = false;
      final sent = <String>[];
      final q = PrintQueue(
        prefs,
        settings,
        docs,
        now: () => t0.add(async.elapsed),
        reachable: (_) async => online,
        send: (_, path, _) async {
          sent.add(path.split('/').last);
          return null;
        },
      )..start(watchLifecycle: false);
      q.add(card('old.jpg'));
      async.elapse(const Duration(minutes: 10));
      q.add(card('recent.jpg'));
      async.elapse(const Duration(minutes: 10));
      // Switched on 20 min after the first job, 10 min after the second.
      online = true;
      async.elapse(PrintQueue.offlineEvery);
      expect(sent, ['recent.jpg']);
      final old = q.jobs.firstWhere((j) => j.path.endsWith('old.jpg'));
      expect(old.status, JobStatus.failed);
      expect(old.error, PrintQueue.tooLate);
      // Staff still can.
      q.retry(old);
      async.flushMicrotasks();
      expect(sent, ['recent.jpg', 'old.jpg']);
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
    var online = true;
    final q = PrintQueue(
      prefs,
      settings,
      docs,
      reachable: (_) async => online,
      send: (_, path, _) async {
        sent.add(path);
        return null;
      },
    )..load();
    expect(q.jobs.map((j) => j.path), ['kept.jpg']);
    expect(q.failedCount, 1);
    expect(prefs.getString('printJobs'), isNot(contains('gone')));

    // Deleted while waiting for the printer: gone from the queue, the next one still prints.
    online = false;
    final doomed = card('doomed.jpg');
    q.add(doomed);
    final next = card('next.jpg');
    q.add(next);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(sent, isEmpty);
    File(doomed).deleteSync();
    online = true;
    q.resume();
    for (var i = 0; i < 20 && sent.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(sent, [next]);
    expect(q.jobs.map((j) => j.path), isNot(contains('doomed.jpg')));
    expect(q.failedCount, 1, reason: 'only the old kept.jpg failure');
    expect(kept, isNotEmpty);
    q.dispose();
  });
}
