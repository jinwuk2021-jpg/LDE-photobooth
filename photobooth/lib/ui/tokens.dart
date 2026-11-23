import 'package:flutter/painting.dart';

/// Lensly's flea-market palette (Lensly lib/core/tokens.dart). Nothing is pure white or pure black.
abstract final class Palette {
  static const paper = Color(0xFFEFE6D0);
  static const paperDeep = Color(0xFFE2D3B0);
  static const kraft = Color(0xFFC49A6C);
  static const coffee = Color(0xFF4A3426);
  static const charcoal = Color(0xFF2A2420);
  static const moss = Color(0xFF5E6B4E);
  static const brick = Color(0xFFA8543E);
  static const brickInk = Color(0xFF8F4433);
  static const mustard = Color(0xFFC99A3B);
  static const brass = Color(0xFFB8893A);
  static const shadow = Color(0xFF1E1A16);
  static const flash = Color(0xFFFFFBF2);
  static const kraftInk = Color(0xFF74512F);

  /// The print's paper: lighter than [paper] so photos stay bright on the SELPHY.
  static const printPaper = Color(0xFFFAF5EA);
}

abstract final class Fonts {
  /// Handwritten titles (Vietnamese coverage checked in Lensly).
  static const hand = 'PatrickHand';

  /// Typewriter labels and dates.
  static const mono = 'SpaceMono';
}

/// Sizes for a 11" iPad seen from a step away: everything big.
abstract final class TextStyles {
  static const hero = TextStyle(fontFamily: Fonts.hand, fontSize: 72, color: Palette.coffee, height: 1.05);
  static const title = TextStyle(fontFamily: Fonts.hand, fontSize: 44, color: Palette.coffee, height: 1.1);
  static const button = TextStyle(fontFamily: Fonts.hand, fontSize: 34, color: Palette.paper, height: 1.1);
  static const body = TextStyle(fontFamily: Fonts.mono, fontSize: 18, color: Palette.coffee, height: 1.35);
  static const label = TextStyle(fontFamily: Fonts.mono, fontSize: 14, letterSpacing: 0.6, color: Palette.coffee);
}
