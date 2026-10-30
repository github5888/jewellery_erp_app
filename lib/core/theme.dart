import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Royal Haute Joaillerie & Sovereign 24K Bullion Design System:
/// - Deep Espresso-Onyx velvet (`ink`) paired with 24K Sovereign Gold (`goldBright` / `gold`)
/// - Warm Royal Ivory (`pearl`) workspace canvas & pure white cards (`card`) with sand-gold hairlines
/// - Zero cold hospital greens: every accent, focus border, wash, and primary CTA radiates luxury gold
class Pal {
  // Deep Royal Espresso-Onyx velvet surfaces
  static const ink = Color(0xFF16110B);
  static const obsidian = ink;
  static const inkSoft = Color(0xFF251C12);
  static const inkElevated = Color(0xFF342719);
  static const inkLine = Color(0xFF4A3824);

  // Warm Royal Ivory & Champagne Linen light surfaces
  static const pearl = Color(0xFFFAF7F1);
  static const surfaceAlt = Color(0xFFF3ECE0);
  static const card = Color(0xFFFFFFFF);
  static const line = Color(0xFFE7DEC9);
  static const lineStrong = Color(0xFFD6C6A9);

  // Warm Espresso Typography Inks
  static const text = Color(0xFF1A140E);
  static const textSoft = Color(0xFF3D3124);
  static const muted = Color(0xFF756756);

  // 24K Sovereign Royal Gold Palette
  static const gold = Color(0xFFB8860B);
  static const goldBright = Color(0xFFD4AF37);
  static const goldSoft = Color(0xFFF3D892);
  static const goldDeep = Color(0xFF7A5608);
  static const goldWash = Color(0xFFFBF3DF);
  static const goldBorder = Color(0xFFE7CE92);

  // Sovereign Burnished Gold action tokens (replaces cold teal/mint across all screens)
  static const teal = Color(0xFFA67814);
  static const tealDark = Color(0xFF7D580A);
  static const tealWash = Color(0xFFF9EFE0);

  // Imperial Ruby / Burgundy secondary accent
  static const ruby = Color(0xFF6E1E32);
  static const rubyWash = Color(0xFFFAF0F3);

  // Refined Jewel-Tone Status Semantics
  static const ok = Color(0xFF1E6B47);
  static const okWash = Color(0xFFEDF7F1);
  static const warn = Color(0xFFB4690E);
  static const warnWash = Color(0xFFFEF5E7);
  static const danger = Color(0xFF9E2A2B);
  static const dangerWash = Color(0xFFFDF0F0);
  static const violet = Color(0xFF5C2D68);
  static const violetWash = Color(0xFFF6EFF8);
}

/// Editorial Haute Joaillerie serif (Fraunces) + Clean Luxury Sans
/// (Plus Jakarta Sans) + Tabular precision monospace (JetBrains Mono).
class T {
  static const _tab = [FontFeature.tabularFigures()];

  static TextStyle display(
    double size, {
    Color color = Pal.text,
    FontWeight w = FontWeight.w600,
    double letterSpacing = -0.3,
  }) =>
      GoogleFonts.fraunces(
        fontSize: size,
        fontWeight: w,
        color: color,
        height: 1.15,
        letterSpacing: letterSpacing,
        fontFeatures: _tab,
      );

  static TextStyle body(
    double size, {
    Color color = Pal.text,
    FontWeight w = FontWeight.w500,
    double height = 1.38,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: w,
        color: color,
        height: height,
        fontFeatures: _tab,
      );

  static TextStyle mono(
    double size, {
    Color color = Pal.text,
    FontWeight w = FontWeight.w600,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: w,
        color: color,
        height: 1.32,
        fontFeatures: _tab,
      );

  static TextStyle caps(
    double size, {
    Color color = Pal.muted,
    FontWeight w = FontWeight.w700,
    double letterSpacing = 1.05,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: w,
        color: color,
        height: 1.2,
        letterSpacing: letterSpacing,
        fontFeatures: _tab,
      );
}

ThemeData buildTheme() {
  final base = GoogleFonts.plusJakartaSansTextTheme();
  const scheme = ColorScheme.light(
    primary: Pal.gold,
    onPrimary: Colors.white,
    secondary: Pal.ink,
    onSecondary: Colors.white,
    tertiary: Pal.goldBright,
    surface: Pal.pearl,
    onSurface: Pal.text,
    error: Pal.danger,
  );
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: c, width: w),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Pal.pearl,
    textTheme: base.apply(bodyColor: Pal.text, displayColor: Pal.text),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      shadowColor: Pal.line,
      centerTitle: false,
      titleTextStyle: T.display(20, w: FontWeight.w600),
      iconTheme: const IconThemeData(color: Pal.text, size: 22),
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(Pal.lineStrong),
      enabledBorder: border(Pal.lineStrong),
      focusedBorder: border(Pal.gold, 1.8),
      errorBorder: border(Pal.danger),
      focusedErrorBorder: border(Pal.danger, 1.8),
      labelStyle: T.body(13.5, color: Pal.muted),
      hintStyle: T.body(13.5, color: Pal.muted.withValues(alpha: 0.78)),
      helperStyle: T.body(12, color: Pal.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Pal.gold,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Pal.line,
        disabledForegroundColor: Pal.muted,
        minimumSize: const Size.fromHeight(50),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        textStyle: T.body(14.5, w: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Pal.goldDeep,
        backgroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: Pal.goldBorder, width: 1.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        textStyle: T.body(14, w: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Pal.goldDeep,
        textStyle: T.body(13.5, w: FontWeight.w700),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: Pal.goldWash,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => T.body(
          11.2,
          w: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
          color: s.contains(WidgetState.selected) ? Pal.goldDeep : Pal.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: 22,
          color: s.contains(WidgetState.selected) ? Pal.goldDeep : Pal.muted,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Pal.ink,
      contentTextStyle: T.body(13.5, color: Colors.white, w: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: const DividerThemeData(color: Pal.line, thickness: 1, space: 1),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Pal.pearl,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}
