import 'package:flutter/material.dart';

/// Material 3 theme.
///
/// Palette: electric violet as the brand colour (matches the launcher icon),
/// mint for "done" states (tertiary role), amber for attention (secondary
/// role: reliability warnings), and a deep navy-violet dark mode instead of
/// plain grey. Every override below is paired with its "on" colour and was
/// checked for WCAG AA contrast.
class AppTheme {
  AppTheme._();

  /// Brand violet, also the launcher icon gradient's mid tone.
  static const Color seed = Color(0xFF6B4EFF);

  /// Mint used by the icon's dot and by completed states.
  static const Color mint = Color(0xFF3DF0BE);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ColorScheme _scheme(Brightness brightness) {
    final light = brightness == Brightness.light;
    return ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
      // Primary: violet.
      primary: light ? seed : const Color(0xFFB9ACFF),
      onPrimary: light ? Colors.white : const Color(0xFF1F0A78),
      primaryContainer:
          light ? const Color(0xFFE6E0FF) : const Color(0xFF3B1FC4),
      onPrimaryContainer:
          light ? const Color(0xFF1A0A66) : const Color(0xFFE6E0FF),
      // Secondary: amber, reserved for "needs attention" surfaces.
      secondary: light ? const Color(0xFFB25E00) : const Color(0xFFFFB866),
      onSecondary: light ? Colors.white : const Color(0xFF472A00),
      secondaryContainer:
          light ? const Color(0xFFFFE0B8) : const Color(0xFF6A3F00),
      onSecondaryContainer:
          light ? const Color(0xFF4A2800) : const Color(0xFFFFDDB3),
      // Tertiary: mint, the colour of getting it done.
      tertiary: light ? const Color(0xFF0B7F60) : mint,
      onTertiary: light ? Colors.white : const Color(0xFF003826),
      tertiaryContainer:
          light ? const Color(0xFFBDF5E3) : const Color(0xFF005140),
      onTertiaryContainer:
          light ? const Color(0xFF00382A) : const Color(0xFF9FFADC),
      // Surfaces: lavender-tinted white / deep navy-violet.
      surface: light ? const Color(0xFFFBFAFF) : const Color(0xFF0F0E1A),
      onSurface: light ? const Color(0xFF17142B) : const Color(0xFFE7E4F5),
      surfaceContainerLowest:
          light ? Colors.white : const Color(0xFF0A0913),
      surfaceContainerLow:
          light ? const Color(0xFFF4F1FF) : const Color(0xFF171626),
      surfaceContainer:
          light ? const Color(0xFFEEEAFB) : const Color(0xFF1D1C2E),
      surfaceContainerHigh:
          light ? const Color(0xFFE8E4F7) : const Color(0xFF262538),
      surfaceContainerHighest:
          light ? const Color(0xFFE1DDF1) : const Color(0xFF302F43),
      onSurfaceVariant:
          light ? const Color(0xFF5A5670) : const Color(0xFFB2AEC6),
      outline: light ? const Color(0xFF8B87A0) : const Color(0xFF7C7893),
      outlineVariant:
          light ? const Color(0xFFD9D4EA) : const Color(0xFF3B3A4F),
    );
  }

  static ThemeData _build(Brightness brightness) {
    final scheme = _scheme(brightness);
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final text = base.textTheme;

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text.copyWith(
        displaySmall: text.displaySmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        extendedTextStyle: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.primaryContainer,
        labelStyle: WidgetStateTextStyle.resolveWith(
          (states) => (text.labelLarge ?? const TextStyle()).copyWith(
            fontWeight: FontWeight.w700,
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      switchTheme: SwitchThemeData(
        thumbIcon: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Icon(Icons.check)
              : null,
        ),
      ),
    );
  }
}
