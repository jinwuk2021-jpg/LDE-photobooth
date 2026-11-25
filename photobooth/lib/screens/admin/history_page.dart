import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../booth/booth.dart';
import '../../services/printer.dart';
import '../../ui/lux.dart';
import 'kit.dart';

/// One guest's folder: `Booth/<yyyy-MM-dd>/<HH-mm-ss>/` with its print.
class SessionEntry {
  SessionEntry(this.dir, this.number, this.time, this.cuts, this.id, this.bytes);
  final Directory dir;

  /// Space the folder takes on the iPad.
  final int bytes;

  /// "Lượt 42": order among all sessions on this iPad.
  final int number;
  final DateTime time;

  /// Photo windows on the card (from layout.json), null when unknown.
  final int? cuts;

  /// Share id (from link.txt).
  final String? id;

  File get print => File(p.join(dir.path, 'print.jpg'));
  File get printerCopy => File(p.join(dir.path, 'print_may_in.jpg'));

  static final _day = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final _time = RegExp(r'^(\d{2})-(\d{2})-(\d{2})(-\d+)?$');

  /// Every session with a print, newest first.
  static List<SessionEntry> scan(Directory docs) {
    final root = Directory(p.join(docs.path, 'Booth'));
    if (!root.existsSync()) return const [];
    final found = <(DateTime, Directory)>[];
    for (final day in root.listSync().whereType<Directory>()) {
      final d = p.basename(day.path);
      if (!_day.hasMatch(d)) continue;
      for (final s in day.listSync().whereType<Directory>()) {
        final m = _time.firstMatch(p.basename(s.path));
        if (m == null || !File(p.join(s.path, 'print.jpg')).existsSync()) continue;
        final t = DateTime.tryParse('${d}T${m[1]}:${m[2]}:${m[3]}');
        if (t != null) found.add((t, s));
      }
    }
    found.sort((a, b) => a.$1.compareTo(b.$1) != 0 ? a.$1.compareTo(b.$1) : a.$2.path.compareTo(b.$2.path));
    return [
      for (final (i, (t, dir)) in found.indexed) SessionEntry(dir, i + 1, t, _cuts(dir), _id(dir), _bytes(dir)),
    ].reversed.toList();
  }

  static int _bytes(Directory dir) {
    var n = 0;
    try {
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        n += f.lengthSync();
      }
    } catch (_) {}
    return n;
  }

  static int? _cuts(Directory dir) {
    try {
      final j = jsonDecode(File(p.join(dir.path, 'layout.json')).readAsStringSync()) as Map;
      return (j['rects'] as List).length;
    } catch (_) {
      return null;
    }
  }

  static String? _id(Directory dir) {
    try {
      return File(p.join(dir.path, 'link.txt')).readAsStringSync().trim().split('/').last;
    } catch (_) {
      return null;
    }
  }
}

/// 7e · Cài đặt – Lịch sử & in lại.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.booth});
  final Booth booth;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  static const _shown = 40;
  late List<SessionEntry> _sessions = SessionEntry.scan(widget.booth.docs);
  int _seenJobs = 0;

  Booth get b => widget.booth;

  /// "In lại": the printer copy (made now when printing was off for that guest).
  Future<void> _reprint(SessionEntry s) async {
    if (!b.settings.printing || b.settings.printerUrl == null) {
      showToast(context, 'Chưa bật in hoặc chưa chọn máy in', icon: Icons.error_outline);
      return;
    }
    var copy = s.printerCopy;
    if (!copy.existsSync()) {
      final codec = await ui.instantiateImageCodec(await s.print.readAsBytes());
      final card = (await codec.getNextFrame()).image;
      codec.dispose();
      copy = File(await b.printerCopy(card, copy.path));
      card.dispose();
    }
    b.prints.add(copy.path);
    if (mounted) showToast(context, 'Đã gửi in lại lượt ${s.number}', icon: Icons.print_outlined);
  }

  void _retryErrors() {
    final failed = b.prints.failedCount;
    final uploads = b.uploads.failingSessions;
    b.prints.retryFailed();
    b.uploads.retryAll();
    showToast(
      context,
      failed + uploads == 0 ? 'Không có lỗi nào' : 'Đang thử lại: $failed lệnh in, $uploads lượt upload',
      icon: Icons.refresh,
    );
  }

  static String _size(int bytes) =>
      bytes >= 1 << 30 ? '${(bytes / (1 << 30)).toStringAsFixed(1)} GB' : '${(bytes / (1 << 20)).toStringAsFixed(bytes < 10 << 20 ? 1 : 0)} MB';

  /// Every file of this guest is on the server (the page and its QR keep working without the iPad).
  bool _online(SessionEntry s) => s.id != null && !b.uploads.isPending(s.id!);

  /// A print of it is going or waiting: deleting would lose it.
  bool _printing(SessionEntry s, List<PrintJob> jobs) {
    final rel = p.relative(s.printerCopy.path, from: b.docs.path);
    return jobs.any((j) => j.path == rel && (j.status == JobStatus.printing || j.status == JobStatus.waiting));
  }

  Future<bool> _confirm(String title, String text, String action) async =>
      await showSheet<bool>(
        context,
        title: title,
        body: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(text, style: LuxFonts.sans(size: 18, color: Lux.ivoryA(0.8))),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: LineButton(label: 'Huỷ', height: 56, fontSize: 18, onPressed: () => Navigator.of(context).pop(false)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: GoldButton(
                    label: action,
                    icon: Icons.delete_outline,
                    height: 56,
                    fontSize: 18,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ) ??
      false;

  void _deleteAll(List<SessionEntry> list) {
    for (final s in list) {
      try {
        b.deleteSession(s.dir, s.id);
      } catch (_) {}
    }
    setState(() => _sessions = SessionEntry.scan(b.docs));
  }

  Future<void> _delete(SessionEntry s) async {
    final online = _online(s);
    final ok = await _confirm(
      'Xoá lượt ${s.number}?',
      'Ảnh, video và bản in của lượt này sẽ bị xoá khỏi iPad (${_size(s.bytes)}). '
          '${online ? 'Trang web và mã QR của khách vẫn dùng được, bản in vẫn còn trong app Ảnh.' : 'Lượt này CHƯA lên web hết: khách sẽ không xem đủ ảnh / video qua mã QR.'}',
      'Xoá',
    );
    if (!ok || !mounted) return;
    _deleteAll([s]);
    showToast(context, 'Đã xoá lượt ${s.number}', icon: Icons.delete_outline);
  }

  /// "Dọn máy": every guest already online and not printing.
  Future<void> _cleanUp() async {
    final jobs = b.prints.jobs;
    final list = _sessions.where((s) => _online(s) && !_printing(s, jobs)).toList();
    if (list.isEmpty) {
      showToast(context, 'Chưa có lượt nào lên web hết để xoá', icon: Icons.info_outline);
      return;
    }
    final bytes = list.fold<int>(0, (n, s) => n + s.bytes);
    final ok = await _confirm(
      'Dọn máy',
      'Xoá ${list.length} lượt đã lên web hết khỏi iPad, giải phóng ${_size(bytes)}. '
          'Trang web và mã QR của khách vẫn dùng được, bản in vẫn còn trong app Ảnh. '
          'Lượt chưa lên web hoặc đang chờ in được giữ lại.',
      'Xoá ${list.length} lượt',
    );
    if (!ok || !mounted) return;
    _deleteAll(list);
    showToast(context, 'Đã xoá ${list.length} lượt · ${_size(bytes)}', icon: Icons.delete_outline);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([b.prints, b.uploads]),
      builder: (context, _) {
        // A new guest (or a reprint) since the page opened: look at the folders again.
        if (b.prints.jobs.length != _seenJobs) {
          _seenJobs = b.prints.jobs.length;
          _sessions = SessionEntry.scan(b.docs);
        }
        final jobs = b.prints.jobs;
        final printing = jobs.where((j) => j.status == JobStatus.printing).length;
        final failed = b.prints.failedCount;
        final pendingUp = b.uploads.pendingSessions;
        final waitingUp = {for (final i in b.uploads.items) i.session};
        return ListView(
          padding: const EdgeInsets.fromLTRB(0, 40, 0, 40),
          children: [
            PageHeader(
              title: 'Lịch sử in',
              subtitle: Text(
                'Bấm "In lại" để in thêm bản của lượt bất kỳ · ${_sessions.length} lượt trên iPad này'
                '${_sessions.isEmpty ? '' : ' · ${_size(_sessions.fold<int>(0, (n, s) => n + s.bytes))}'}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (printing > 0) ...[StatusPill('$printing đang in', PillKind.wait), const SizedBox(width: 10)],
                  if (failed > 0) ...[StatusPill('$failed lỗi', PillKind.bad), const SizedBox(width: 10)],
                  StatusPill(
                    pendingUp == 0 ? 'Đã lên web hết' : '$pendingUp chờ upload',
                    pendingUp == 0 ? PillKind.ok : PillKind.wait,
                  ),
                  const SizedBox(width: 14),
                  LineButton(
                    label: 'Dọn máy',
                    icon: Icons.cleaning_services_outlined,
                    width: 170,
                    height: 56,
                    fontSize: 18,
                    onPressed: _sessions.isEmpty ? null : _cleanUp,
                  ),
                  const SizedBox(width: 10),
                  GoldButton(
                    label: 'Thử lại lỗi',
                    icon: Icons.refresh,
                    width: 196,
                    height: 56,
                    fontSize: 18,
                    onPressed: failed > 0 || b.uploads.failingSessions > 0 ? _retryErrors : null,
                  ),
                ],
              ),
            ),
            if (b.uploads.lastError != null) ...[
              const SizedBox(height: 12),
              AlertBox(Text('Upload đang lỗi: ${b.uploads.lastError}. App tự thử lại, ảnh vẫn nằm an toàn trên iPad.')),
            ],
            const SizedBox(height: 24),
            if (_sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Center(child: Text('Chưa có lượt chụp nào.', style: hintStyle(size: 18))),
              )
            else
              LayoutBuilder(
                builder: (context, box) {
                  const gap = 20.0;
                  final w = (box.maxWidth - 3 * gap) / 4;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final s in _sessions.take(_shown))
                        SizedBox(
                          width: w,
                          child: _SessionCard(
                            session: s,
                            status: _status(s, jobs),
                            uploading: s.id != null && waitingUp.contains(s.id),
                            onReprint: () => _reprint(s),
                            onDelete: _printing(s, jobs) ? null : () => _delete(s),
                          ),
                        ),
                    ],
                  );
                },
              ),
            if (_sessions.length > _shown)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(
                  'Hiện $_shown lượt mới nhất. Các lượt cũ hơn xem trong app Tệp → Photobooth → Booth.',
                  style: hintStyle(),
                ),
              ),
          ],
        );
      },
    );
  }

  (String, PillKind) _status(SessionEntry s, List<PrintJob> jobs) {
    final rel = p.relative(s.printerCopy.path, from: b.docs.path);
    final mine = jobs.where((j) => j.path == rel).toList();
    final done = mine.where((j) => j.status == JobStatus.done).length;
    if (mine.any((j) => j.status == JobStatus.printing)) return ('Đang in…', PillKind.wait);
    if (mine.any((j) => j.status == JobStatus.waiting)) {
      return (done > 0 ? 'Đã in ×$done · chờ thêm' : 'Chờ máy in', PillKind.wait);
    }
    if (done > 0) return ('Đã in ×$done', PillKind.ok);
    if (mine.any((j) => j.status == JobStatus.failed)) return ('Lỗi – chưa in', PillKind.bad);
    return ('Chưa in', PillKind.none);
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.status,
    required this.uploading,
    required this.onReprint,
    required this.onDelete,
  });
  final SessionEntry session;
  final (String, PillKind) status;
  final bool uploading;
  final VoidCallback onReprint;

  /// Null while a print of it is going or waiting.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = session.time;
    final today = DateUtils.isSameDay(t, DateTime.now());
    return Glass(
      radius: 22,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 150,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withValues(alpha: 0.03),
            ),
            child: Center(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 16, offset: Offset(0, 6))],
                ),
                child: Image.file(session.print, cacheHeight: 300, fit: BoxFit.contain),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!today) Text('${two(t.day)}/${two(t.month)}/${t.year}', style: hintStyle(size: 13)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${two(t.hour)}:${two(t.minute)}', style: LuxFonts.sans(size: 20, weight: FontWeight.w600)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    'Lượt ${session.number}',
                    if (session.cuts != null) '${session.cuts} Cut',
                  ].join(' · '),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: LuxFonts.sans(size: 15, color: Lux.ivoryA(0.6)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusPill(status.$1, status.$2, small: true),
              if (uploading) const StatusPill('chờ upload', PillKind.wait, small: true),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: LineButton(
                  label: 'In lại',
                  icon: Icons.print_outlined,
                  width: double.infinity,
                  height: 48,
                  fontSize: 17,
                  onPressed: onReprint,
                ),
              ),
              const SizedBox(width: 10),
              Opacity(
                opacity: onDelete == null ? 0.35 : 1,
                child: RoundIconButton(Icons.delete_outline, tooltip: 'Xoá lượt này', onTap: onDelete),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
