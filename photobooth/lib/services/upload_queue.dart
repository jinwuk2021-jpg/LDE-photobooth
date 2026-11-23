import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../config.dart';

/// One file waiting to go to `PUT /api/booth/<session>/<name>`.
class UploadItem {
  UploadItem({
    required this.session,
    required this.name,
    required this.path,
    required this.title,
    required this.created,
    this.attempts = 0,
    DateTime? nextAt,
    this.error,
  }) : nextAt = nextAt ?? created;

  factory UploadItem.fromJson(Map<String, Object?> j) => UploadItem(
    session: j['session']! as String,
    name: j['name']! as String,
    path: j['path']! as String,
    title: j['title'] as String? ?? '',
    created: DateTime.parse(j['created']! as String),
    attempts: (j['attempts'] as num?)?.toInt() ?? 0,
    nextAt: DateTime.tryParse(j['nextAt'] as String? ?? ''),
    error: j['error'] as String?,
  );

  final String session;

  /// print.jpg, 1..4.jpg or 1..4.mp4.
  final String name;

  /// Relative to the documents directory (the iOS container path changes between installs).
  final String path;

  /// Event title, sent with print.jpg for the page heading.
  final String title;
  final DateTime created;
  int attempts;
  DateTime nextAt;
  String? error;

  /// Print first, then the photos, then the clips (oldest session first within each).
  int get priority => name == 'print.jpg' || name == 'layout.json' ? 0 : (name.endsWith('.jpg') ? 1 : 2);

  Map<String, Object?> toJson() => {
    'session': session,
    'name': name,
    'path': path,
    'title': title,
    'created': created.toIso8601String(),
    'attempts': attempts,
    'nextAt': nextAt.toIso8601String(),
    'error': error,
  };
}

/// Uploads one file at a time and retries forever (5 s, 15 s, 60 s, then every
/// 2 minutes). Saved to disk after every change, so it carries on after a relaunch.
class UploadQueue extends ChangeNotifier {
  UploadQueue({
    required this.docs,
    required this.stateFile,
    this.baseUrl = SHARE_API_URL,
    this.key = BOOTH_KEY,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final Directory docs;
  final File stateFile;
  final String baseUrl;

  /// The Worker's BOOTH_KEY.
  final String key;
  final http.Client _client;
  final List<UploadItem> _items = [];
  bool _busy = false;
  Timer? _timer;

  static const _backoff = [Duration(seconds: 5), Duration(seconds: 15), Duration(seconds: 60)];
  static const _later = Duration(minutes: 2);

  List<UploadItem> get items => List.unmodifiable(_items);

  /// Guests whose files are not all online yet.
  int get pendingSessions => _items.map((i) => i.session).toSet().length;

  /// Guests with at least one file that already failed once.
  int get failingSessions => _items.where((i) => i.attempts > 0).map((i) => i.session).toSet().length;

  String? get lastError => _items.map((i) => i.error).whereType<String>().firstOrNull;

  void load() {
    try {
      final list = jsonDecode(stateFile.readAsStringSync()) as List;
      _items.addAll(list.map((e) => UploadItem.fromJson((e as Map).cast<String, Object?>())));
    } catch (_) {}
    _pump();
  }

  void add(String session, String name, String absolutePath, String title) {
    _items.add(
      UploadItem(
        session: session,
        name: name,
        path: p.relative(absolutePath, from: docs.path),
        title: title,
        created: DateTime.now(),
      ),
    );
    _save();
    _pump();
  }

  /// Admin "Thử lại tất cả": everything is due now.
  void retryAll() {
    final now = DateTime.now();
    for (final i in _items) {
      i.nextAt = now;
    }
    _save();
    _pump();
  }

  void _save() {
    try {
      stateFile.parent.createSync(recursive: true);
      stateFile.writeAsStringSync(jsonEncode([for (final i in _items) i.toJson()]));
    } catch (_) {}
    notifyListeners();
  }

  UploadItem? _next() {
    final due = _items.where((i) => !i.nextAt.isAfter(DateTime.now())).toList()
      ..sort((a, b) => a.priority != b.priority ? a.priority - b.priority : a.created.compareTo(b.created));
    return due.firstOrNull;
  }

  void _pump() {
    if (_busy) return;
    _timer?.cancel();
    final item = _next();
    if (item == null) {
      if (_items.isEmpty) return;
      // Sleep until the earliest retry.
      final soonest = _items.map((i) => i.nextAt).reduce((a, b) => a.isBefore(b) ? a : b);
      _timer = Timer(soonest.difference(DateTime.now()) + const Duration(milliseconds: 50), _pump);
      return;
    }
    _busy = true;
    _send(item).whenComplete(() {
      _busy = false;
      _pump();
    });
  }

  Future<void> _send(UploadItem item) async {
    final file = File(p.join(docs.path, item.path));
    if (!file.existsSync()) {
      // Deleted from the Files app: nothing left to send.
      _items.remove(item);
      _save();
      return;
    }
    String? error;
    try {
      if (key.isEmpty) throw 'Chưa có BOOTH_KEY (build lại với booth_defines.json)';
      final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
      final res = await _client
          .put(
            Uri.parse('$base/api/booth/${item.session}/${item.name}'),
            headers: {
              'x-booth-key': key,
              'content-type': switch (p.extension(item.name)) {
                '.mp4' => 'video/mp4',
                '.json' => 'application/json',
                _ => 'image/jpeg',
              },
              if (item.name == 'print.jpg' && item.title.isNotEmpty) 'x-booth-title': Uri.encodeComponent(item.title),
            },
            body: await file.readAsBytes(),
          )
          .timeout(const Duration(minutes: 2));
      if (res.statusCode != 201) error = 'Máy chủ trả lỗi ${res.statusCode}';
    } on TimeoutException {
      error = 'Hết thời gian chờ';
    } on SocketException {
      error = 'Không có mạng';
    } catch (e) {
      error = '$e';
    }
    if (error == null) {
      _items.remove(item);
    } else {
      item.error = error;
      item.nextAt = DateTime.now().add(item.attempts < _backoff.length ? _backoff[item.attempts] : _later);
      item.attempts++;
    }
    _save();
  }
}
