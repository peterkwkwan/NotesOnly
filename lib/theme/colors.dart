import 'package:flutter/material.dart';

/// Pelvi brand + neutral color tokens (Figma SoT — cream / dusty pink).
class PelviColors {
  PelviColors._();

  // Brand — dusty pink (primary) / purple (secondary)
  static const pink950 = Color(0xFF8A2E56); // pressed / deepest pink
  static const pink700 = Color(0xFFB63C70);
  static const pink400 = Color(0xFFD48AA8);
  static const pink200 = Color(0xFFE8C4D4);
  static const pink50 = Color(0xFFF8EAF0);

  static const purple950 = Color(0xFF5A4578);
  static const purple700 = Color(0xFF7B609F);
  static const purple400 = Color(0xFFA892C0);
  static const purple50 = Color(0xFFF1ECF6);

  // Neutrals (Figma cream canvas)
  static const canvas = Color(0xFFFFFCFA);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF6F2F2);
  static const ink = Color(0xFF302931);
  static const inkMuted = Color(0xFF827780);
  static const inkInverse = Color(0xFFFFFFFF);
  static const border = Color(0xFFEDE5E8);
  static const chromeBorder = Color(0xFFEDE5E8);
  static const overlay = Color(0x73302931); // ~45% ink

  // Semantic
  static const success = Color(0xFF007A33);
  static const danger = Color(0xFFB42318);
  static const warning = Color(0xFFB54708);
}
