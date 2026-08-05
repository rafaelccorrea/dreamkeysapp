import 'package:flutter/material.dart';

import '../../core/constants/app_assets.dart';

/// `standard` — [BoxFit.contain] (uso genérico).
/// `appBar` / `loading` — caixa com proporção fixa; [BoxFit.contain].
///
/// Os DOIS PNGs têm o mesmo canvas justo (702×166, sem respiro embutido) —
/// o `logo.png` claro foi recortado em 2026-08 (antes era 1080×1080 com 82%
/// de transparência, o que encolhia a marca no claro). Nunca reintroduzir
/// PNG com respiro: os temas se comportam idênticos.
enum BrandWordmarkVariant { standard, appBar, loading }

/// Wordmark Intellisys — `logo.png` (claro) / `logo-dark.png` (escuro).
class BrandWordmarkLogo extends StatelessWidget {
  const BrandWordmarkLogo({
    super.key,
    required this.height,
    this.maxWidth,
    this.alignment = Alignment.centerLeft,
    this.variant = BrandWordmarkVariant.standard,
  });

  final double height;
  final double? maxWidth;
  final Alignment alignment;
  final BrandWordmarkVariant variant;

  /// Mesma proporção do header da landing (~200×64).
  static const double _appBarAspect = 200 / 64;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppAssets.logoDark : AppAssets.logoLight;
    final secondary = isDark ? AppAssets.logoLight : AppAssets.logoDark;

    final w = variant == BrandWordmarkVariant.standard
        ? maxWidth
        : (maxWidth ?? (height * _appBarAspect));

    return _wordmarkImage(
      primary,
      height: height,
      width: w,
      fit: BoxFit.contain,
      imageAlignment: alignment,
      secondaryPath: secondary,
    );
  }

  Widget _wordmarkImage(
    String path, {
    required BoxFit fit,
    required Alignment imageAlignment,
    double? height,
    double? width,
    required String secondaryPath,
  }) {
    return Image.asset(
      path,
      height: height,
      width: width,
      fit: fit,
      alignment: imageAlignment,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) {
        return Image.asset(
          secondaryPath,
          height: height,
          width: width,
          fit: fit,
          alignment: imageAlignment,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, e, s) {
            return Image.asset(
              AppAssets.brandIcon,
              height: height,
              width: width,
              fit: BoxFit.contain,
            );
          },
        );
      },
    );
  }
}

/// Dimensões da wordmark em loadings — IGUAIS nos dois temas (os PNGs têm
/// o mesmo canvas justo; os valores maiores do claro compensavam o respiro
/// do PNG antigo).
abstract final class BrandWordmarkLoadingDimensions {
  BrandWordmarkLoadingDimensions._();

  static double overlayLogoHeight(BuildContext context) => 62;

  static double overlayLogoMaxWidth(BuildContext context) => 268;

  static const double overlayProgressSize = 44;
  static const double overlayGapAfterLogo = 26;

  static double splashLogoHeight(BuildContext context) => 62;

  static double splashStackHeight(BuildContext context) => 82;

  static double splashMaxWidth(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    return (screenW * 0.66).clamp(184.0, 288.0);
  }
}
