import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'settings.dart';

/// Native side: ios/Runner/BoothPrinter.swift (UIPrinterPickerController, UIPrintInteractionController).
abstract final class PrinterChannel {
  static const _ch = MethodChannel('booth/printer');

  /// Shows the system printer picker once; (url, name) of the chosen printer.
  static Future<(String, String)?> pick() async {
    final r = await _ch.invokeMapMethod<String, String>('pick');
    if (r == null) return null;
    return (r['url']!, r['name'] ?? r['url']!);
  }

  /// Prints the image at [path] on [url] without any dialog. Null when done, else the error.
  /// [fill]: cover the whole sheet (borderless) instead of fitting the printable area (only
  /// honoured when the sheet has the card's shape). [paper]: the paper asked of the printer.
  static Future<String?> printFile(
    String url,
    String path, {
    bool fill = true,
    PrintPaper paper = PrintPaper.postcard,
  }) async {
    try {
      return await _ch.invokeMethod<String>('print', {
        'url': url,
        'path': path,
        'fill': fill,
        'paperW': paper.widthMm,
        'paperH': paper.heightMm,
      });
    } on PlatformException catch (e) {
      return e.message ?? e.code;
    }
  }

  /// Whether the printer answers on the network (for the staff badge).
  static Future<bool> reachable(String url) async =>
      await _ch.invokeMethod<bool>('reachable', {'url': url}).catchError((_) => false) ?? false;
}

enum JobStatus { waiting, printing, done, failed }

class PrintJob {
  PrintJob({required this.path, required this.created, this.status = JobStatus.waiting, this.error, this.attempts = 0});

  factory PrintJob.fromJson(Map<String, Object?> j) => PrintJob(
    path: j['path']! as String,
    created: DateTime.parse(j['created']! as String),
    // A job cut off by a relaunch while printing is not known to be done: shown as failed.
    status: switch (j['status']) {
      'done' => JobStatus.done,
      'waiting' => JobStatus.waiting,
      _ => JobStatus.failed,
    },
    error: j['error'] as String?,
    attempts: (j['attempts'] as num?)?.toInt() ?? 0,
  );

  /// The print JPEG, relative to the documents directory (`Booth/<day>/<time>/print.jpg`).
  final String path;
  final DateTime created;
  JobStatus status;

  /// Why it failed, or (while waiting) why it has not gone yet.
  String? error;

  /// Times it was sent and refused (drives the automatic retries).
  int attempts;

  /// Held back after a refusal until its retry timer fires. In memory only: a relaunch tries at once.
  bool held = false;

  Map<String, Object?> toJson() => {
    'path': path,
    'created': created.toIso8601String(),
    'status': status.name,
    'error': error,
    'attempts': attempts,
  };
}

/// Sends prints one by one: the next job goes only after the previous one's completion handler ran.
///
/// AirPrint keeps no open connection: each job finds the printer again by its saved URL (the
/// Bonjour name when picked from the list, so a new IP address on the hotspot does not matter).
/// What goes wrong is the printer being asleep, off or off the network at that moment, so:
/// - a watchdog asks the printer every [offlineEvery] while it does not answer (every
///   [onlineEvery] while it does), from launch on, and again when the app comes back to the front;
/// - a job is only sent once the printer answers; until then it waits (never lost, never failed)
///   and goes as soon as the printer is back;
/// - a job the printer refuses is retried by itself [autoRetries] times (15 s, 30 s, 60 s apart)
///   before it shows as failed in admin. A job that timed out is not: it may have printed.
class PrintQueue extends ChangeNotifier {
  PrintQueue(
    this._prefs,
    this._settings,
    this.docs, {
    Future<bool> Function(String url)? reachable,
    Future<String?> Function(String url, String path, bool fill)? send,
  }) : _reachable = reachable ?? PrinterChannel.reachable,
       // A named parameter cannot be a private initializing formal.
       // ignore: prefer_initializing_formals
       _send = send;

  final SharedPreferences _prefs;
  final Directory docs;
  final BoothSettings _settings;
  final Future<bool> Function(String url) _reachable;

  /// Tests send through this; null = the real printer ([_toPrinter]).
  final Future<String?> Function(String url, String path, bool fill)? _send;

  Future<String?> _toPrinter(String url, String path, bool fill) =>
      PrinterChannel.printFile(url, path, fill: fill, paper: _settings.printPaper);
  final List<PrintJob> _jobs = [];
  bool _busy = false;
  Timer? _watchdog;
  final Set<Timer> _retryTimers = {};
  AppLifecycleListener? _lifecycle;

  static const offlineEvery = Duration(seconds: 15);
  static const onlineEvery = Duration(seconds: 60);
  static const autoRetries = 3;
  static const retryBase = Duration(seconds: 15);
  static const contactTimeout = Duration(seconds: 12);
  static const printTimeout = Duration(minutes: 3);
  static const _timeoutError = 'Máy in không phản hồi sau 3 phút';
  static const waitingForPrinter = 'Đang chờ máy in kết nối lại';

  /// Last result: null = not asked yet, true = answers / last job ok, false = unreachable or last job failed.
  bool? printerOk;

  /// When the printer last answered (admin shows it).
  DateTime? lastSeen;

  /// How long the printer took to answer the last time it did.
  Duration? lastLatency;

  /// Newest first, the last 50.
  List<PrintJob> get jobs => _jobs.reversed.toList();
  int get failedCount => _jobs.where((j) => j.status == JobStatus.failed).length;
  int get waitingCount => _jobs.where((j) => j.status == JobStatus.waiting).length;

  void load() {
    try {
      final list = jsonDecode(_prefs.getString('printJobs') ?? '[]') as List;
      _jobs.addAll(list.map((e) => PrintJob.fromJson((e as Map).cast<String, Object?>())));
    } catch (_) {}
    dropMissing();
    _pump();
  }

  /// Forgets the jobs whose picture is gone (a deleted session, a cleaned-up test): they can never
  /// print, and they showed as errors in "Lịch sử in" with no session to go with them.
  void dropMissing() {
    final before = _jobs.length;
    _jobs.removeWhere((j) => j.status != JobStatus.printing && !File(p.join(docs.path, j.path)).existsSync());
    if (_jobs.length != before) _save();
  }

  /// Starts the watchdog (and re-checks when the iPad wakes the app). Called once from main().
  void start({bool watchLifecycle = true}) {
    if (watchLifecycle) _lifecycle ??= AppLifecycleListener(onResume: () => check());
    _tick();
  }

  void _tick() {
    _watchdog?.cancel();
    unawaited(
      check().whenComplete(() {
        _watchdog = Timer(printerOk == true ? onlineEvery : offlineEvery, _tick);
      }),
    );
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    for (final t in _retryTimers) {
      t.cancel();
    }
    _lifecycle?.dispose();
    super.dispose();
  }

  /// Queues [absolutePath]; the job is returned so a screen can follow it ("In thêm 1 tấm").
  PrintJob add(String absolutePath) {
    final job = PrintJob(
      path: p.relative(absolutePath, from: docs.path),
      created: DateTime.now(),
    );
    _jobs.add(job);
    _save();
    _pump();
    return job;
  }

  /// Printing was switched on (or a printer picked): send what is waiting.
  void resume() => _pump();

  /// "In lại" in admin: sends it now, with a fresh set of automatic retries.
  void retry(PrintJob job) {
    job
      ..status = JobStatus.waiting
      ..error = null
      ..attempts = 0
      ..held = false;
    _save();
    _pump();
  }

  /// Asks the printer whether it is there; sends waiting jobs when it is.
  Future<void> check() async {
    if (!_settings.printing) return;
    final url = _settings.printerUrl;
    if (url == null || _busy) return;
    final ok = await _ask(url);
    if (ok) lastSeen = DateTime.now();
    if (ok != printerOk) {
      printerOk = ok;
      notifyListeners();
    }
    if (ok) await _pump();
  }

  Future<bool> _ask(String url) async {
    final sw = Stopwatch()..start();
    final ok = await _reachable(url)
        .then<bool>((v) => v)
        .timeout(contactTimeout, onTimeout: () => false)
        .catchError((_) => false);
    if (ok) lastLatency = sw.elapsed;
    return ok;
  }

  /// Every failed job goes again ("Thử lại lỗi").
  void retryFailed() {
    for (final j in _jobs.where((j) => j.status == JobStatus.failed).toList()) {
      j
        ..status = JobStatus.waiting
        ..error = null
        ..attempts = 0
        ..held = false;
    }
    _save();
    _pump();
  }

  /// The printer was forgotten: nothing is known about it any more.
  void forget() {
    printerOk = null;
    lastSeen = null;
    lastLatency = null;
    notifyListeners();
  }

  void _save() {
    while (_jobs.length > 50) {
      _jobs.removeAt(0);
    }
    _prefs.setString('printJobs', jsonEncode([for (final j in _jobs) j.toJson()]));
    notifyListeners();
  }

  Future<void> _pump() async {
    if (_busy || !_settings.printing) return;
    final job = _jobs.where((j) => j.status == JobStatus.waiting && !j.held).firstOrNull;
    if (job == null) return;
    final url = _settings.printerUrl;
    final file = p.join(docs.path, job.path);
    _busy = true;
    String? error;
    if (url == null) {
      error = 'Chưa chọn máy in';
    } else if (!File(file).existsSync()) {
      // Gone for good: dropped, not shown as an error that no retry can fix.
      _jobs.remove(job);
      _busy = false;
      _save();
      unawaited(_pump());
      return;
    } else if (!await _ask(url)) {
      // Asleep / off / off the hotspot: the job keeps its place and goes when the watchdog sees
      // the printer again. Not a failure, so no retry is used up.
      job.error = waitingForPrinter;
      printerOk = false;
      _busy = false;
      _save();
      return;
    } else {
      lastSeen = DateTime.now();
      job
        ..status = JobStatus.printing
        ..error = null;
      _save();
      // A printer that never answers (out of paper, switched off mid-job) must not stop the queue,
      // and nothing thrown may leave the job stuck on "printing".
      try {
        error = await (_send ?? _toPrinter)(
          url,
          file,
          _settings.printFill,
        ).then<String?>((v) => v).timeout(printTimeout, onTimeout: () => _timeoutError);
      } catch (e) {
        error = '$e';
      }
      job.attempts++;
    }
    final retryable = error != null && url != null && error != _timeoutError && job.attempts > 0;
    if (error == null) {
      job
        ..status = JobStatus.done
        ..error = null;
    } else if (retryable && job.attempts <= autoRetries) {
      job
        ..status = JobStatus.waiting
        ..error = '$error · tự thử lại (${job.attempts}/$autoRetries)'
        ..held = true;
      late final Timer t;
      t = Timer(retryBase * (1 << (job.attempts - 1)), () {
        _retryTimers.remove(t);
        job.held = false;
        _pump();
      });
      _retryTimers.add(t);
    } else {
      job
        ..status = JobStatus.failed
        ..error = error;
    }
    printerOk = error == null;
    _busy = false;
    _save();
    _pump();
  }
}
