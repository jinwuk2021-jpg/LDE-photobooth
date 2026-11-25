// LPE Sum Up – Photobooth · design tokens
// Generated from the Claude Design canvas. Units are iPad logical points (1194×834 landscape).
// Keep this file the single source of truth for colors, type, motion and filters.

import 'dart:ui' show ImageFilter;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

class LpeColors {
  static const night = Color(0xFF0B0B12); // main background
  static const navy = Color(0xFF141A33); // gradient, 3 Cut band
  static const champagne = Color(0xFFD4AF6A); // borders, icons, accents
  static const champagneLight = Color(0xFFF5E1A4); // highlight, selected ring
  static const goldDeep = Color(0xFF9C7A3F); // metal shadow, gold on ivory
  static const ivory = Color(0xFFF8F3E8); // primary text, print paper
  static const rose = Color(0xFFE9C7C0); // eyebrows, secondary labels, bokeh
  static const urgent = Color(0xFFE0525A); // timer ≤ 10 s (text 0xFFFFB3B7)
  static const urgentText = Color(0xFFFFB3B7);
  static const amber = Color(0xFFE8B04A); // upload pending
  static const ok = Color(0xFF8FD3A8); // printer ready
  static const glass = Color(0xA614121E); // dark glass fill (+ blur 18)
  static const textMuted = Color(0xB3F8F3E8); // ivory @ 70%
}

class LpeGradients {
  /// Metal gold for text & hairlines. Use 220% width + slide for the shimmer.
  static const metal = LinearGradient(
    begin: Alignment(-1, -0.18),
    end: Alignment(1, 0.18), // ≈100°
    colors: [
      Color(0xFF9C7A3F),
      Color(0xFFD4AF6A),
      Color(0xFFF5E1A4),
      Color(0xFFFFF6DA),
      Color(0xFFF5E1A4),
      Color(0xFFD4AF6A),
      Color(0xFF9C7A3F),
    ],
    stops: [0, .22, .45, .50, .55, .78, 1],
  );

  /// Gold button fill (top → bottom).
  static const button = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF5E1A4), Color(0xFFE6C886), Color(0xFFD4AF6A), Color(0xFFB8914F)],
    stops: [0, .40, .70, 1],
  );

  /// Gold for print on ivory paper (darker, reads on dye-sub).
  static const inkOnIvory = LinearGradient(
    colors: [Color(0xFF6E5223), Color(0xFF9C7A3F), Color(0xFFC9A35C), Color(0xFF9C7A3F), Color(0xFF6E5223)],
    stops: [0, .30, .50, .70, 1],
  );
  static const screenGlow = RadialGradient(
    center: Alignment(0, -1),
    radius: 1.1,
    colors: [Color(0x8C28305C), Color(0x000B0B12)],
  );
}

class LpeRadius {
  static const pill = 999.0;
  static const card = 28.0; // frame cards, glass panels (28–32)
  static const qrTile = 24.0;
  static const photo = 18.0; // captured shots, filter thumbs (18–20)
  static const field = 16.0; // inputs, keys
  static const printPreview = 6.0;
}

class LpeShadows {
  static const glass = [BoxShadow(color: Color(0x73000000), blurRadius: 60, offset: Offset(0, 20))];
  static const goldButton = [
    BoxShadow(color: Color(0x47D4AF6A), blurRadius: 30, offset: Offset(0, 10)),
    BoxShadow(color: Color(0x80000000), blurRadius: 6, offset: Offset(0, 2)),
  ];
  static const pressedGlow = [
    BoxShadow(color: Color(0xBFF5E1A4), blurRadius: 44),
    BoxShadow(color: Color(0x2EF5E1A4), spreadRadius: 6),
  ];
  static const selected = [BoxShadow(color: Color(0x73F5E1A4), blurRadius: 28)];
  static const print = [BoxShadow(color: Color(0xA6000000), blurRadius: 60, offset: Offset(0, 30))];
}

class LpeType {
  static TextStyle displayXL = GoogleFonts.playfairDisplay(fontSize: 96, fontWeight: FontWeight.w700, height: 1.08);
  static TextStyle displayL = GoogleFonts.playfairDisplay(fontSize: 64, fontWeight: FontWeight.w600, height: 1.15);
  static TextStyle title = GoogleFonts.playfairDisplay(fontSize: 40, fontWeight: FontWeight.w600, height: 1.15);
  static TextStyle countdown = GoogleFonts.playfairDisplay(fontSize: 180, fontWeight: FontWeight.w700, height: 1);
  static TextStyle button = GoogleFonts.beVietnamPro(fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: .28);
  static TextStyle bodyL = GoogleFonts.beVietnamPro(fontSize: 32, fontWeight: FontWeight.w500, height: 1.3);
  static TextStyle body = GoogleFonts.beVietnamPro(fontSize: 20, fontWeight: FontWeight.w400, height: 1.45);
  static TextStyle eyebrow = GoogleFonts.beVietnamPro(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 3.6,
    color: LpeColors.rose,
  );
  static TextStyle chip = GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.w500);
}

/// Durations & curves (see design/Motion.dc.html for the full table).
class LpeMotion {
  static const screenIn = Duration(milliseconds: 380);
  static const screenOut = Duration(milliseconds: 200);
  static const screenCurve = Curves.easeOutQuint; // cubic-bezier(.22,1,.36,1)
  static const press = Duration(milliseconds: 140);
  static const pressCurve = Cubic(.2, .8, .2, 1);
  static const release = Duration(milliseconds: 220);
  static const shimmerCycle = Duration(seconds: 3); // sweep occupies first 28%
  static const shimmerCurve = Curves.fastOutSlowIn;
  static const metalSweep = Duration(seconds: 6);
  static const cardSelect = Duration(milliseconds: 260);
  static const overshoot = Curves.easeOutBack; // cubic-bezier(.34,1.56,.64,1)
  static const flip = Duration(milliseconds: 420);
  static const flipCurve = Cubic(.2, .9, .3, 1.2);
  static const ringGlow = Duration(milliseconds: 900);
  static const flashUp = Duration(milliseconds: 40);
  static const flashHold = Duration(milliseconds: 120);
  static const flashDown = Duration(milliseconds: 260);
  static const burst = Duration(milliseconds: 760);
  static const burstCurve = Cubic(.15, .8, .3, 1);
  static const readyIntro = Duration(seconds: 3);
  static const firstShotCountdown = 5; // seconds
  static const nextShotCountdown = 3; // seconds
  static const pickTimeout = Duration(seconds: 45);
  static const urgentAt = 10; // seconds left → red + pulse 1 s
  static const autoReturn = Duration(seconds: 25);
  static const qrBorderSpin = Duration(seconds: 3);
  static const beamSwing = [Duration(seconds: 9), Duration(seconds: 8), Duration(seconds: 11)];
  static const lightSweep = Duration(seconds: 7);
}

/// Sparkle background density per screen (see SPEC §Background).
enum LpeSparkle { max, mid, low }

class LpeSparkleSpec {
  final int dust, glitter, glints, flares, bokeh, rings, beams;
  final bool sweep;
  const LpeSparkleSpec(
    this.dust,
    this.glitter,
    this.glints,
    this.flares,
    this.bokeh,
    this.rings,
    this.beams,
    this.sweep,
  );
  static const max = LpeSparkleSpec(80, 64, 16, 7, 12, 7, 3, true); // attract, thank-you
  static const mid = LpeSparkleSpec(50, 38, 11, 4, 9, 5, 2, true); // frame select, photo select
  static const low = LpeSparkleSpec(24, 20, 7, 2, 0, 0, 0, false); // camera screens, settings, web
}

class LpeFilter {
  final String id;
  final String name;
  final List<double> matrix; // ColorFilter.matrix (offsets in 0–255)
  final double blurSigma; // print-space px at 1200 wide; scale for previews
  const LpeFilter({required this.id, required this.name, required this.matrix, required this.blurSigma});
  ColorFilter get colorFilter => ColorFilter.matrix(matrix);
  ImageFilter? blur(double scale) =>
      blurSigma == 0 ? null : ImageFilter.blur(sigmaX: blurSigma * scale, sigmaY: blurSigma * scale);
}

/// Composed from the CSS filter chains in the design (W3C filter-effects matrices).
const lpeFilters = <LpeFilter>[
  LpeFilter(
    id: 'trongVeo',
    name: 'Trong veo',
    matrix: <double>[
      1.1568,
      -0.0398,
      -0.0040,
      0.0000,
      -6.3750,
      -0.0119,
      1.1289,
      -0.0040,
      0.0000,
      -6.3750,
      -0.0119,
      -0.0398,
      1.1646,
      0.0000,
      -6.3750,
      0.0000,
      0.0000,
      0.0000,
      1.0000,
      0.0000,
    ],
    blurSigma: 0,
  ),
  LpeFilter(
    id: 'nangSom',
    name: 'Nắng sớm',
    matrix: <double>[
      1.0580,
      0.2070,
      -0.0768,
      0.0000,
      0.0000,
      0.0442,
      0.9966,
      0.0735,
      0.0000,
      0.0000,
      0.1429,
      -0.0735,
      0.9592,
      0.0000,
      0.0000,
      0.0000,
      0.0000,
      0.0000,
      1.0000,
      0.0000,
    ],
    blurSigma: 0,
  ),
  LpeFilter(
    id: 'hongDao',
    name: 'Hồng đào',
    matrix: <double>[
      1.0835,
      0.2675,
      -0.1851,
      0.0000,
      0.0000,
      0.0161,
      0.9879,
      0.0963,
      0.0000,
      0.0000,
      0.2230,
      -0.1452,
      0.9660,
      0.0000,
      0.0000,
      0.0000,
      0.0000,
      0.0000,
      1.0000,
      0.0000,
    ],
    blurSigma: 0,
  ),
  LpeFilter(
    id: 'hongMo',
    name: 'Hồng mơ',
    matrix: <double>[
      0.9216,
      0.4859,
      -0.2349,
      0.0000,
      6.3750,
      0.0569,
      0.8778,
      0.1405,
      0.0000,
      6.3750,
      0.3413,
      -0.0577,
      0.7413,
      0.0000,
      6.3750,
      0.0000,
      0.0000,
      0.0000,
      1.0000,
      0.0000,
    ],
    blurSigma: 0,
  ),
  LpeFilter(
    id: 'hongAnhDao',
    name: 'Hồng anh đào',
    matrix: <double>[
      1.3323,
      0.0966,
      -0.4137,
      0.0000,
      7.6500,
      -0.1219,
      1.0380,
      0.0992,
      0.0000,
      7.6500,
      0.2719,
      -0.5090,
      1.2523,
      0.0000,
      7.6500,
      0.0000,
      0.0000,
      0.0000,
      1.0000,
      0.0000,
    ],
    blurSigma: 0,
  ),
  LpeFilter(
    id: 'moMong',
    name: 'Mờ mộng',
    matrix: <double>[
      0.8297,
      0.1009,
      0.0102,
      0.0000,
      20.4000,
      0.0301,
      0.9006,
      0.0102,
      0.0000,
      20.4000,
      0.0301,
      0.1009,
      0.8098,
      0.0000,
      20.4000,
      0.0000,
      0.0000,
      0.0000,
      1.0000,
      0.0000,
    ],
    blurSigma: 0.6,
  ),
];
