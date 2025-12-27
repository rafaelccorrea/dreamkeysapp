import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../core/constants/app_assets.dart';

/// Widget de overlay de loading com blur e animação Lottie
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
    return Stack(
      children: [
        // Conteúdo principal
        child,
        
        // Overlay de loading
        if (isLoading)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
              child: Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: Lottie.asset(
                    AppAssets.loadingHome,
                    width: 80,
                    height: 80,
                    fit: BoxFit.contain,
                    repeat: true,
                    animate: true,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

