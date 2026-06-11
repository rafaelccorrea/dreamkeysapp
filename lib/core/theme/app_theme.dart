import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  // Fonte Poppins
  static final _textTheme = GoogleFonts.poppinsTextTheme();

  static SnackBarThemeData _snackBarTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final onSurface = isDark
        ? AppColors.text.textDarkMode
        : AppColors.text.text;
    final card = isDark
        ? AppColors.background.cardBackgroundDarkMode
        : AppColors.background.cardBackground;
    final primary = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    final border = isDark
        ? AppColors.border.borderDarkMode
        : AppColors.border.border;

    return SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: card,
      elevation: 16,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: Color.lerp(
            border,
            primary,
            isDark ? 0.4 : 0.5,
          )!.withValues(alpha: isDark ? 0.85 : 0.65),
          width: 1.1,
        ),
      ),
      insetPadding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
      contentTextStyle: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.32,
        letterSpacing: -0.1,
        color: onSurface,
      ),
      actionTextColor: primary,
      showCloseIcon: false,
    );
  }

  /// Overlay dos menus ⋯ — repita em [PopupMenuButton] (color/shape/elevation) se o tema global não aparecer no overlay.
  static PopupMenuThemeData styledPopupMenu(Brightness brightness) =>
      _popupMenuTheme(brightness);

  /// Atalho com o brilho atual do [BuildContext].
  static PopupMenuThemeData styledPopupMenuOf(BuildContext context) =>
      styledPopupMenu(Theme.of(context).brightness);

  /// Menu dos três pontinhos (`PopupMenuButton`) — card com borda, sem tint M3.
  static PopupMenuThemeData _popupMenuTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final card = isDark
        ? AppColors.background.cardBackgroundDarkMode
        : AppColors.background.cardBackground;
    final border = isDark
        ? AppColors.border.borderDarkMode
        : AppColors.border.border;
    final onSurface = isDark
        ? AppColors.text.textDarkMode
        : AppColors.text.text;
    final iconTone = isDark
        ? AppColors.text.textSecondaryDarkMode
        : AppColors.text.textSecondary;

    return PopupMenuThemeData(
      color: card,
      surfaceTintColor: Colors.transparent,
      elevation: 20,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.52 : 0.14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: border.withValues(alpha: isDark ? 0.72 : 0.82),
          width: 1,
        ),
      ),
      textStyle: GoogleFonts.poppins(
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
        height: 1.28,
        letterSpacing: -0.12,
        color: onSurface,
      ),
      iconColor: iconTone,
      menuPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      position: PopupMenuPosition.under,
    );
  }

  /// Variante refinada para ações ⋯ sobre um card de imóvel (lista/grade/carrossel).
  static PopupMenuThemeData propertyTileActionsPopupMenu(
    Brightness brightness,
  ) {
    final isDark = brightness == Brightness.dark;
    final base = _popupMenuTheme(brightness);
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    final borderTone = isDark
        ? AppColors.border.borderDarkMode
        : AppColors.border.border;
    return base.copyWith(
      elevation: 28,
      menuPadding: const EdgeInsets.fromLTRB(5, 8, 5, 10),
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.62 : 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          width: 1.2,
          color: Color.lerp(
            borderTone,
            accent,
            isDark ? 0.52 : 0.42,
          )!.withValues(alpha: isDark ? 0.94 : 0.92),
        ),
      ),
    );
  }

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    textTheme: _textTheme,
    colorScheme: ColorScheme.light(
      primary: AppColors.primary.primary,
      secondary: AppColors.secondary.secondary,
      error: AppColors.status.error,
      surface: AppColors.background.surface,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onError: Colors.white,
      onSurface: AppColors.text.text,
    ),
    scaffoldBackgroundColor: AppColors.background.background,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background.background,
      elevation: 0,
      scrolledUnderElevation: 1,
      iconTheme: IconThemeData(color: AppColors.text.textSecondary),
      titleTextStyle: TextStyle(
        color: AppColors.text.textSecondary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: AppColors.background.cardBackground,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border.border, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.background.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border.border, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border.border, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primary.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.status.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.status.error, width: 2),
      ),
      labelStyle: TextStyle(color: AppColors.text.textSecondary, fontSize: 14),
      hintStyle: TextStyle(color: AppColors.text.textLight, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary.primary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        side: BorderSide(color: AppColors.primary.primary, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: AppColors.border.border,
      thickness: 1,
      space: 1,
    ),
    popupMenuTheme: _popupMenuTheme(Brightness.light),
    snackBarTheme: _snackBarTheme(Brightness.light),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: AppColors.primary.primary,
      linearTrackColor: AppColors.primary.primary.withOpacity(0.2),
      circularTrackColor: AppColors.primary.primary.withOpacity(0.2),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    textTheme: _textTheme.apply(
      bodyColor: const Color(0xFFF9FAFB),
      displayColor: const Color(0xFFF9FAFB),
    ),
    colorScheme: ColorScheme.dark(
      primary: AppColors.primary.primaryDarkMode,
      secondary: AppColors.secondary.secondaryDarkMode,
      error: AppColors.status.errorDarkMode,
      surface: AppColors.background.surfaceDarkMode,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onError: Colors.white,
      onSurface: AppColors.text.textDarkMode,
    ),
    scaffoldBackgroundColor: AppColors.background.backgroundDarkMode,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background.backgroundDarkMode,
      elevation: 0,
      scrolledUnderElevation: 1,
      iconTheme: IconThemeData(color: AppColors.text.textDarkMode),
      titleTextStyle: TextStyle(
        color: AppColors.text.textDarkMode,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    cardTheme: CardThemeData(
      color: AppColors.background.cardBackgroundDarkMode,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border.borderDarkMode, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.background.backgroundSecondaryDarkMode,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: AppColors.border.borderDarkMode,
          width: 1.5,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: AppColors.border.borderDarkMode,
          width: 1.5,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: AppColors.primary.primaryDarkMode,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: AppColors.status.errorDarkMode,
          width: 1.5,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.status.errorDarkMode, width: 2),
      ),
      labelStyle: TextStyle(
        color: AppColors.text.textSecondaryDarkMode,
        fontSize: 14,
      ),
      hintStyle: TextStyle(
        color: AppColors.text.textLightDarkMode,
        fontSize: 14,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary.primaryDarkMode,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary.primaryDarkMode,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        side: BorderSide(color: AppColors.primary.primaryDarkMode, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary.primaryDarkMode,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: AppColors.border.borderDarkMode,
      thickness: 1,
      space: 1,
    ),
    popupMenuTheme: _popupMenuTheme(Brightness.dark),
    snackBarTheme: _snackBarTheme(Brightness.dark),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: AppColors.primary.primaryDarkMode,
      linearTrackColor: AppColors.primary.primaryDarkMode.withOpacity(0.2),
      circularTrackColor: AppColors.primary.primaryDarkMode.withOpacity(0.2),
    ),
  );
}
