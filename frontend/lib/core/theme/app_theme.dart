import 'package:material_ui/material_ui.dart';

/// Light-first Coral-Orange Glassmorphism design system with full Dark Mode support.
class AppTheme {
  AppTheme._();

  // Brand Accent & Semantic Tokens
  static const Color coralPrimary = Color(0xFFF05A3E);
  static const Color coralGradientStart = Color(0xFFFF6B4A);
  static const Color coralGradientEnd = Color(0xFFE6482E);

  static const LinearGradient coralGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [coralGradientStart, coralGradientEnd],
  );

  // Typography
  static const Color charcoalText = Color(0xFF1A1D1F);
  static const Color slateMuted = Color(0xFF52606D);

  // Status & Highlight Badges
  static const Color mintBg = Color(0xFFE6F7F2);
  static const Color mintText = Color(0xFF0D9488);
  static const Color warmGold = Color(0xFFF59E0B);

  // Ambient Backdrop Gradient Stops
  static const Color lightBgTop = Color(0xFFFFE8E0);
  static const Color lightBgMid = Color(0xFFF7F8FA);
  static const Color lightBgBottom = Color(0xFFE6F2FF);

  static const Color darkBgTop = Color(0xFF151926);
  static const Color darkBgMid = Color(0xFF141720);
  static const Color darkBgBottom = Color(0xFF0F131C);

  static ThemeData get lightTheme {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: coralPrimary,
      brightness: Brightness.light,
    );
    final colorScheme = baseScheme.copyWith(
      primary: coralPrimary,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFFFE4DC),
      onPrimaryContainer: const Color(0xFF7A1D0D),
      secondary: const Color(0xFF0D9488),
      secondaryContainer: mintBg,
      onSecondaryContainer: mintText,
      tertiary: warmGold,
      tertiaryContainer: const Color(0xFFFEF3C7),
      onTertiaryContainer: const Color(0xFF92400E),
      surface: lightBgMid,
      onSurface: charcoalText,
      onSurfaceVariant: slateMuted,
      surfaceContainerLow: Colors.white.withValues(alpha: 0.78),
      surfaceContainerHighest: Colors.white.withValues(alpha: 0.62),
      outlineVariant: const Color(0xFFE2E8F0),
    );
    return _buildTheme(colorScheme);
  }

  static ThemeData get darkTheme {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: coralPrimary,
      brightness: Brightness.dark,
    );
    final colorScheme = baseScheme.copyWith(
      primary: coralGradientStart,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFF4A2018),
      onPrimaryContainer: const Color(0xFFFFD8CC),
      secondary: const Color(0xFF2DD4BF),
      secondaryContainer: const Color(0xFF133A36),
      onSecondaryContainer: const Color(0xFF5EEAD4),
      tertiary: warmGold,
      tertiaryContainer: const Color(0xFF3F2E12),
      onTertiaryContainer: const Color(0xFFFDE68A),
      surface: darkBgBottom,
      onSurface: const Color(0xFFF3F4F6),
      onSurfaceVariant: const Color(0xFF9CA3AF),
      surfaceContainerLow: const Color(0xFF1E2433),
      surfaceContainerHighest: const Color(0xFF262D3F),
      outlineVariant: const Color(0xFF2F374B),
    );
    return _buildTheme(colorScheme);
  }

  static ThemeData _buildTheme(ColorScheme colorScheme) {
    final isDark = colorScheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark ? darkBgBottom : lightBgMid,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark
            ? const Color(0xFF1E2433).withValues(alpha: 0.78)
            : Colors.white.withValues(alpha: 0.78),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.85),
          ),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? const Color(0xFF1E2433).withValues(alpha: 0.72)
            : Colors.white.withValues(alpha: 0.78),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.9),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.14)
                : const Color(0xFFE2E8F0),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 15,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: coralPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          minimumSize: const Size(64, 52),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.2)
                : const Color(0xFFD6DCE5),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark
            ? const Color(0xFF1E2433).withValues(alpha: 0.74)
            : Colors.white.withValues(alpha: 0.78),
        selectedColor: coralPrimary,
        labelStyle: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.9),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark
            ? const Color(0xFF1A2030).withValues(alpha: 0.94)
            : Colors.white.withValues(alpha: 0.92),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }
}
