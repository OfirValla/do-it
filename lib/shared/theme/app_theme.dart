import 'package:flutter/material.dart';

/// Material 3 theme built on a four-colour palette
/// (https://colorhunt.co/palette/000000233d4dfe7f2deaecf0):
///
///   #FE7F2D orange   action colour: buttons, FAB, active occurrence, chips
///   #233D4D slate    attention surfaces, secondary text, dark-mode cards
///   #EAECF0 cloud    light-mode background, dark-mode text
///   #000000 black    dark-mode background, light-mode text, "done" badge
///
/// White text does not pass contrast on the orange, so everything on primary
/// is black. Every override is paired with its "on" colour and checked for
/// WCAG AA contrast.
class AppTheme {
  AppTheme._();

  static const Color orange = Color(0xFFFE7F2D);
  static const Color slate = Color(0xFF233D4D);
  static const Color cloud = Color(0xFFEAECF0);
  static const Color black = Color(0xFF000000);

  /// Brand colour, also used by the launcher icon and notification accent.
  static const Color seed = orange;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ColorScheme _scheme(Brightness brightness) {
    final light = brightness == Brightness.light;
    return ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
      // Primary: orange with black on top.
      primary: orange,
      onPrimary: black,
      primaryContainer: light ? const Color(0xFFFFDCC6) : const Color(0xFF4A2610),
      onPrimaryContainer:
          light ? const Color(0xFF3D1C05) : const Color(0xFFFFDCC6),
      // Secondary: slate, the "needs attention" role.
      secondary: light ? slate : const Color(0xFF9FB6C4),
      onSecondary: light ? cloud : const Color(0xFF0F1E28),
      secondaryContainer: slate,
      onSecondaryContainer: cloud,
      // Tertiary: black/cloud, the colour of getting it done.
      tertiary: light ? black : cloud,
      onTertiary: light ? cloud : black,
      tertiaryContainer:
          light ? const Color(0xFFD9DDE3) : const Color(0xFF3A4A55),
      onTertiaryContainer: light ? black : cloud,
      // Surfaces: cloud with white cards / true black with slate cards.
      surface: light ? cloud : black,
      onSurface: light ? black : cloud,
      surfaceContainerLowest: light ? Colors.white : black,
      surfaceContainerLow: light ? Colors.white : const Color(0xFF16262F),
      surfaceContainer: light ? const Color(0xFFF5F6F8) : const Color(0xFF1D3240),
      surfaceContainerHigh: light ? const Color(0xFFDFE2E8) : slate,
      surfaceContainerHighest:
          light ? const Color(0xFFD3D8DF) : const Color(0xFF2E4B5C),
      onSurfaceVariant: light ? slate : const Color(0xFFB7C4CD),
      outline: light ? const Color(0xFF6B7C88) : const Color(0xFF6F8592),
      outlineVariant:
          light ? const Color(0xFFC9D0D8) : const Color(0xFF34505F),
      inverseSurface: light ? slate : cloud,
      onInverseSurface: light ? cloud : black,
      inversePrimary: orange,
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
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.onSurface),
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
