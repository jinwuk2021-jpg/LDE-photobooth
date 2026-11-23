import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../camera/skin_smooth.dart';

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

  /// Seconds a guest has to pick the photos before the booth picks and prints.
  int get pickSeconds => _prefs.getInt('pickSeconds') ?? 60;
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
  bool get printFill => _prefs.getBool('printFill') ?? true;
  set printFill(bool v) {
    _prefs.setBool('printFill', v);
    notifyListeners();
  }

  /// Lift for the printer copy, in percent (0, 5, 10, 15).
  int get printBrighten => _prefs.getInt('printBrighten') ?? 0;
  set printBrighten(int v) {
    _prefs.setInt('printBrighten', v);
    notifyListeners();
  }

  /// Turn 4 Cut the other way for the printer.
  bool get turnCounterClockwise => _prefs.getBool('turnCcw') ?? false;
  set turnCounterClockwise(bool v) {
    _prefs.setBool('turnCcw', v);
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
