import 'package:flutter/material.dart';

// ── Border Radius ─────────────────────────────────────────────────────────────
abstract final class LumaRadius {
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double full = 999;

  static const radiusXs = BorderRadius.all(Radius.circular(xs));
  static const radiusSm = BorderRadius.all(Radius.circular(sm));
  static const radiusMd = BorderRadius.all(Radius.circular(md));
  static const radiusLg = BorderRadius.all(Radius.circular(lg));
  static const radiusXl = BorderRadius.all(Radius.circular(xl));
}

// ── Shadows (Untitled UI) ─────────────────────────────────────────────────────
abstract final class LumaShadow {
  static const xs = [
    BoxShadow(
        offset: Offset(0, 1), blurRadius: 2, color: Color(0x0D101828)),
  ];

  static const sm = [
    BoxShadow(
        offset: Offset(0, 1), blurRadius: 3, color: Color(0x1A101828)),
    BoxShadow(
        offset: Offset(0, 1), blurRadius: 2, color: Color(0x0F101828)),
  ];

  static const md = [
    BoxShadow(
        offset: Offset(0, 4),
        blurRadius: 8,
        spreadRadius: -2,
        color: Color(0x1A101828)),
    BoxShadow(
        offset: Offset(0, 2),
        blurRadius: 4,
        spreadRadius: -2,
        color: Color(0x0F101828)),
  ];

  static const lg = [
    BoxShadow(
        offset: Offset(0, 12),
        blurRadius: 16,
        spreadRadius: -4,
        color: Color(0x14101828)),
    BoxShadow(
        offset: Offset(0, 4),
        blurRadius: 6,
        spreadRadius: -2,
        color: Color(0x08101828)),
  ];

  static const xl = [
    BoxShadow(
        offset: Offset(0, 20),
        blurRadius: 24,
        spreadRadius: -4,
        color: Color(0x14101828)),
    BoxShadow(
        offset: Offset(0, 8),
        blurRadius: 8,
        spreadRadius: -4,
        color: Color(0x08101828)),
  ];
}

// ── Spacing ───────────────────────────────────────────────────────────────────
abstract final class LumaSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}
