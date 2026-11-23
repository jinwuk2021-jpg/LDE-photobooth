import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'booth/booth.dart';
import 'booth/print_layout.dart';
import 'camera/booth_camera.dart';
import 'config.dart';
import 'screens/idle_screen.dart';
import 'screens/layout_screen.dart';
import 'screens/pick_screen.dart';
import 'screens/shoot_screen.dart';
import 'screens/thanks_screen.dart';
import 'services/printer.dart';
import 'services/settings.dart';
import 'services/upload_queue.dart';
import 'ui/lux.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  // No status bar, home indicator hidden (the screen also never locks: AppDelegate).
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final prefs = await SharedPreferences.getInstance();
  final docs = await getApplicationDocumentsDirectory();
  final support = await getApplicationSupportDirectory();
  final settings = BoothSettings(prefs);
  final booth = Booth(
    docs: docs,
    settings: settings,
    camera: BoothCamera(),
    uploads: UploadQueue(docs: docs, stateFile: File(p.join(support.path, 'upload_queue.json')))..load(),
    prints: PrintQueue(prefs, settings, docs)..load(),
  );
  // Playfair Display + Be Vietnam Pro (fetched once, then cached by google_fonts).
  await LuxFonts.warmUp();
  runApp(BoothApp(booth: booth));
}

class BoothApp extends StatelessWidget {
  const BoothApp({super.key, required this.booth});
  final Booth booth;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Photobooth',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: Lux.champagne, brightness: Brightness.dark, surface: const Color(0xFF14121E)),
        scaffoldBackgroundColor: Lux.night,
      ),
      home: Home(booth: booth),
    );
  }
}

enum Stage { starting, noCamera, idle, layout, shoot, pick, thanks }

/// The guest flow: start → frame → 6 shots → pick 4 → thanks → start.
class Home extends StatefulWidget {
  const Home({super.key, required this.booth});
  final Booth booth;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Stage _stage = Stage.starting;
  GuestSession? _guest;
  Finished? _finished;
  Timer? _idle;

  Booth get booth => widget.booth;

  @override
  void initState() {
    super.initState();
    _openCamera();
  }

  Future<void> _openCamera() async {
    final tmp = Directory(p.join((await getTemporaryDirectory()).path, 'booth'))..createSync(recursive: true);
    final ok = await booth.camera.init(tmp);
    if (mounted) setState(() => _stage = ok ? Stage.idle : Stage.noCamera);
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  void _go(Stage stage) {
    setState(() => _stage = stage);
    _touch();
  }

  /// Any touch restarts the 60 s timer on the frame picker (the photo picker has its own limit).
  void _touch() {
    _idle?.cancel();
    if (_stage == Stage.layout) _idle = Timer(IDLE_TIMEOUT, _reset);
  }

  /// Back to the start screen, dropping the current guest's shots.
  void _reset() {
    final g = _guest;
    // After "In" the shots belong to the clip export, which frees them.
    if (g != null && _stage != Stage.thanks) booth.discard(g);
    _guest = null;
    _finished = null;
    _go(Stage.idle);
  }

  void _startShooting(BoothLayout layout) {
    _guest = GuestSession(layout);
    _go(Stage.shoot);
  }

  void _retake() {
    final layout = _guest!.layout;
    booth.discard(_guest!);
    _startShooting(layout);
  }

  @override
  Widget build(BuildContext context) {
    final screen = switch (_stage) {
      Stage.starting => const Center(child: CircularProgressIndicator(color: Lux.champagne)),
      Stage.noCamera => Center(
        child: Text(
          'Chưa có quyền camera.\nVào Cài đặt → Photobooth → bật Camera, rồi mở lại app.',
          textAlign: TextAlign.center,
          style: LuxFonts.serif(size: 32),
        ),
      ),
      Stage.idle => IdleScreen(booth: booth, onStart: () => _go(Stage.layout)),
      Stage.layout => LayoutScreen(settings: booth.settings, onPick: _startShooting, onBack: _reset),
      Stage.shoot => ShootScreen(
        key: ObjectKey(_guest),
        booth: booth,
        guest: _guest!,
        onDone: () => _go(Stage.pick),
        onFailed: _reset,
      ),
      Stage.pick => PickScreen(
        key: ObjectKey(_guest),
        booth: booth,
        guest: _guest!,
        onRetake: _retake,
        onPrinted: (f) {
          _finished = f;
          _go(Stage.thanks);
        },
      ),
      Stage.thanks => ThanksScreen(finished: _finished!, onDone: _reset),
    };
    return Scaffold(
      backgroundColor: Lux.night,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _touch(),
        // Fade + scale 1.02 → 1: 380 ms in, 200 ms out.
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          reverseDuration: const Duration(milliseconds: 200),
          transitionBuilder: luxTransition,
          child: KeyedSubtree(key: ValueKey(_stage), child: screen),
        ),
      ),
    );
  }
}
