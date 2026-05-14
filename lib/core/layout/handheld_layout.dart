import 'package:flutter/foundation.dart';

/// Ajustes de layout e gestos para telemóveis (foco em iPhone).
abstract final class HandheldLayout {
  HandheldLayout._();

  static bool get isIosPhone =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Altura relativa do hero de login: ecrãs baixos (SE, etc.) recebem menos
  /// área fixa para sobrar espaço ao formulário.
  static double loginHeroHeightFraction(double screenHeight) {
    if (!isIosPhone) return 0.32;
    if (screenHeight < 620) return 0.26;
    if (screenHeight < 700) return 0.28;
    if (screenHeight < 780) return 0.30;
    return 0.32;
  }

  /// Margens horizontais do cartão de login — no iPhone evita paddings
  /// percentuais demasiado largos em 320–375 pt.
  static double loginFormHorizontalPadding(double width) {
    if (!isIosPhone) return width * 0.08;
    return (width * 0.065).clamp(16.0, 28.0);
  }
}
