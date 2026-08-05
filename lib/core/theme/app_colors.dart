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

  // Contraste de modo claro DE FATO: principal quase-preto, secundário
  // um degrau mais escuro que o antigo (#4B5563 lia fraco no branco).
  final Color text = const Color(0xFF0F172A);
  final Color textDarkMode = const Color(0xFFE6E6E6);

  final Color textSecondary = const Color(0xFF475569);
  final Color textSecondaryDarkMode = const Color(0xFFB3B3B3);

  final Color textLight = const Color(0xFF64748B);
  final Color textLightDarkMode = const Color(0xFF9CA3AF);
}

class BackgroundColors {
  BackgroundColors._();

  // MODO CLARO DE FATO (reforma 2026-08): fundo BRANCO sólido — o cinza
  // "gelo" (#E9ECF3) dava sensação desbotada e de itens flutuando. No
  // branco, a separação vem de BORDAS/hairlines sólidas e tipografia
  // escura (não de sombras). Não voltar ao gelo.
  final Color background = const Color(0xFFFFFFFF);
  final Color backgroundDarkMode = const Color(0xFF0C0C16);

  final Color backgroundSecondary = const Color(0xFFF4F5F7);
  final Color backgroundSecondaryDarkMode = const Color(0xFF13131F);

  // Fill sólido de inputs/chips — legível SOBRE branco.
  final Color backgroundTertiary = const Color(0xFFEEF0F3);
  final Color backgroundTertiaryDarkMode = const Color(0xFF1A1A2A);

  final Color cardBackground = const Color(0xFFFFFFFF);
  final Color cardBackgroundDarkMode = const Color(0xFF13131F);

  final Color surface = const Color(0xFFFFFFFF);
  final Color surfaceDarkMode = const Color(0xFF13131F);
}

class BorderColors {
  BorderColors._();

  // Com fundo branco, a borda É a separação (não a sombra) — sólida e
  // nítida, sem virar grade pesada.
  final Color border = const Color(0xFFD6DAE1);
  final Color borderDarkMode = const Color(0xFF1E1E30);

  final Color borderLight = const Color(0xFFE8EAEE);
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

  final Color rose = const Color(0xFFEC4899);
  final Color roseDarkMode = const Color(0xFFF472B6);

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
