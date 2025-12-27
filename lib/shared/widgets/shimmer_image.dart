import 'package:flutter/material.dart';
import 'skeleton_box.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_helpers.dart';

/// Widget de imagem com efeito shimmer durante o carregamento
class ShimmerImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;

  const ShimmerImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }

          // Mostrar shimmer enquanto carrega
          return Stack(
            fit: StackFit.expand,
            children: [
              SkeletonBox(
                width: width ?? double.infinity,
                height: height ?? double.infinity,
                borderRadius: borderRadius != null
                    ? (borderRadius!.topLeft.x > 0
                          ? borderRadius!.topLeft.x
                          : 0)
                    : 0,
              ),
              if (loadingProgress.expectedTotalBytes != null)
                Center(
                  child: CircularProgressIndicator(
                    value:
                        loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!,
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primary.primary,
                    ),
                  ),
                ),
            ],
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return errorWidget ??
              Container(
                width: width,
                height: height,
                color: isDark
                    ? AppColors.background.backgroundSecondaryDarkMode
                    : AppColors.background.backgroundSecondary,
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 48,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              );
        },
      ),
    );
  }
}
