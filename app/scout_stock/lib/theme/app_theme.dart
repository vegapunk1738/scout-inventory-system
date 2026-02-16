import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens that are NOT part of Material's ColorScheme.
/// Access via: Theme.of(context).extension<AppTokens>()!
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.radiusLg,
    required this.radiusXl,
    required this.cardShadow,
    required this.glowShadow,
  });

  final double radiusLg;
  final double radiusXl;

  /// Soft neutral shadow used for cards/sheets.
  final List<BoxShadow> cardShadow;

  /// Green glow used only on primary “hero” actions.
  final List<BoxShadow> glowShadow;

  @override
  AppTokens copyWith({
    double? radiusLg,
    double? radiusXl,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? glowShadow,
  }) {
    return AppTokens(
      radiusLg: radiusLg ?? this.radiusLg,
      radiusXl: radiusXl ?? this.radiusXl,
      cardShadow: cardShadow ?? this.cardShadow,
      glowShadow: glowShadow ?? this.glowShadow,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      radiusLg: lerpDouble(radiusLg, other.radiusLg, t)!,
      radiusXl: lerpDouble(radiusXl, other.radiusXl, t)!,
      cardShadow: t < 0.5 ? cardShadow : other.cardShadow,
      glowShadow: t < 0.5 ? glowShadow : other.glowShadow,
    );
  }
}

class AppColors {
  static const primary = Color(0xFF0E7A2C);
  static const ink = Color(0xFF0B1220);
  static const muted = Color(0xFF667085);

  static const outline = Color(0xFFE4E7EC);

  /// App background (off-white)
  static const background = Color(0xFFF7F8FA);

  static const successBg = Color(0xFFE7F6EC);
  static const warningBg = Color(0xFFFFF3D6);
  static const infoBg = Color(0xFFE8F1FF);

  static const onPrimary = Colors.white;
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light);

    // Start from a seed scheme, then normalize to your palette.
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.primary,
          onPrimary: AppColors.onPrimary,
          surface: Colors.white,
          onSurface: AppColors.ink,
          outline: AppColors.outline,
          secondary: AppColors.primary,
          onSecondary: AppColors.onPrimary,
          // Background is what your screens look like.
          surfaceContainerLowest: AppColors.background,
          surfaceContainerLow: AppColors.background,
          surfaceContainer: AppColors.background,
        );

    // Typography: softer than Inter, matches your screenshots closely.
    final baseText = GoogleFonts.plusJakartaSansTextTheme(base.textTheme);

    final textTheme = baseText
        .copyWith(
          displaySmall: GoogleFonts.plusJakartaSans(
            fontSize: 42,
            height: 1.05,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
          headlineMedium: GoogleFonts.plusJakartaSans(
            fontSize: 28,
            height: 1.15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
          titleLarge: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            height: 1.2,
            fontWeight: FontWeight.w800,
          ),
          titleMedium: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
          bodyLarge: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            height: 1.5,
            fontWeight: FontWeight.w500,
          ),
          bodyMedium: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            height: 1.5,
            fontWeight: FontWeight.w500,
            color: AppColors.muted, // muted body text default
          ),
          labelLarge: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            height: 1.1,
            fontWeight: FontWeight.w800,
          ),
          labelMedium: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            height: 1.1,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        )
        .apply(displayColor: AppColors.ink, bodyColor: AppColors.ink);

    const tokens = AppTokens(
      radiusLg: 18,
      radiusXl: 24,
      cardShadow: [
        BoxShadow(
          blurRadius: 18,
          offset: Offset(0, 10),
          color: Color(0x14000000), // ~8% black
        ),
      ],
      glowShadow: [
        BoxShadow(
          blurRadius: 28,
          spreadRadius: 2,
          offset: Offset(0, 10),
          color: Color(0x660E7A2C), // green glow (~40%)
        ),
      ],
    );

    final roundedXl = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.radiusXl),
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      extensions: const [tokens],

      // Top app bars
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleMedium,
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),

      // Icons
      iconTheme: const IconThemeData(color: AppColors.ink),

      // Cards & sheets (your UI is card-heavy)
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: roundedXl,
        surfaceTintColor: Colors.transparent, // avoid M3 tint
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: roundedXl,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyLarge?.copyWith(color: AppColors.muted),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: roundedXl,
        showDragHandle: true,
        dragHandleColor: AppColors.outline,
      ),

      // Inputs (search bars + forms + manual entry)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        hintStyle: textTheme.bodyLarge?.copyWith(
          color: const Color(0xFFB9C0C8),
          fontWeight: FontWeight.w700,
        ),
        labelStyle: textTheme.labelMedium?.copyWith(color: AppColors.muted),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          borderSide: const BorderSide(color: Colors.redAccent, width: 2),
        ),
      ),

      // Buttons (base style; glow is a wrapper widget, not global)
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          textStyle: textTheme.labelLarge,
          minimumSize: const Size.fromHeight(60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusLg),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          textStyle: textTheme.titleMedium,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: AppColors.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusLg),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          textStyle: textTheme.titleMedium,
        ),
      ),

      // Chips / badges (Admin/Scout tags, status pills)
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.background,
        selectedColor: AppColors.successBg,
        labelStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
        side: const BorderSide(color: AppColors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),

      // List tiles (activity rows, settings rows)
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.muted,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodyMedium,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      ),

      // Navigation (you may use BottomNavigationBar now, but this also supports M3 NavigationBar)
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.muted,
        selectedLabelStyle: textTheme.labelMedium?.copyWith(letterSpacing: 0),
        unselectedLabelStyle: textTheme.labelMedium?.copyWith(letterSpacing: 0),
        type: BottomNavigationBarType.fixed,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.successBg,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final color = states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.muted;
          return IconThemeData(color: color);
        }),
      ),

      // FAB (center “+”)
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 6,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.outline,
        thickness: 1,
        space: 1,
      ),

      // Cursor/selection (important for your big input fields)
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.ink,
        selectionColor: AppColors.primary.withOpacity(0.18),
        selectionHandleColor: AppColors.primary,
      ),
    );
  }
}
