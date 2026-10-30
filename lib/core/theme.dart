import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens harmonized directly with https://pos.hrpocket.in
/// ("Jewellery ERP Enterprise · Haute Joaillerie & Precious Bullion"):
/// - Midnight Obsidian hero & bullion plates with 24K Champagne Gold accents
/// - Crisp Enterprise Slate-50 workspace canvas, pure white cards & Slate-200 borders
/// - Royal Teal & Obsidian action triggers matching the web portal
class Pal {
  // Obsidian / Vault luxury dark surfaces
  static const ink = Color(0xFF0B1120);
  static const obsidian = ink;
  static const inkSoft = Color(0xFF152238);
  static const inkElevated = Color(0xFF1E2E4A);
  static const inkLine = Color(0xFF283A5E);

  // Enterprise workspace light surfaces (Slate-50 / White / Slate-200)
  static const pearl = Color(0xFFF8FAFC);
  static const surfaceAlt = Color(0xFFF1F5F9);
  static const card = Color(0xFFFFFFFF);
  static const line = Color(0xFFE2E8F0);
  static const lineStrong = Color(0xFFCBD5E1);

  // Typography inks
  static const text = Color(0xFF0F172A);
  static const textSoft = Color(0xFF334155);
  static const muted = Color(0xFF64748B);

  // Haute Joaillerie 24K Bullion Gold & Champagne accents
  static const gold = Color(0xFFB78628);
  static const goldBright = Color(0xFFD4AF37);
  static const goldSoft = Color(0xFFF3D58D);
  static const goldDeep = Color(0xFF78530D);
  static const goldWash = Color(0xFFFEF7E6);
  static const goldBorder = Color(0xFFF2DEAC);

  // Enterprise Royal Teal (matches web portal bg-teal-700)
  static const teal = Color(0xFF0F766E);
  static const tealDark = Color(0xFF115E59);
  static const tealWash = Color(0xFFCCFBF1);

  // Status semantics
  static const ok = Color(0xFF059669);
  static const okWash = Color(0xFFECFDF5);
  static const warn = Color(0xFFD97706);
  static const warnWash = Color(0xFFFFFBEB);
  static const danger = Color(0xFFDC2626);
  static const dangerWash = Color(0xFFFEF2F2);
  static const violet = Color(0xFF6D28D9);
  static const violetWash = Color(0xFFF5F3FF);
}

/// Editorial Haute Joaillerie serif (Fraunces) + Enterprise geometric sans
/// (Plus Jakarta Sans) + Tabular precision monospace (JetBrains Mono).
class T {
  static const _tab = [FontFeature.tabularFigures()];

  static TextStyle display(
    double size, {
    Color color = Pal.text,
    FontWeight w = FontWeight.w600,
    double letterSpacing = -0.35,
  }) =>
      GoogleFonts.fraunces(
        fontSize: size,
        fontWeight: w,
        color: color,
        height: 1.14,
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
    primary: Pal.ink,
    onPrimary: Colors.white,
    secondary: Pal.teal,
    onSecondary: Colors.white,
    tertiary: Pal.gold,
    surface: Pal.pearl,
    onSurface: Pal.text,
    error: Pal.danger,
  );
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
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
      titleTextStyle: T.display(20.5, w: FontWeight.w600),
      iconTheme: const IconThemeData(color: Pal.text, size: 22),
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(Pal.lineStrong),
      enabledBorder: border(Pal.lineStrong),
      focusedBorder: border(Pal.teal, 1.8),
      errorBorder: border(Pal.danger),
      focusedErrorBorder: border(Pal.danger, 1.8),
      labelStyle: T.body(13.5, color: Pal.muted),
      hintStyle: T.body(13.5, color: Pal.muted),
      helperStyle: T.body(12, color: Pal.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Pal.ink,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Pal.line,
        disabledForegroundColor: Pal.muted,
        minimumSize: const Size.fromHeight(50),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: T.body(14.5, w: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Pal.text,
        backgroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: Pal.lineStrong, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: T.body(14, w: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Pal.teal,
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
          color: s.contains(WidgetState.selected) ? Pal.ink : Pal.muted,
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
