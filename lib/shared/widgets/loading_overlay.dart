import 'dart:ui';
import 'package:flutter/material.dart';

import 'brand_wordmark_logo.dart';

/// Overlay de loading com blur — marca `logo-dark.png` + progresso (sem Lottie azul).
class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Stack(
      children: [
        child,
        if (isLoading)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BrandWordmarkLogo(
                        height: BrandWordmarkLoadingDimensions.overlayLogoHeight,
                        maxWidth: BrandWordmarkLoadingDimensions.overlayLogoMaxWidth,
                        alignment: Alignment.center,
                      ),
                      SizedBox(
                        height: BrandWordmarkLoadingDimensions.overlayGapAfterLogo,
                      ),
                      SizedBox(
                        width: BrandWordmarkLoadingDimensions.overlayProgressSize,
                        height: BrandWordmarkLoadingDimensions.overlayProgressSize,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

