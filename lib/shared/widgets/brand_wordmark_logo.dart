import 'package:flutter/material.dart';

import '../../core/constants/app_assets.dart';

/// `standard` — [BoxFit.contain] (splash, overlays).
/// `appBar` — no **claro**: caixa fixa + [BoxFit.cover] (corta margem do `logo.png`). No **escuro**: [BoxFit.contain] (inalterado).
enum BrandWordmarkVariant { standard, appBar }

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

    if (variant == BrandWordmarkVariant.appBar) {
      final w = maxWidth ?? (height * _appBarAspect);
      if (!isDark) {
        return SizedBox(
          width: w,
          height: height,
          child: ClipRect(
            child: _wordmarkImage(
              primary,
              width: w,
              height: height,
              fit: BoxFit.cover,
              imageAlignment: Alignment.center,
              secondaryPath: secondary,
            ),
          ),
        );
      }
      return _wordmarkImage(
        primary,
        height: height,
        width: w,
        fit: BoxFit.contain,
        imageAlignment: alignment,
        secondaryPath: secondary,
      );
    }

    return _wordmarkImage(
      primary,
      height: height,
      width: maxWidth,
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

/// Dimensões da wordmark em loadings full-screen (overlay com blur e splash inicial).
abstract final class BrandWordmarkLoadingDimensions {
  BrandWordmarkLoadingDimensions._();

  static const double overlayLogoHeight = 64;
  static const double overlayLogoMaxWidth = 280;
  static const double overlayProgressSize = 40;
  static const double overlayGapAfterLogo = 22;

  static const double splashLogoHeight = 64;
  static const double splashStackHeight = 88;

  static double splashMaxWidth(double screenWidth) =>
      (screenWidth * 0.72).clamp(200.0, 300.0);
}
