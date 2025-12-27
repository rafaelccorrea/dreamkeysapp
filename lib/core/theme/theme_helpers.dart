import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Helpers para obter cores que se adaptam ao tema (Light/Dark)
class ThemeHelpers {
  ThemeHelpers._();

  /// Retorna a cor de fundo de card baseada no tema
  static Color cardBackgroundColor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? AppColors.background.cardBackgroundDarkMode
        : AppColors.background.cardBackground;
  }

  /// Retorna a cor de fundo baseada no tema
  static Color backgroundColor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? AppColors.background.backgroundDarkMode
        : AppColors.background.background;
  }

  /// Retorna a cor de texto baseada no tema
  static Color textColor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? AppColors.text.textDarkMode
        : AppColors.text.text;
  }

  /// Retorna a cor de texto secundário baseada no tema
  static Color textSecondaryColor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? AppColors.text.textSecondaryDarkMode
        : AppColors.text.textSecondary;
  }

  /// Retorna a cor de borda baseada no tema
  static Color borderColor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? AppColors.border.borderDarkMode
        : AppColors.border.border;
  }

  /// Retorna a cor de borda clara baseada no tema
  static Color borderLightColor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? AppColors.border.borderLightDarkMode
        : AppColors.border.borderLight;
  }

  /// Retorna a cor de sombra baseada no tema
  static Color shadowColor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? Colors.black.withValues(alpha: 0.3)
        : Colors.black.withValues(alpha: 0.05);
  }

  /// Retorna a cor de texto sobre fundo primário (sempre branco ou preto conforme necessário)
  static Color onPrimaryColor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? const Color(0xFF111827) // Texto escuro sobre fundo claro no dark mode
        : Colors.white; // Texto branco sobre fundo escuro no light mode
  }

  /// Retorna a cor de fundo do AppBar baseada no tema
  static Color appBarBackgroundColor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? AppColors.background.backgroundDarkMode
        : AppColors.background.background;
  }
}
