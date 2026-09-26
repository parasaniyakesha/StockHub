import 'package:flutter/material.dart';

/// Restrained corporate palette built around a single brand blue.
class AppColors {
  AppColors._();

  // Brand
  static const primary = Color(0xFF1E4FD8);
  static const primaryDark = Color(0xFF173DA8);
  static const primarySoft = Color(0xFFEAF0FD);

  // Neutrals (slate)
  static const background = Color(0xFFF4F6F9);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF8FAFC);
  static const border = Color(0xFFE2E7EE);
  static const borderStrong = Color(0xFFCBD3DE);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF475569);
  static const textMuted = Color(0xFF8391A7);

  // Sidebar
  static const sidebar = Color(0xFF0F1B33);
  static const sidebarHover = Color(0xFF1A2847);
  static const sidebarSelected = Color(0xFF22345C);
  static const sidebarText = Color(0xFFB7C2D6);
  static const sidebarTextActive = Color(0xFFFFFFFF);

  // Semantic
  static const success = Color(0xFF15803D);
  static const successSoft = Color(0xFFE7F6EC);
  static const warning = Color(0xFFB45309);
  static const warningSoft = Color(0xFFFEF3E2);
  static const danger = Color(0xFFC62828);
  static const dangerSoft = Color(0xFFFDECEC);
  static const info = Color(0xFF0369A1);
  static const infoSoft = Color(0xFFE6F3FA);
  static const neutral = Color(0xFF475569);
  static const neutralSoft = Color(0xFFEEF1F5);
  static const purple = Color(0xFF6D28D9);
  static const purpleSoft = Color(0xFFF1EBFD);

  /// Categorical series colors for charts, in fixed order (never cycle/reassign
  /// per-filter). Validated CVD-safe ordering - see dataviz skill palette.md.
  static const chartSeries = [
    Color(0xFF2A78D6), // blue
    Color(0xFFEB6834), // orange
    Color(0xFF1BAF7A), // aqua
    Color(0xFFEDA100), // yellow
    Color(0xFFE87BA4), // magenta
    Color(0xFF008300), // green
    Color(0xFF4A3AA7), // violet
    Color(0xFFE34948), // red
  ];

  /// Single-hue sequential ramp (light -> dark) for magnitude encodings.
  static const chartSequential = [
    Color(0xFFCDE2FB),
    Color(0xFF9EC5F4),
    Color(0xFF6DA7EC),
    Color(0xFF3987E5),
    Color(0xFF256ABF),
    Color(0xFF184F95),
  ];
}
