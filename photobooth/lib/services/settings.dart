import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../booth/print_layout.dart';
import '../camera/skin_smooth.dart';

/// Paper loaded in the printer (Settings → Máy in → Khổ giấy), portrait, in mm.
enum PrintPaper {
  postcard('Postcard', 100, 148),
  l2('2L', 127, 178),
  l('L', 89, 127);

  const PrintPaper(this.label, this.widthMm, this.heightMm);
  final String label;
  final double widthMm;
  final double heightMm;

  static PrintPaper byName(String? name) => values.firstWhere((v) => v.name == name, orElse: () => PrintPaper.postcard);
}

/// What the staff can change in the admin screen. Kept across launches.
class BoothSettings extends ChangeNotifier {
  BoothSettings(this._prefs);
  final SharedPreferences _prefs;

  String get title => _prefs.getString('title') ?? 'LPE Sum Up';
  set title(String v) => _set('title', v.trim());

  /// Shown with the date ("[date] · Tiệc tổng kết cuối năm") on the print and the start screen.
  String get subtitle => _prefs.getString('subtitle') ?? 'Tiệc tổng kết cuối năm';
  set subtitle(String v) => _set('subtitle', v.trim());

  /// The date line, e.g. "23.12.2026".
  String get dateLine => _prefs.getString('dateLine') ?? _today();
  set dateLine(String v) => _set('dateLine', v.trim());

  /// AirPrint printer picked once in the admin screen.
  String? get printerUrl => _prefs.getString('printerUrl');
  String? get printerName => _prefs.getString('printerName');
  Future<void> setPrinter(String url, String name) async {
    await _prefs.setString('printerUrl', url);
    await _prefs.setString('printerName', name);
    notifyListeners();
  }

  /// "Quên máy in này".
  Future<void> forgetPrinter() async {
    await _prefs.remove('printerUrl');
    await _prefs.remove('printerName');
    notifyListeners();
  }

  /// Cards printed per guest (1–3).
  /// "In thêm 1 tấm" on the thank-you screen: how many extra copies a guest may ask for
  /// (0 hides the button).
  int get extraPrintMax => (_prefs.getInt('extraPrintMax') ?? 1).clamp(0, 3);
  set extraPrintMax(int v) {
    _prefs.setInt('extraPrintMax', v.clamp(0, 3));
    notifyListeners();
  }

  int get printCopies => (_prefs.getInt('printCopies') ?? 1).clamp(1, 3);
  set printCopies(int v) {
    _prefs.setInt('printCopies', v.clamp(1, 3));
    notifyListeners();
  }

  /// Seconds a guest has to pick the photos before the booth picks and prints.
  int get pickSeconds => _prefs.getInt('pickSeconds') ?? 45;
  set pickSeconds(int v) {
    _prefs.setInt('pickSeconds', v);
    notifyListeners();
  }

  /// Print each card on the SELPHY. Off: the last button only saves, uploads and shows the QR.
  bool get printing => _prefs.getBool('printing') ?? true;
  set printing(bool v) {
    _prefs.setBool('printing', v);
    notifyListeners();
  }

  /// Picture covers the whole sheet (borderless) instead of fitting the printable area.
  /// The paper the printer is asked for (SELPHY: Postcard; photo printers: 2L / L).
  PrintPaper get printPaper => PrintPaper.byName(_prefs.getString('printPaper'));
  set printPaper(PrintPaper v) => _set('printPaper', v.name);

  bool get printFill => _prefs.getBool('printFill') ?? true;
  set printFill(bool v) {
    _prefs.setBool('printFill', v);
    notifyListeners();
  }

  /// Colour richness of the printer copy (SELPHY prints run pale). Default: Đậm.
  PrintColor get printColor => PrintColor.byName(_prefs.getString('printColor'));
  set printColor(PrintColor v) => _set('printColor', v.name);

  /// Brightness of the printer copy in percent (−10 … +10). A new key: the old "Làm sáng"
  /// (+5 / +10 %) also lifted the blacks and made prints milky, so it starts again from 0.
  int get printBrighten => _prefs.getInt('printLight') ?? 0;
  set printBrighten(int v) {
    _prefs.setInt('printLight', v);
    notifyListeners();
  }

  /// Turn 4 Cut the other way for the printer.
  bool get turnCounterClockwise => _prefs.getBool('turnCcw') ?? false;
  set turnCounterClockwise(bool v) {
    _prefs.setBool('turnCcw', v);
    notifyListeners();
  }

  /// Shoot with the Sony camera on the USB-C port when it is ready (the iPad camera otherwise).
  bool get externalCamera => _prefs.getBool('externalCamera') ?? true;
  set externalCamera(bool v) {
    _prefs.setBool('externalCamera', v);
    notifyListeners();
  }

  SkinSmooth get skin => SkinSmooth.byName(_prefs.getString('skin'));
  set skin(SkinSmooth v) => _set('skin', v.name);

  Future<void> _set(String key, String value) async {
    await _prefs.setString(key, value);
    notifyListeners();
  }

  static String _today() {
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }
}
