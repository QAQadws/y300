import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_palette.dart';

/// Central place for Material component theme construction.
///
/// Component themes stay centralized so feature widgets can consume ThemeData
/// instead of carrying their own light/dark color branches.
final class AppComponentThemeBuilder {
  const AppComponentThemeBuilder._();

  static AppBarTheme appBarTheme(AppThemePalette palette) {
    return AppBarTheme(
      backgroundColor: palette.appBarBackground,
      foregroundColor: palette.appBarForeground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    );
  }

  static NavigationBarThemeData navigationBarTheme(AppThemePalette palette) {
    return NavigationBarThemeData(
      backgroundColor: palette.navigationBarBackground,
    );
  }

  static PopupMenuThemeData popupMenuTheme(ColorScheme scheme) {
    return PopupMenuThemeData(
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: scheme.onSurface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      elevation: 6,
    );
  }

  static MenuThemeData menuTheme(ColorScheme scheme) {
    return MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(
          scheme.surfaceContainer,
        ),
        surfaceTintColor: const WidgetStatePropertyAll<Color>(
          Colors.transparent,
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  static DropdownMenuThemeData dropdownMenuTheme(ColorScheme scheme) {
    return DropdownMenuThemeData(
      textStyle: TextStyle(color: scheme.onSurface),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(
          scheme.surfaceContainer,
        ),
        surfaceTintColor: const WidgetStatePropertyAll<Color>(
          Colors.transparent,
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: inputDecorationTheme(scheme),
    );
  }

  static BottomSheetThemeData bottomSheetTheme(ColorScheme scheme) {
    return BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainer,
      modalBackgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      showDragHandle: false,
    );
  }

  static DialogThemeData dialogTheme(ColorScheme scheme) {
    return DialogThemeData(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: TextStyle(color: scheme.onSurfaceVariant),
    );
  }

  static SnackBarThemeData snackBarTheme(ColorScheme scheme) {
    return SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      actionTextColor: scheme.inversePrimary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  static SegmentedButtonThemeData segmentedButtonTheme(ColorScheme scheme) {
    return SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll<Size>(Size.fromHeight(44)),
        backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.secondaryContainer;
          }
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.disabled)) {
            return scheme.onSurface.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.selected)) {
            return scheme.onSecondaryContainer;
          }
          return scheme.onSurface;
        }),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }

  static SliderThemeData sliderTheme(ColorScheme scheme) {
    return SliderThemeData(
      trackHeight: 4,
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      disabledActiveTrackColor: scheme.primary,
      disabledInactiveTrackColor: scheme.surfaceContainerHighest,
      activeTickMarkColor: scheme.onPrimary.withValues(alpha: 0.38),
      inactiveTickMarkColor: scheme.onSurfaceVariant.withValues(alpha: 0.38),
      disabledActiveTickMarkColor: scheme.onPrimary.withValues(alpha: 0.38),
      disabledInactiveTickMarkColor: scheme.onSurfaceVariant.withValues(
        alpha: 0.38,
      ),
      thumbColor: scheme.primary,
      disabledThumbColor: scheme.primary,
      // Keep the track geometry stable while pressing or dragging. The
      // default Material overlay is a transient halo that reads as a flash
      // on the compact reader and cache controls.
      overlayColor: Colors.transparent,
      overlayShape: SliderComponentShape.noOverlay,
      showValueIndicator: ShowValueIndicator.never,
      valueIndicatorColor: scheme.primary,
      valueIndicatorTextStyle: TextStyle(color: scheme.onPrimary),
    );
  }

  static ListTileThemeData listTileTheme(ColorScheme scheme) {
    return ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      selectedColor: scheme.primary,
      selectedTileColor: scheme.secondaryContainer.withValues(alpha: 0.48),
    );
  }

  static DividerThemeData dividerTheme(ColorScheme scheme) {
    return DividerThemeData(
      color: scheme.outlineVariant,
      space: 1,
      thickness: 1,
    );
  }

  static IconButtonThemeData iconButtonTheme(ColorScheme scheme) {
    return IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.disabled)) {
            return scheme.onSurface.withValues(alpha: 0.38);
          }
          return scheme.onSurfaceVariant;
        }),
      ),
    );
  }

  static InputDecorationThemeData inputDecorationTheme(ColorScheme scheme) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );
    return InputDecorationThemeData(
      filled: true,
      fillColor: scheme.surfaceContainer,
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      helperStyle: TextStyle(color: scheme.onSurfaceVariant),
      errorStyle: TextStyle(color: scheme.error),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
    );
  }

  static ChipThemeData chipTheme(ColorScheme scheme) {
    return ChipThemeData(
      backgroundColor: scheme.surfaceContainer,
      selectedColor: scheme.secondaryContainer,
      disabledColor: scheme.onSurface.withValues(alpha: 0.12),
      labelStyle: TextStyle(color: scheme.onSurface),
      secondaryLabelStyle: TextStyle(color: scheme.onSecondaryContainer),
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  static CardThemeData cardTheme(ColorScheme scheme) {
    return CardThemeData(
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}
