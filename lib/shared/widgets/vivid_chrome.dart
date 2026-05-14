import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_helpers.dart';

/// Superfícies e faixas hero (gradiente primário + secundário + borda), alinhado ao dashboard.
class VividChrome {
  VividChrome._();

  static const double _radius = 20;

  /// Faixa full-width (padding horizontal fica a cargo do pai).
  static Widget heroBanner(
    BuildContext context, {
    required Color accent,
    required String eyebrow,
    required String title,
    String? subtitle,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.16),
            AppColors.secondary.secondary.withValues(alpha: 0.09),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon, color: accent, size: 28),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow.toUpperCase(),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      letterSpacing: 1.05,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cartão estratégico — conteúdo solto dentro, borda suave.
  static Widget insetCard(
    BuildContext context, {
    required Color accent,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(
          color: accent.withValues(alpha: 0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }

  static Widget sectionLabel(
    BuildContext context,
    String text, {
    required Color accent,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                ),
          ),
        ],
      ),
    );
  }

  static Widget mutedMessage(
    BuildContext context,
    String text, {
    required Color accent,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text(
          text,
          style: TextStyle(
            color: ThemeHelpers.textSecondaryColor(context),
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
