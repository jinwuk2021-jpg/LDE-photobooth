import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  /// [fill]: cover the whole sheet (borderless) instead of fitting the printable area.
  static Future<String?> printFile(String url, String path, {bool fill = true}) async {
    try {
      return await _ch.invokeMethod<String>('print', {'url': url, 'path': path, 'fill': fill});
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
  PrintJob({required this.path, required this.created, this.status = JobStatus.waiting, this.error});

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
  );

  /// The print JPEG, relative to the documents directory (`Booth/<day>/<time>/print.jpg`).
  final String path;
  final DateTime created;
  JobStatus status;
  String? error;

  Map<String, Object?> toJson() => {
    'path': path,
    'created': created.toIso8601String(),
    'status': status.name,
    'error': error,
  };
}

/// Sends prints one by one: the next job goes only after the previous one's completion handler ran.
class PrintQueue extends ChangeNotifier {
  PrintQueue(this._prefs, this._settings, this.docs);

  final SharedPreferences _prefs;
  final Directory docs;
  final BoothSettings _settings;
  final List<PrintJob> _jobs = [];
  bool _busy = false;

  /// Last result: null = nothing printed yet, true = ok, false = last job failed or printer unreachable.
  bool? printerOk;

  /// Newest first, the last 50.
  List<PrintJob> get jobs => _jobs.reversed.toList();
  int get failedCount => _jobs.where((j) => j.status == JobStatus.failed).length;

  void load() {
    try {
      final list = jsonDecode(_prefs.getString('printJobs') ?? '[]') as List;
      _jobs.addAll(list.map((e) => PrintJob.fromJson((e as Map).cast<String, Object?>())));
    } catch (_) {}
    _pump();
  }

  void add(String absolutePath) {
    _jobs.add(
      PrintJob(
        path: p.relative(absolutePath, from: docs.path),
        created: DateTime.now(),
      ),
    );
    _save();
    _pump();
  }

  /// Printing was switched on: send what is waiting.
  void resume() => _pump();

  void retry(PrintJob job) {
    job
      ..status = JobStatus.waiting
      ..error = null;
    _save();
    _pump();
  }

  /// Checks the printer is on the network (start screen badge).
  Future<void> check() async {
    if (!_settings.printing) return;
    final url = _settings.printerUrl;
    if (url == null || _busy) return;
    final ok = await PrinterChannel.reachable(url);
    if (ok != printerOk) {
      printerOk = ok;
      notifyListeners();
    }
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
    final job = _jobs.where((j) => j.status == JobStatus.waiting).firstOrNull;
    if (job == null) return;
    _busy = true;
    job.status = JobStatus.printing;
    _save();
    final url = _settings.printerUrl;
    final file = p.join(docs.path, job.path);
    final String? error;
    if (url == null) {
      error = 'Chưa chọn máy in';
    } else if (!File(file).existsSync()) {
      error = 'Không tìm thấy file ảnh in';
    } else {
      // A printer that never answers (out of paper, switched off mid-job) must not stop the queue.
      error = await PrinterChannel.printFile(
        url,
        file,
        fill: _settings.printFill,
      ).timeout(const Duration(minutes: 3), onTimeout: () => 'Máy in không phản hồi sau 3 phút');
    }
    job
      ..status = error == null ? JobStatus.done : JobStatus.failed
      ..error = error;
    printerOk = error == null;
    _busy = false;
    _save();
    _pump();
  }
}
