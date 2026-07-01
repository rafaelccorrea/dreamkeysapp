import 'package:flutter/material.dart';

/// Sistema de cores centralizado — alinhado ao tema do painel web (imobx-front / `theme.ts`).
/// Primária vermelha da marca, secundária vinho, fundos e dark mode idênticos ao front.
class AppColors {
  AppColors._();

  static final PrimaryColors primary = PrimaryColors._();
  static final SecondaryColors secondary = SecondaryColors._();
  static final TextColors text = TextColors._();
  static final BackgroundColors background = BackgroundColors._();
  static final BorderColors border = BorderColors._();
  static final StatusColors status = StatusColors._();
  static final MessageColors message = MessageColors._();
  static final HoverColors hover = HoverColors._();
}

class PrimaryColors {
  PrimaryColors._();

  /// Light — principal
  final Color primary = const Color(0xFFD32F2F);

  /// Dark — principal (mais clara para contraste)
  final Color primaryDarkMode = const Color(0xFFE53935);

  final Color primaryDark = const Color(0xFFB71C1C);
  final Color primaryDarkDarkMode = const Color(0xFFD32F2F);

  final Color primaryDarker = const Color(0xFF8B1515);
  final Color primaryDarkerDarkMode = const Color(0xFFB71C1C);

  final Color primaryDarkest = const Color(0xFF5C0E0E);
  final Color primaryDarkestDarkMode = const Color(0xFF8B1515);

  /// Tom mais claro (light)
  final Color primaryLight = const Color(0xFFE53935);
  final Color primaryLightDarkMode = const Color(0xFFEF5350);
}

class SecondaryColors {
  SecondaryColors._();

  final Color secondary = const Color(0xFF592722);
  final Color secondaryDarkMode = const Color(0xFF7A3A34);
}

class TextColors {
  TextColors._();

  final Color text = const Color(0xFF1F2937);
  final Color textDarkMode = const Color(0xFFE6E6E6);

  final Color textSecondary = const Color(0xFF4B5563);
  final Color textSecondaryDarkMode = const Color(0xFFB3B3B3);

  final Color textLight = const Color(0xFF6B7280);
  final Color textLightDarkMode = const Color(0xFF9CA3AF);
}

class BackgroundColors {
  BackgroundColors._();

  // Cinza frio (não quase-branco): dá contraste para os cards brancos
  // "pularem" no light — antes era #F8FAFC e o app ficava chapado/morto.
  final Color background = const Color(0xFFE9ECF3);
  final Color backgroundDarkMode = const Color(0xFF0C0C16);

  final Color backgroundSecondary = const Color(0xFFF5F7FA);
  final Color backgroundSecondaryDarkMode = const Color(0xFF13131F);

  final Color backgroundTertiary = const Color(0xFFF0F4F8);
  final Color backgroundTertiaryDarkMode = const Color(0xFF1A1A2A);

  final Color cardBackground = const Color(0xFFFFFFFF);
  final Color cardBackgroundDarkMode = const Color(0xFF13131F);

  final Color surface = const Color(0xFFFFFFFF);
  final Color surfaceDarkMode = const Color(0xFF13131F);
}

class BorderColors {
  BorderColors._();

  // Um pouco mais definida (cool) que #E5E7EB para o contorno do card ler
  // limpo contra o fundo cinza — parte do refino de contraste no light.
  final Color border = const Color(0xFFDDE1E9);
  final Color borderDarkMode = const Color(0xFF1E1E30);

  final Color borderLight = const Color(0xFFF3F4F6);
  final Color borderLightDarkMode = const Color(0xFF252538);
}

class StatusColors {
  StatusColors._();

  final Color success = const Color(0xFF3FA66B);
  final Color successDarkMode = const Color(0xFF4FC77D);

  final Color error = const Color(0xFFDC2626);
  final Color errorDarkMode = const Color(0xFFEF5350);

  final Color warning = const Color(0xFFE6B84C);
  final Color warningDarkMode = const Color(0xFFE6B84C);

  final Color info = const Color(0xFF4A90E2);
  final Color infoDarkMode = const Color(0xFF4A90E2);

  final Color green = const Color(0xFF3FA66B);
  final Color greenDarkMode = const Color(0xFF4FC77D);

  final Color blue = const Color(0xFF4A90E2);
  final Color blueDarkMode = const Color(0xFF4A90E2);

  final Color yellow = const Color(0xFFE6B84C);
  final Color yellowDarkMode = const Color(0xFFE6B84C);

  final Color purple = const Color(0xFF8B5CF6);
  final Color purpleDarkMode = const Color(0xFFa78bfa);

  final Color red = const Color(0xFFDC2626);
  final Color redDarkMode = const Color(0xFFEF5350);
}

class MessageColors {
  MessageColors._();

  final Color successBackground = const Color(0xFFF0FDF4);
  final Color successBackgroundDarkMode = const Color(0xFF1A3A2A);

  final Color successBorder = const Color(0xFFBBF7D0);
  final Color successBorderDarkMode = const Color(0xFF2D8A4F);

  final Color successText = const Color(0xFF16A34A);
  final Color successTextDarkMode = const Color(0xFF4FC77D);

  final Color errorBackground = const Color(0xFFFEF2F2);
  final Color errorBackgroundDarkMode = const Color(0xFF3A1A1A);

  final Color errorBorder = const Color(0xFFFECACA);
  final Color errorBorderDarkMode = const Color(0xFFE53935);

  final Color errorText = const Color(0xFFB91C1C);
  final Color errorTextDarkMode = const Color(0xFFEF5350);

  final Color warningBackground = const Color(0xFFFFFBEB);
  final Color warningBackgroundDarkMode = const Color(0xFF3A2F1A);

  final Color warningBorder = const Color(0xFFFED7AA);
  final Color warningBorderDarkMode = const Color(0xFFD4A43A);

  final Color warningText = const Color(0xFFD97706);
  final Color warningTextDarkMode = const Color(0xFFE6B84C);

  final Color infoBackground = const Color(0xFFEFF6FF);
  final Color infoBackgroundDarkMode = const Color(0xFF1A2A3A);

  final Color infoBorder = const Color(0xFFBFDBFE);
  final Color infoBorderDarkMode = const Color(0xFF357ABD);

  final Color infoText = const Color(0xFF2563EB);
  final Color infoTextDarkMode = const Color(0xFF4A90E2);
}

class HoverColors {
  HoverColors._();

  final Color hover = const Color(0xFFF9FAFB);
  final Color hoverDarkMode = const Color(0xFF1A1A2A);

  final Color hoverDark = const Color(0xFFF3F4F6);
  final Color hoverDarkDarkMode = const Color(0xFF1E1E30);
}
