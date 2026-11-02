import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// One set of colours. "Marquee": a cinema sign at night — warm gold lights
/// on near-black — and its daytime twin on warm paper.
class Palette {
  const Palette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.raised,
    required this.hairline,
    required this.perforation,
    required this.gold,
    required this.goldEdge,
    required this.amber,
    required this.text,
    required this.muted,
    required this.onGold,
    required this.imax,
    required this.fourDx,
    required this.glass,
    required this.glassEdge,
    required this.scrim,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color raised;
  final Color hairline;
  final Color perforation;
  final Color gold;

  /// The border of something of mine (a starred cinema's card).
  final Color goldEdge;
  final Color amber;
  final Color text;
  final Color muted;
  final Color onGold;

  // Format tints, told apart by lightness as well as hue.
  final Color imax;
  final Color fourDx;

  /// Frosted panels (tab bar, cards over pictures) and their bright rim.
  final Color glass;
  final Color glassEdge;

  /// Behind sheets and dialogs.
  final Color scrim;

  static const dark = Palette(
    brightness: Brightness.dark,
    background: Color(0xFF0B0A08),
    surface: Color(0xFF16130F),
    raised: Color(0xFF211C15),
    hairline: Color(0xFF2E271E),
    perforation: Color(0xFF3A3124),
    gold: Color(0xFFF2B544),
    goldEdge: Color(0xFF5C4520),
    amber: Color(0xFFFF8A3D),
    text: Color(0xFFF5EFE6),
    muted: Color(0xFFA39A8C),
    onGold: Color(0xFF1A1206),
    imax: Color(0xFF7FB8FF),
    fourDx: Color(0xFF7FD4A0),
    glass: Color(0xA61A1612),
    glassEdge: Color(0x24FFFFFF),
    scrim: Color(0xB8050403),
  );

  static const light = Palette(
    brightness: Brightness.light,
    background: Color(0xFFF7F2EA),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFF0E8DB),
    hairline: Color(0xFFE6DCCB),
    perforation: Color(0xFFD8C9B1),
    gold: Color(0xFFB87A0B),
    goldEdge: Color(0xFFE2C084),
    amber: Color(0xFFD45A12),
    text: Color(0xFF1C1610),
    muted: Color(0xFF6E6455),
    onGold: Color(0xFFFFFFFF),
    imax: Color(0xFF1F5FC4),
    fourDx: Color(0xFF17804A),
    glass: Color(0xB8FFFFFF),
    glassEdge: Color(0x99FFFFFF),
    scrim: Color(0x8A1C1610),
  );
}

/// The colours in use. Screens read them while building; the app rebuilds
/// everything when the palette changes (see main.dart).
abstract final class AppColors {
  static Palette palette = Palette.dark;

  static bool get isDark => palette.brightness == Brightness.dark;

  static Color get background => palette.background;
  static Color get surface => palette.surface;
  static Color get raised => palette.raised;
  static Color get hairline => palette.hairline;
  static Color get perforation => palette.perforation;
  static Color get gold => palette.gold;
  static Color get goldEdge => palette.goldEdge;
  static Color get amber => palette.amber;
  static Color get text => palette.text;
  static Color get muted => palette.muted;
  static Color get onGold => palette.onGold;
  static Color get imax => palette.imax;
  static Color get fourDx => palette.fourDx;
  static Color get glass => palette.glass;
  static Color get glassEdge => palette.glassEdge;
  static Color get scrim => palette.scrim;
}

/// Display type for titles (Lalezar), condensed numerals for times (Bebas Neue),
/// IBM Plex Sans Arabic for everything else.
abstract final class AppText {
  static TextStyle display(double size, {Color? color}) => GoogleFonts.lalezar(
    fontSize: size,
    color: color ?? AppColors.text,
    height: 1.15,
  );

  static TextStyle numerals(double size, {Color? color}) =>
      GoogleFonts.bebasNeue(
        fontSize: size,
        color: color ?? AppColors.text,
        height: 1,
      );

  static TextStyle body(
    double size, {
    Color? color,
    FontWeight weight = FontWeight.w400,
  }) => GoogleFonts.ibmPlexSansArabic(
    fontSize: size,
    color: color ?? AppColors.text,
    fontWeight: weight,
    height: 1.4,
  );
}

/// The card look: a lifted panel with a soft rim of light along its top
/// edge, like glass catching the marquee.
abstract final class AppDecor {
  static BoxDecoration card({
    double radius = 16,
    bool mine = false,
  }) => BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.alphaBlend(
          AppColors.isDark ? const Color(0x12FFFFFF) : const Color(0x00FFFFFF),
          AppColors.surface,
        ),
        AppColors.surface,
      ],
    ),
    border: Border.all(color: mine ? AppColors.goldEdge : AppColors.hairline),
    boxShadow: [
      BoxShadow(
        color: AppColors.isDark
            ? const Color(0x66000000)
            : const Color(0x14583C10),
        blurRadius: AppColors.isDark ? 18 : 24,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

/// A tappable card in the app's look ([AppDecor.card]); ink splashes stay
/// inside it.
class TapCard extends StatelessWidget {
  const TapCard({
    super.key,
    required this.child,
    this.radius = 16,
    this.mine = false,
  });

  final Widget child;
  final double radius;

  /// Gold-rimmed: one of my cinemas.
  final bool mine;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: AppDecor.card(radius: radius, mine: mine),
    child: Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  );
}

/// Frosted glass: blurs what's behind it and tints it, with a bright rim.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = 24,
  });

  final Widget child;
  final double radius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            color: AppColors.isDark
                ? const Color(0x80000000)
                : const Color(0x22583C10),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: shape,
              color: AppColors.glass,
              border: Border.all(color: AppColors.glassEdge, width: 0.8),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

ThemeData buildTheme() {
  final p = AppColors.palette;
  final base = ThemeData(brightness: p.brightness, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: p.background,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: p.gold,
          brightness: p.brightness,
        ).copyWith(
          primary: p.gold,
          onPrimary: p.onGold,
          secondary: p.amber,
          surface: p.surface,
          onSurface: p.text,
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.text,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      modalBarrierColor: p.scrim,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.raised,
      behavior: SnackBarBehavior.floating,
    ),
    dividerColor: p.hairline,
    textTheme: GoogleFonts.ibmPlexSansArabicTextTheme(
      base.textTheme,
    ).apply(bodyColor: p.text, displayColor: p.text),
    splashFactory: InkSparkle.splashFactory,
  );
}
