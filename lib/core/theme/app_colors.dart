import 'package:flutter/material.dart';

/// Paleta de cores do App Corretor
/// Suporta Light e Dark Mode
class AppColors {
  AppColors._();

  // Cores Primárias
  static final primary = _PrimaryColors();
  static final secondary = _SecondaryColors();

  // Cores de Texto
  static final text = _TextColors();

  // Cores de Fundo
  static final background = _BackgroundColors();

  // Cores de Borda
  static final border = _BorderColors();

  // Cores de Status
  static final status = _StatusColors();

  // Cores de Mensagens
  static final message = _MessageColors();

  // Cores de Hover
  static final hover = _HoverColors();
}

class _PrimaryColors {
  _PrimaryColors();
  // Light Mode
  final Color primary = const Color(0xFF1C4EFF);
  final Color primaryDark = const Color(0xFF153ABF);
  final Color primaryDarker = const Color(0xFF0E2780);
  final Color primaryDarkest = const Color(0xFF0A1F5C);
  final Color primaryLight = const Color(0xFF3B82F6);
  // Dark Mode
  final Color primaryDarkMode = const Color(0xFF60A5FA);
  final Color primaryDarkDarkMode = const Color(0xFF3B82F6);
  final Color primaryDarkerDarkMode = const Color(0xFF2563EB);
  final Color primaryDarkestDarkMode = const Color(0xFF1D4ED8);
  final Color primaryLightDarkMode = const Color(0xFF93C5FD);
}

class _SecondaryColors {
  _SecondaryColors();
  final Color secondary = const Color(0xFF6B7280);
}

class _TextColors {
  _TextColors();
  // Light Mode
  final Color text = const Color(0xFF4B5563);
  final Color textSecondary = const Color(0xFF6B7280);
  final Color textLight = const Color(0xFF9CA3AF);
  // Dark Mode
  final Color textDarkMode = const Color(0xFFF9FAFB);
  final Color textSecondaryDarkMode = const Color(0xFFFFFFFF);
  final Color textLightDarkMode = const Color(0xFF9CA3AF);
}

class _BackgroundColors {
  _BackgroundColors();
  // Light Mode
  final Color background = const Color(0xFFFFFFFF);
  final Color backgroundSecondary = const Color(0xFFF1F5F9);
  final Color backgroundTertiary = const Color(0xFFF8FAFC);
  final Color cardBackground = const Color(0xFFFFFFFF);
  final Color surface = const Color(0xFFFFFFFF);
  // Dark Mode
  final Color backgroundDarkMode = const Color(0xFF111827);
  final Color backgroundSecondaryDarkMode = const Color(0xFF1F2937);
  final Color backgroundTertiaryDarkMode = const Color(0xFF374151);
  final Color cardBackgroundDarkMode = const Color(0xFF1F2937);
  final Color surfaceDarkMode = const Color(0xFF1F2937);
}

class _BorderColors {
  _BorderColors();
  // Light Mode
  final Color border = const Color(0xFFE1E5E9);
  final Color borderLight = const Color(0xFFF1F5F9);
  // Dark Mode
  final Color borderDarkMode = const Color(0xFF374151);
  final Color borderLightDarkMode = const Color(0xFF4B5563);
}

class _StatusColors {
  _StatusColors();
  // Light Mode
  final Color success = const Color(0xFF10B981);
  final Color error = const Color(0xFFEF4444);
  final Color warning = const Color(0xFFF59E0B);
  final Color info = const Color(0xFF3B82F6);
  final Color green = const Color(0xFF10B981);
  final Color blue = const Color(0xFF3B82F6);
  final Color yellow = const Color(0xFFF59E0B);
  final Color purple = const Color(0xFF8B5CF6);
  final Color red = const Color(0xFFEF4444);
  // Dark Mode
  final Color successDarkMode = const Color(0xFF34D399);
  final Color errorDarkMode = const Color(0xFFEF4444);
  final Color warningDarkMode = const Color(0xFFFCD34D);
  final Color infoDarkMode = const Color(0xFF60A5FA);
  final Color greenDarkMode = const Color(0xFF34D399);
  final Color blueDarkMode = const Color(0xFF60A5FA);
  final Color yellowDarkMode = const Color(0xFFFCD34D);
  final Color purpleDarkMode = const Color(0xFFA78BFA);
  final Color redDarkMode = const Color(0xFFEF4444);
}

class _MessageColors {
  _MessageColors();
  
  // Success
  final successBackground = const Color(0xFFF0FDF4);
  final successBorder = const Color(0xFFBBF7D0);
  final successText = const Color(0xFF16A34A);
  final successBackgroundDark = const Color(0xFF064E3B);
  final successBorderDark = const Color(0xFF065F46);
  final successTextDark = const Color(0xFF34D399);
  
  // Error
  final errorBackground = const Color(0xFFFEF2F2);
  final errorBorder = const Color(0xFFFECACA);
  final errorText = const Color(0xFFDC2626);
  final errorBackgroundDark = const Color(0xFF450A0A);
  final errorBorderDark = const Color(0xFF7F1D1D);
  final errorTextDark = const Color(0xFFFCA5A5);
  
  // Warning
  final warningBackground = const Color(0xFFFFFBEB);
  final warningBorder = const Color(0xFFFED7AA);
  final warningText = const Color(0xFFD97706);
  final warningBackgroundDark = const Color(0xFF451A03);
  final warningBorderDark = const Color(0xFF78350F);
  final warningTextDark = const Color(0xFFFCD34D);
  
  // Info
  final infoBackground = const Color(0xFFEFF6FF);
  final infoBorder = const Color(0xFFBFDBFE);
  final infoText = const Color(0xFF2563EB);
  final infoBackgroundDark = const Color(0xFF1E3A8A);
  final infoBorderDark = const Color(0xFF1E40AF);
  final infoTextDark = const Color(0xFF60A5FA);
}

class _HoverColors {
  _HoverColors();
  // Light Mode
  final Color hover = const Color(0xFFF8FAFC);
  final Color hoverDark = const Color(0xFFF1F5F9);
  // Dark Mode
  final Color hoverDarkMode = const Color(0xFF374151);
  final Color hoverDarkDarkMode = const Color(0xFF4B5563);
}
