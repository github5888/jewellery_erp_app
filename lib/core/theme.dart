import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette: deep bottle-green "vault" tones, pearl surfaces, one gold accent.
/// Gold is reserved for money and metal - never decoration.
class Pal {
  static const ink = Color(0xFF0E2B27);
  static const inkSoft = Color(0xFF16403A);
  static const inkLine = Color(0xFF2D5A53);
  static const pearl = Color(0xFFF5F4F0);
  static const card = Colors.white;
  static const line = Color(0xFFE4E2DB);
  static const text = Color(0xFF14201E);
  static const muted = Color(0xFF68736F);
  static const gold = Color(0xFFB58A3C);
  static const goldSoft = Color(0xFFE2C27C);
  static const goldWash = Color(0xFFF3E9D2);
  static const danger = Color(0xFFB3402F);
  static const dangerWash = Color(0xFFF7E3DF);
  static const ok = Color(0xFF2F7D5B);
  static const okWash = Color(0xFFDDEFE6);
  static const warn = Color(0xFF9A6A12);
  static const warnWash = Color(0xFFF6EBCF);
}

/// Fraunces carries money and headlines; Manrope carries everything else.
class T {
  static const _tab = [FontFeature.tabularFigures()];

  static TextStyle display(double size,
          {Color color = Pal.text, FontWeight w = FontWeight.w500}) =>
      GoogleFonts.fraunces(
        fontSize: size,
        fontWeight: w,
        color: color,
        height: 1.1,
        letterSpacing: -0.4,
        fontFeatures: _tab,
      );

  static TextStyle body(double size,
          {Color color = Pal.text, FontWeight w = FontWeight.w500}) =>
      GoogleFonts.manrope(
        fontSize: size,
        fontWeight: w,
        color: color,
        height: 1.35,
        fontFeatures: _tab,
      );
}

ThemeData buildTheme() {
  final base = GoogleFonts.manropeTextTheme();
  const scheme = ColorScheme.light(
    primary: Pal.ink,
    onPrimary: Colors.white,
    secondary: Pal.gold,
    surface: Pal.pearl,
    onSurface: Pal.text,
    error: Pal.danger,
  );
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Pal.pearl,
    textTheme: base.apply(bodyColor: Pal.text, displayColor: Pal.text),
    appBarTheme: AppBarTheme(
      backgroundColor: Pal.pearl,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: T.display(22),
      iconTheme: const IconThemeData(color: Pal.text),
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(Pal.line),
      enabledBorder: border(Pal.line),
      focusedBorder: border(Pal.ink, 1.6),
      errorBorder: border(Pal.danger),
      focusedErrorBorder: border(Pal.danger, 1.6),
      labelStyle: T.body(14, color: Pal.muted),
      hintStyle: T.body(14, color: Pal.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Pal.ink,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: T.body(15.5, w: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Pal.ink,
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: Pal.line, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: T.body(15, w: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Pal.ink,
        textStyle: T.body(14, w: FontWeight.w700),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: Pal.goldWash,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => T.body(11.5,
            w: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            color: s.contains(WidgetState.selected) ? Pal.ink : Pal.muted),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected) ? Pal.ink : Pal.muted),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Pal.ink,
      contentTextStyle: T.body(14, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: const DividerThemeData(color: Pal.line, thickness: 1, space: 1),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Pal.pearl,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
  );
}
