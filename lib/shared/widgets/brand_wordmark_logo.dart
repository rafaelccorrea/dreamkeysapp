import 'package:flutter/material.dart';

import '../../core/constants/app_assets.dart';

/// `standard` — [BoxFit.contain] (uso genérico).
/// `appBar` — no **claro**: caixa fixa + [BoxFit.cover]. No **escuro**: [BoxFit.contain].
/// `loading` — splash/overlay: no **claro** igual ao appBar (corta área vazia do PNG); no **escuro**: [BoxFit.contain] (tamanho vem menor de [BrandWordmarkLoadingDimensions]).
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

    if (variant == BrandWordmarkVariant.loading) {
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

/// Dimensões da wordmark em loadings — **escuro** mais compacto; **claro** maior (o recorte [loading] compensa o PNG).
abstract final class BrandWordmarkLoadingDimensions {
  BrandWordmarkLoadingDimensions._();

  static double overlayLogoHeight(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? 62 : 108;
  }

  static double overlayLogoMaxWidth(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? 268 : 438;
  }

  static const double overlayProgressSize = 44;
  static const double overlayGapAfterLogo = 26;

  static double splashLogoHeight(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? 62 : 108;
  }

  static double splashStackHeight(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? 82 : 138;
  }

  static double splashMaxWidth(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return (screenW * 0.66).clamp(184.0, 288.0);
    }
    return (screenW * 0.85).clamp(252.0, 456.0);
  }
}
