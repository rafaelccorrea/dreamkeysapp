import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Widget base para skeleton com animação shimmer
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double? height;
  final double? borderRadius;
  final EdgeInsets? margin;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.margin,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _animation = Tween<double>(
      begin: -2.0,
      end: 2.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          margin: widget.margin,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius ?? 8),
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value, 0),
              colors: [
                isDark
                    ? AppColors.background.backgroundSecondaryDarkMode
                    : AppColors.background.backgroundSecondary,
                isDark
                    ? AppColors.background.backgroundTertiaryDarkMode
                    : AppColors.background.backgroundTertiary,
                isDark
                    ? AppColors.background.backgroundSecondaryDarkMode
                    : AppColors.background.backgroundSecondary,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton para texto
class SkeletonText extends StatelessWidget {
  final double? width;
  final double height;
  final double? borderRadius;
  final EdgeInsets? margin;

  const SkeletonText({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(
      width: width,
      height: height,
      borderRadius: borderRadius ?? 4,
      margin: margin,
    );
  }
}

/// Skeleton para card
class SkeletonCard extends StatelessWidget {
  final double? width;
  final double? height;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Widget? child;

  const SkeletonCard({
    super.key,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: width,
      height: height,
      margin: margin ?? const EdgeInsets.only(bottom: 16),
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.background.cardBackgroundDarkMode
            : AppColors.background.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? AppColors.border.borderDarkMode
              : AppColors.border.border,
          width: 1,
        ),
      ),
      child: child,
    );
  }
}

/// Skeleton para lista de itens
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  final EdgeInsets? padding;
  final Widget Function(BuildContext, int)? itemBuilder;

  const SkeletonList({
    super.key,
    this.itemCount = 5,
    this.itemHeight = 80,
    this.padding,
    this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: padding ?? EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      itemBuilder:
          itemBuilder ??
          (context, index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 48, height: 48, borderRadius: 8),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonText(
                          width: double.infinity,
                          height: 16,
                          margin: const EdgeInsets.only(bottom: 8),
                        ),
                        SkeletonText(width: 150, height: 14),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
    );
  }
}
