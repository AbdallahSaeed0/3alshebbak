import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// "Marquee": a cinema sign at night — warm gold lights on near-black.
abstract final class AppColors {
  static const background = Color(0xFF0B0A08);
  static const surface = Color(0xFF16130F);
  static const raised = Color(0xFF211C15);
  static const hairline = Color(0xFF2E271E);
  static const perforation = Color(0xFF3A3124);
  static const gold = Color(0xFFF2B544);
  static const amber = Color(0xFFFF8A3D);
  static const text = Color(0xFFF5EFE6);
  static const muted = Color(0xFFA39A8C);
  static const onGold = Color(0xFF1A1206);

  // Format tints, told apart by lightness as well as hue.
  static const imax = Color(0xFF7FB8FF);
  static const fourDx = Color(0xFF7FD4A0);
}

/// Display type for titles (Lalezar), condensed numerals for times (Bebas Neue),
/// IBM Plex Sans Arabic for everything else.
abstract final class AppText {
  static TextStyle display(double size, {Color color = AppColors.text}) =>
      GoogleFonts.lalezar(fontSize: size, color: color, height: 1.15);

  static TextStyle numerals(double size, {Color color = AppColors.text}) =>
      GoogleFonts.bebasNeue(fontSize: size, color: color, height: 1);

  static TextStyle body(
    double size, {
    Color color = AppColors.text,
    FontWeight weight = FontWeight.w400,
  }) => GoogleFonts.ibmPlexSansArabic(
    fontSize: size,
    color: color,
    fontWeight: weight,
    height: 1.4,
  );
}

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.gold,
      onPrimary: AppColors.onGold,
      secondary: AppColors.amber,
      surface: AppColors.surface,
      onSurface: AppColors.text,
    ),
    textTheme: GoogleFonts.ibmPlexSansArabicTextTheme(
      base.textTheme,
    ).apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    splashFactory: InkSparkle.splashFactory,
  );
}
