import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../camera/booth_camera.dart';
import '../camera/filters.dart';
import '../config.dart';
import '../services/printer.dart';
import '../services/settings.dart';
import '../services/upload_queue.dart';
import 'print_layout.dart';

/// One guest, from picking a frame to pressing "In".
class GuestSession extends ChangeNotifier {
  GuestSession(this.layout);

  final BoothLayout layout;
  final List<Shot> shots = [];

  /// Shot indexes in tap order = order on the print.
  final List<int> picks = [];

  bool get complete => picks.length == layout.picks;

  void toggle(int index) {
    if (picks.contains(index)) {
      picks.remove(index);
    } else if (picks.length < layout.picks) {
      picks.add(index);
    }
    notifyListeners();
  }

  /// Time is up: the first shots not picked yet fill the remaining places.
  void fillPicks() {
    for (var i = 0; i < shots.length && !complete; i++) {
      if (!picks.contains(i)) picks.add(i);
    }
    notifyListeners();
  }
}

/// What the thank-you screen shows.
class Finished {
  const Finished(this.url, this.printPath, this.aspect);
  final String url;

  /// The card as designed (landscape for 4 Cut).
  final String printPath;
  final double aspect;
}

/// The booth's services, created once in main().
class Booth {
  Booth({
    required this.docs,
    required this.settings,
    required this.camera,
    required this.uploads,
    required this.prints,
  });

  final Directory docs;
  final BoothSettings settings;
  final BoothCamera camera;
  final UploadQueue uploads;
  final PrintQueue prints;

  static const _idAlphabet = 'abcdefghjkmnpqrstuvwxyz23456789'; // same ids as the Worker (no 0/o, 1/l/i)

  static String newSessionId() {
    final r = Random.secure();
    return List.generate(12, (_) => _idAlphabet[r.nextInt(_idAlphabet.length)]).join();
  }

  /// Event picture on the start screen, picked in admin (or replaced from the Files app).
  File get startImage => File(p.join(docs.path, 'Booth', 'anh-man-cho.jpg'));

  /// Bumped when [startImage] changes, so the start screen reloads it.
  final startImageVersion = ValueNotifier<int>(0);

  Future<void> setStartImage(String? pickedPath) async {
    if (pickedPath == null) {
      if (startImage.existsSync()) startImage.deleteSync();
    } else {
      startImage.parent.createSync(recursive: true);
      await File(pickedPath).copy(startImage.path);
    }
    startImageVersion.value++;
  }

  String linkFor(String id) => '${SHARE_API_URL.replaceAll(RegExp(r'/+$'), '')}/b/$id';

  /// `Documents/Booth/<yyyy-MM-dd>/<HH-mm-ss>/` (visible in the Files app).
  Directory _sessionDir(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final day = '${t.year}-${two(t.month)}-${two(t.day)}';
    var time = '${two(t.hour)}-${two(t.minute)}-${two(t.second)}';
    var dir = Directory(p.join(docs.path, 'Booth', day, time));
    for (var n = 2; dir.existsSync(); n++) {
      dir = Directory(p.join(docs.path, 'Booth', day, '$time-$n'));
    }
    return dir..createSync(recursive: true);
  }

  /// [guest]'s shots through [filter] (in shot order).
  Future<List<ui.Image>> developAll(GuestSession guest, BoothFilter filter) async => [
    for (final (i, s) in guest.shots.indexed) await camera.develop(await s.base, filter, '$i'),
  ];

  /// "In": renders the print with a fresh link's QR, queues it for printing and
  /// uploading straight away, then saves the photos; the clips are exported and
  /// queued in the background. [developed] is [developAll] for the chosen filter.
  Future<Finished> finish(GuestSession guest, BoothFilter filter, List<ui.Image> developed) async {
    final id = newSessionId();
    final url = linkFor(id);
    final dir = _sessionDir(DateTime.now());
    final title = settings.title;
    File(p.join(dir.path, 'link.txt')).writeAsStringSync('$url\n');

    final photos = [for (final i in guest.picks) developed[i]];
    final printImage = await renderPrint(
      PrintSpec(layout: guest.layout, photos: photos, title: title, dateLine: settings.dateLine, qrUrl: url),
    );
    final printPath = await camera.saveJpeg(printImage, p.join(dir.path, 'print.jpg'), quality: 95);
    if (!PRINTING) {
      // Printing is off for now: saved and uploaded only.
    } else if (guest.layout.landscape) {
      // The SELPHY takes portrait postcards: a turned copy goes to the printer.
      final turned = await forPrinter(printImage);
      prints.add(await camera.saveJpeg(turned, p.join(dir.path, 'print_may_in.jpg'), quality: 95));
      turned.dispose();
    } else {
      prints.add(printPath);
    }
    printImage.dispose();
    uploads.add(id, 'print.jpg', printPath, title);
    // Where each photo sits on the print, so the page plays the clips in their windows.
    final layoutPath = p.join(dir.path, 'layout.json');
    File(layoutPath).writeAsStringSync(jsonEncode(layoutJson(guest.layout)));
    uploads.add(id, 'layout.json', layoutPath, title);
    _toPhotos(printPath);

    for (final (k, img) in photos.indexed) {
      final path = await camera.saveJpeg(img, p.join(dir.path, '${k + 1}.jpg'));
      uploads.add(id, '${k + 1}.jpg', path, title);
    }
    unawaited(_clips(guest, filter, id, dir, title));
    return Finished(url, printPath, guest.layout.size.aspectRatio);
  }

  Future<void> _clips(GuestSession guest, BoothFilter filter, String id, Directory dir, String title) async {
    try {
      for (final (k, i) in guest.picks.indexed) {
        final out = await camera.exportClip(guest.shots[i], filter, p.join(dir.path, '${k + 1}.mp4'));
        if (out != null) uploads.add(id, '${k + 1}.mp4', out, title);
      }
    } finally {
      discard(guest);
    }
  }

  /// Copies the print (with its QR) into the iPad's Photos app, album [PHOTOS_ALBUM]. Photos and
  /// clips stay in the cloud and the Files app only. Needs the Photos permission asked at launch;
  /// without it the print still lands in the library, outside the album.
  void _toPhotos(String path) {
    unawaited(camera.cam.saveToLibrary(path: path, isVideo: false, album: PHOTOS_ALBUM).catchError((_) => false));
  }

  /// Frees a guest's raw files, clip segments and images.
  void discard(GuestSession guest) {
    camera.release(guest.shots);
    for (final s in guest.shots) {
      s.base.then((img) => img.dispose(), onError: (_) {});
    }
    guest.shots.clear();
  }
}

/// layout.json for the Worker: the card's width / height and each photo window as
/// [x, y, w, h] fractions of the card.
Map<String, Object> layoutJson(BoothLayout layout) {
  final size = layout.size;
  double f(double v) => double.parse(v.toStringAsFixed(4));
  return {
    'aspect': f(size.aspectRatio),
    'rects': [
      for (final r in PrintGeometry.of(layout).cells)
        [f(r.left / size.width), f(r.top / size.height), f(r.width / size.width), f(r.height / size.height)],
    ],
  };
}
