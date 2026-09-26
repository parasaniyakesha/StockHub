import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Spacing scale (4pt grid). Use these instead of magic numbers.
class Gap {
  Gap._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class Radii {
  Radii._();
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
}

class AppTheme {
  AppTheme._();

  static const double controlHeight = 38;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.surface,
      error: AppColors.danger,
      brightness: Brightness.light,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, visualDensity: VisualDensity.compact);
    final text = base.textTheme.apply(bodyColor: AppColors.textPrimary, displayColor: AppColors.textPrimary);

    OutlineInputBorder border(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.sm), borderSide: BorderSide(color: c, width: w));

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      dividerColor: AppColors.border,
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        titleLarge: text.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
        titleMedium: text.titleMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
        titleSmall: text.titleSmall?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
        bodyLarge: text.bodyLarge?.copyWith(fontSize: 14),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 13, color: AppColors.textPrimary),
        bodySmall: text.bodySmall?.copyWith(fontSize: 12, color: AppColors.textSecondary),
        labelLarge: text.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
        labelMedium: text.labelMedium?.copyWith(fontSize: 12, color: AppColors.textSecondary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        floatingLabelStyle: const TextStyle(color: AppColors.primary, fontSize: 13),
        border: border(AppColors.borderStrong),
        enabledBorder: border(AppColors.borderStrong),
        focusedBorder: border(AppColors.primary, 1.5),
        errorBorder: border(AppColors.danger),
        focusedErrorBorder: border(AppColors.danger, 1.5),
        disabledBorder: border(AppColors.border),
        errorStyle: const TextStyle(fontSize: 11.5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, controlHeight),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, controlHeight),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.borderStrong),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: AppColors.borderStrong, width: 1.5),
        visualDensity: VisualDensity.compact,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
        titleTextStyle: text.titleLarge?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md), side: const BorderSide(color: AppColors.border)),
        textStyle: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.circular(Radii.sm)),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        dividerColor: AppColors.border,
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
      chipTheme: base.chipTheme.copyWith(
        side: const BorderSide(color: AppColors.border),
        labelStyle: const TextStyle(fontSize: 12),
      ),
    );
  }
}
