/// Constantes de caminhos de assets do aplicativo
/// Centraliza todos os caminhos de imagens, ícones, etc.
class AppAssets {
  AppAssets._();

  // Imagens
  /// Modo claro — mesmo `imobx-front/public/logo.png` (`LandingPage` header).
  static const String logoLight = 'assets/images/logo.png';
  /// Modo escuro — mesmo `imobx-front/public/logo-dark.png` (hero da landing).
  static const String logoDark = 'assets/images/logo-dark.png';
  /// Favicon / ícone geométrico (“i”) — `public/favicon.png` no front. Launcher / fallback apenas.
  static const String brandIcon = 'assets/images/intellisys_logo.png';
  static const String backgroundLogin = 'assets/images/background.jpg';

  // static const String jsonConfig = 'assets/data/config.json';
}
