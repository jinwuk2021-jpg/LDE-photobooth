import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Paper of a built-in frame (the design has every cut on ivory and on black).
enum Paper { ivory, black }

/// One print frame, as in `frame.json` (spec §3.2): the card's size, the photo windows in
/// tap order, the QR square. Built-ins are drawn in code (so the title, date line and the
/// scan hint in the guest's language stay live); custom frames are a PNG with transparent
/// holes ([overlay]) laid over the photos.
class BoothFrame {
  const BoothFrame({
    required this.id,
    required this.name,
    required this.size,
    required this.slots,
    required this.qr,
    this.builtIn = false,
    this.paper = Paper.ivory,
    this.enabledByDefault = true,
    this.overlay,
  });

  factory BoothFrame.fromJson(Map<String, dynamic> j, {ui.Image? overlay}) {
    Rect rect(Map<String, dynamic> r) => Rect.fromLTWH(
      (r['x'] as num).toDouble(),
      (r['y'] as num).toDouble(),
      (r['w'] as num).toDouble(),
      (r['h'] as num).toDouble(),
    );
    final size = (j['size'] as List).cast<num>();
    final qr = j['qr'] as Map<String, dynamic>;
    final q = (qr['size'] as num).toDouble();
    return BoothFrame(
      id: j['id'] as String,
      name: j['name'] as String? ?? j['id'] as String,
      size: Size(size[0].toDouble(), size[1].toDouble()),
      slots: [for (final s in (j['slots'] as List).cast<Map<String, dynamic>>()) rect(s)],
      qr: Rect.fromLTWH((qr['x'] as num).toDouble(), (qr['y'] as num).toDouble(), q, q),
      builtIn: j['builtIn'] == true,
      paper: j['paper'] == 'black' ? Paper.black : Paper.ivory,
      enabledByDefault: j['enabled'] != false,
      overlay: overlay,
    );
  }

  final String id;

  /// As saved ("2 Cut Ngà"); custom frames show it to guests.
  final String name;

  /// 1200 × 1776 (portrait) or 1776 × 1200 (landscape), ≈300 dpi on a 100 × 148 mm postcard.
  final Size size;

  /// Photo windows, in print order (= the order the guest taps).
  final List<Rect> slots;
  final Rect qr;
  final bool builtIn;
  final Paper paper;
  final bool enabledByDefault;

  /// Custom frames: the PNG drawn over the photos (null for built-ins).
  final ui.Image? overlay;

  /// Photos the guest picks.
  int get picks => slots.length;

  /// Shots taken: the windows plus [SPARE_SHOTS] to choose from (2 Cut → 4, 6 Cut → 8).
  int get shots => picks + SPARE_SHOTS;

  bool get landscape => size.width > size.height;

  /// Black card with light-gold ink (built-ins).
  bool get dark => paper == Paper.black;

  /// Big name on the frame card: "2 Cut" for built-ins (paper goes in the hint), else the saved name.
  String get label => builtIn ? '$picks Cut' : name;

  /// Width / height of the first photo window (the camera crops every shot to it).
  double get cellAspect => slots.first.size.aspectRatio;

  Map<String, Object> toJson({bool enabled = true}) {
    int r(double v) => v.round();
    return {
      'id': id,
      'name': name,
      'orientation': landscape ? 'landscape' : 'portrait',
      'size': [r(size.width), r(size.height)],
      'slots': [
        for (final s in slots) {'x': r(s.left), 'y': r(s.top), 'w': r(s.width), 'h': r(s.height)},
      ],
      'qr': {'x': r(qr.left), 'y': r(qr.top), 'size': r(qr.width)},
      'enabled': enabled,
      'builtIn': builtIn,
      if (builtIn) 'paper': paper.name,
    };
  }

  @override
  String toString() => 'BoothFrame($id)';
}

/// The built-in frames, in the order they are listed (`assets/frames/<id>/frame.json`).
const builtInFrameIds = [
  'lpe_2cut_ivory',
  'lpe_2cut_black',
  'lpe_3cut_ivory',
  'lpe_3cut_black',
  'lpe_4cut_black',
  'lpe_4cut_ivory',
  'lpe_6cut_ivory',
  'lpe_6cut_black',
];

/// Built-in frames (from the app's assets) and custom ones (`Documents/frames/<id>/`), with
/// which of them guests see. At least one always stays on.
class FrameStore extends ChangeNotifier {
  FrameStore(this._prefs, {this.docs});

  final SharedPreferences _prefs;

  /// Where custom frames live (`frames/<id>/frame.png + frame.json`). Null: built-ins only.
  final Directory? docs;

  List<BoothFrame> _all = const [];
  List<BoothFrame> get all => _all;

  static const _enabledKey = 'framesEnabled';

  /// Built-ins never change while the app runs: read once.
  List<BoothFrame>? _builtIns;

  Future<void> load({AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
    final frames = <BoothFrame>[
      ...(_builtIns ??= [
        for (final id in builtInFrameIds)
          BoothFrame.fromJson(
            jsonDecode(await assets.loadString('assets/frames/$id/frame.json')) as Map<String, dynamic>,
          ),
      ]),
    ];
    frames.addAll(await _loadCustom());
    _all = frames;
    notifyListeners();
  }

  /// Every `frames/*/frame.json` with its `frame.png`; broken ones are skipped.
  Future<List<BoothFrame>> _loadCustom() async {
    final root = customRoot;
    if (root == null || !root.existsSync()) return const [];
    final out = <BoothFrame>[];
    final dirs = root.listSync().whereType<Directory>().toList()..sort((a, b) => a.path.compareTo(b.path));
    for (final dir in dirs) {
      try {
        final json = File(p.join(dir.path, 'frame.json'));
        final png = File(p.join(dir.path, 'frame.png'));
        if (!json.existsSync() || !png.existsSync()) continue;
        final image = await decodePng(await png.readAsBytes());
        final j = jsonDecode(await json.readAsString()) as Map<String, dynamic>;
        out.add(BoothFrame.fromJson({...j, 'builtIn': false}, overlay: image));
      } catch (e) {
        debugPrint('frame ${dir.path}: $e');
      }
    }
    return out;
  }

  Directory? get customRoot => docs == null ? null : Directory(p.join(docs!.path, 'frames'));

  Set<String> get _enabledIds {
    final saved = _prefs.getStringList(_enabledKey);
    if (saved != null) return saved.toSet();
    return {
      for (final f in _all)
        if (f.enabledByDefault) f.id,
    };
  }

  bool isEnabled(BoothFrame f) => _enabledIds.contains(f.id);

  /// What guests choose from, in [all]'s order. Never empty once loaded.
  List<BoothFrame> get enabled {
    final ids = _enabledIds;
    final on = [
      for (final f in _all)
        if (ids.contains(f.id)) f,
    ];
    return on.isEmpty && _all.isNotEmpty ? [_all.first] : on;
  }

  /// Shows or hides [f] on the frame picker. Turning off the last one is refused (returns false).
  Future<bool> setEnabled(BoothFrame f, bool on) async {
    final ids = _enabledIds..removeWhere((id) => !_all.any((f) => f.id == id));
    if (on) {
      ids.add(f.id);
    } else {
      if (ids.length <= 1 && ids.contains(f.id)) return false;
      ids.remove(f.id);
    }
    await _prefs.setStringList(_enabledKey, [
      for (final x in _all)
        if (ids.contains(x.id)) x.id,
    ]);
    notifyListeners();
    return true;
  }

  /// A custom frame's PNG (`frames/<id>/frame.png`), null for built-ins.
  File? pngOf(BoothFrame f) => f.builtIn || customRoot == null ? null : File(p.join(customRoot!.path, f.id, 'frame.png'));

  /// Saves a custom frame (a new one when [id] is null), reloads, shows it to guests. Returns it.
  Future<BoothFrame> saveCustom({
    String? id,
    required String name,
    required Uint8List png,
    required Size card,
    required List<Rect> slots,
    required Rect qr,
  }) async {
    final root = customRoot;
    if (root == null) throw StateError('no documents folder');
    final newId = id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final dir = Directory(p.join(root.path, newId))..createSync(recursive: true);
    final frame = BoothFrame(id: newId, name: name, size: card, slots: slots, qr: qr);
    await File(p.join(dir.path, 'frame.png')).writeAsBytes(png, flush: true);
    await File(p.join(dir.path, 'frame.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(frame.toJson()),
      flush: true,
    );
    await load();
    final saved = byId(newId)!;
    await setEnabled(saved, true);
    return saved;
  }

  /// Deletes a custom frame's folder (built-ins cannot be deleted).
  Future<void> deleteCustom(BoothFrame f) async {
    if (f.builtIn || customRoot == null) return;
    final dir = Directory(p.join(customRoot!.path, f.id));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    await load();
  }

  BoothFrame? byId(String id) {
    for (final f in _all) {
      if (f.id == id) return f;
    }
    return null;
  }
}

Future<ui.Image> decodePng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}
