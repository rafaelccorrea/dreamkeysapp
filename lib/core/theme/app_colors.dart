import 'package:flutter/material.dart';

/// Sistema de cores centralizado do aplicativo
/// Suporta Light Mode e Dark Mode
/// Baseado na documentação oficial de cores do Dream Keys
class AppColors {
  AppColors._();

  /// Cores primárias
  static final PrimaryColors primary = PrimaryColors._();

  /// Cores secundárias
  static final SecondaryColors secondary = SecondaryColors._();

  /// Cores de texto
  static final TextColors text = TextColors._();

  /// Cores de fundo
  static final BackgroundColors background = BackgroundColors._();

  /// Cores de borda
  static final BorderColors border = BorderColors._();

  /// Cores de status (sucesso, erro, aviso, etc)
  static final StatusColors status = StatusColors._();

  /// Cores de mensagens
  static final MessageColors message = MessageColors._();

  /// Cores de hover
  static final HoverColors hover = HoverColors._();
}

/// Cores primárias
class PrimaryColors {
  PrimaryColors._();

  /// Cor primária principal (Light Mode)
  final Color primary = const Color(0xFF1c4eff);

  /// Cor primária principal (Dark Mode)
  final Color primaryDarkMode = const Color(0xFF60a5fa);

  /// Tom mais escuro da primária (Light Mode)
  final Color primaryDark = const Color(0xFF153abf);

  /// Tom mais escuro da primária (Dark Mode)
  final Color primaryDarkDarkMode = const Color(0xFF3b82f6);

  /// Tom ainda mais escuro (Light Mode)
  final Color primaryDarker = const Color(0xFF0e2780);

  /// Tom ainda mais escuro (Dark Mode)
  final Color primaryDarkerDarkMode = const Color(0xFF2563eb);

  /// Tom mais escuro possível (Light Mode)
  final Color primaryDarkest = const Color(0xFF0a1f5c);

  /// Tom mais escuro possível (Dark Mode)
  final Color primaryDarkestDarkMode = const Color(0xFF1d4ed8);

  /// Tom mais claro da primária (Light Mode)
  final Color primaryLight = const Color(0xFF3b82f6);

  /// Tom mais claro da primária (Dark Mode)
  final Color primaryLightDarkMode = const Color(0xFF93c5fd);
}

/// Cores secundárias
class SecondaryColors {
  SecondaryColors._();

  /// Cor secundária (usa a mesma em ambos os modos)
  final Color secondary = const Color(0xFF6B7280);
}

/// Cores de texto
class TextColors {
  TextColors._();

  /// Texto principal (Light Mode)
  final Color text = const Color(0xFF4B5563);

  /// Texto principal (Dark Mode)
  final Color textDarkMode = const Color(0xFFf9fafb);

  /// Texto secundário (Light Mode)
  final Color textSecondary = const Color(0xFF6B7280);

  /// Texto secundário (Dark Mode)
  final Color textSecondaryDarkMode = const Color(0xFFFFFFFF);

  /// Texto claro/desabilitado (Light Mode)
  final Color textLight = const Color(0xFF9CA3AF);

  /// Texto claro/desabilitado (Dark Mode)
  final Color textLightDarkMode = const Color(0xFF9ca3af);
}

/// Cores de fundo
class BackgroundColors {
  BackgroundColors._();

  /// Fundo principal (Light Mode)
  final Color background = const Color(0xFFFFFFFF);

  /// Fundo principal (Dark Mode)
  final Color backgroundDarkMode = const Color(0xFF111827);

  /// Fundo secundário (Light Mode)
  final Color backgroundSecondary = const Color(0xFFf1f5f9);

  /// Fundo secundário (Dark Mode)
  final Color backgroundSecondaryDarkMode = const Color(0xFF1f2937);

  /// Fundo terciário (Light Mode)
  final Color backgroundTertiary = const Color(0xFFf8fafc);

  /// Fundo terciário (Dark Mode)
  final Color backgroundTertiaryDarkMode = const Color(0xFF374151);

  /// Fundo de card (Light Mode)
  final Color cardBackground = const Color(0xFFFFFFFF);

  /// Fundo de card (Dark Mode)
  final Color cardBackgroundDarkMode = const Color(0xFF1f2937);

  /// Superfície (elementos elevados) (Light Mode)
  final Color surface = const Color(0xFFFFFFFF);

  /// Superfície (elementos elevados) (Dark Mode)
  final Color surfaceDarkMode = const Color(0xFF1f2937);
}

/// Cores de borda
class BorderColors {
  BorderColors._();

  /// Borda padrão (Light Mode)
  final Color border = const Color(0xFFe1e5e9);

  /// Borda padrão (Dark Mode)
  final Color borderDarkMode = const Color(0xFF374151);

  /// Borda clara/sutil (Light Mode)
  final Color borderLight = const Color(0xFFf1f5f9);

  /// Borda clara/sutil (Dark Mode)
  final Color borderLightDarkMode = const Color(0xFF4b5563);
}

/// Cores de status
class StatusColors {
  StatusColors._();

  /// Sucesso (Light Mode)
  final Color success = const Color(0xFF10b981);

  /// Sucesso (Dark Mode)
  final Color successDarkMode = const Color(0xFF34d399);

  /// Erro (Light Mode)
  final Color error = const Color(0xFFef4444);

  /// Erro (Dark Mode)
  final Color errorDarkMode = const Color(0xFFef4444);

  /// Aviso (Light Mode)
  final Color warning = const Color(0xFFf59e0b);

  /// Aviso (Dark Mode)
  final Color warningDarkMode = const Color(0xFFfcd34d);

  /// Info (Light Mode)
  final Color info = const Color(0xFF3b82f6);

  /// Info (Dark Mode)
  final Color infoDarkMode = const Color(0xFF60a5fa);

  /// Verde (Light Mode)
  final Color green = const Color(0xFF10b981);

  /// Verde (Dark Mode)
  final Color greenDarkMode = const Color(0xFF34d399);

  /// Azul (Light Mode)
  final Color blue = const Color(0xFF3b82f6);

  /// Azul (Dark Mode)
  final Color blueDarkMode = const Color(0xFF60a5fa);

  /// Amarelo (Light Mode)
  final Color yellow = const Color(0xFFf59e0b);

  /// Amarelo (Dark Mode)
  final Color yellowDarkMode = const Color(0xFFfcd34d);

  /// Roxo (Light Mode)
  final Color purple = const Color(0xFF8b5cf6);

  /// Roxo (Dark Mode)
  final Color purpleDarkMode = const Color(0xFFa78bfa);

  /// Vermelho (Light Mode)
  final Color red = const Color(0xFFef4444);

  /// Vermelho (Dark Mode)
  final Color redDarkMode = const Color(0xFFef4444);
}

/// Cores de mensagens
class MessageColors {
  MessageColors._();

  /// Fundo de mensagem de sucesso (Light Mode)
  final Color successBackground = const Color(0xFFf0fdf4);

  /// Fundo de mensagem de sucesso (Dark Mode)
  final Color successBackgroundDarkMode = const Color(0xFF064e3b);

  /// Borda de mensagem de sucesso (Light Mode)
  final Color successBorder = const Color(0xFFbbf7d0);

  /// Borda de mensagem de sucesso (Dark Mode)
  final Color successBorderDarkMode = const Color(0xFF065f46);

  /// Texto de mensagem de sucesso (Light Mode)
  final Color successText = const Color(0xFF16a34a);

  /// Texto de mensagem de sucesso (Dark Mode)
  final Color successTextDarkMode = const Color(0xFF34d399);

  /// Fundo de mensagem de erro (Light Mode)
  final Color errorBackground = const Color(0xFFfef2f2);

  /// Fundo de mensagem de erro (Dark Mode)
  final Color errorBackgroundDarkMode = const Color(0xFF450a0a);

  /// Borda de mensagem de erro (Light Mode)
  final Color errorBorder = const Color(0xFFfecaca);

  /// Borda de mensagem de erro (Dark Mode)
  final Color errorBorderDarkMode = const Color(0xFF7f1d1d);

  /// Texto de mensagem de erro (Light Mode)
  final Color errorText = const Color(0xFFdc2626);

  /// Texto de mensagem de erro (Dark Mode)
  final Color errorTextDarkMode = const Color(0xFFfca5a5);

  /// Fundo de mensagem de aviso (Light Mode)
  final Color warningBackground = const Color(0xFFfffbeb);

  /// Fundo de mensagem de aviso (Dark Mode)
  final Color warningBackgroundDarkMode = const Color(0xFF451a03);

  /// Borda de mensagem de aviso (Light Mode)
  final Color warningBorder = const Color(0xFFfed7aa);

  /// Borda de mensagem de aviso (Dark Mode)
  final Color warningBorderDarkMode = const Color(0xFF78350f);

  /// Texto de mensagem de aviso (Light Mode)
  final Color warningText = const Color(0xFFd97706);

  /// Texto de mensagem de aviso (Dark Mode)
  final Color warningTextDarkMode = const Color(0xFFfcd34d);

  /// Fundo de mensagem de info (Light Mode)
  final Color infoBackground = const Color(0xFFeff6ff);

  /// Fundo de mensagem de info (Dark Mode)
  final Color infoBackgroundDarkMode = const Color(0xFF1e3a8a);

  /// Borda de mensagem de info (Light Mode)
  final Color infoBorder = const Color(0xFFbfdbfe);

  /// Borda de mensagem de info (Dark Mode)
  final Color infoBorderDarkMode = const Color(0xFF1e40af);

  /// Texto de mensagem de info (Light Mode)
  final Color infoText = const Color(0xFF2563eb);

  /// Texto de mensagem de info (Dark Mode)
  final Color infoTextDarkMode = const Color(0xFF60a5fa);
}

/// Cores de hover
class HoverColors {
  HoverColors._();

  /// Cor de hover padrão (Light Mode)
  final Color hover = const Color(0xFFf8fafc);

  /// Cor de hover padrão (Dark Mode)
  final Color hoverDarkMode = const Color(0xFF374151);

  /// Cor de hover escura (Light Mode)
  final Color hoverDark = const Color(0xFFf1f5f9);

  /// Cor de hover escura (Dark Mode)
  final Color hoverDarkDarkMode = const Color(0xFF4b5563);
}
