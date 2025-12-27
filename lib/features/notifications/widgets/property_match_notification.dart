import 'package:flutter/material.dart';
import '../models/notification_model.dart';
import '../../../core/theme/app_colors.dart';

/// Componente específico para notificações de match de propriedades
class PropertyMatchNotification extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback? onRead;

  const PropertyMatchNotification({
    super.key,
    required this.notification,
    this.onRead,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Extrair metadata
    final metadata = notification.metadata;
    if (metadata == null) {
      return const SizedBox.shrink();
    }

    final propertyTitle = metadata['propertyTitle']?.toString() ?? '';
    final totalMatches = metadata['totalMatches'] as int? ?? 0;
    final highScoreMatches = metadata['highScoreMatches'] as int? ?? 0;
    final propertyType = metadata['propertyType']?.toString();
    final propertyCity = metadata['propertyCity']?.toString();
    final propertyState = metadata['propertyState']?.toString();
    final propertyPrice = (metadata['propertyPrice'] as num?)?.toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.background.backgroundSecondaryDarkMode
            : AppColors.background.backgroundSecondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark
              ? AppColors.border.borderDarkMode
              : AppColors.border.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título da propriedade
          Text(
            propertyTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark
                  ? AppColors.text.textDarkMode
                  : AppColors.text.text,
            ),
          ),
          const SizedBox(height: 8),
          // Informações da propriedade
          if (propertyType != null || propertyCity != null)
            Row(
              children: [
                if (propertyType != null)
                  _InfoChip(
                    icon: Icons.home,
                    label: propertyType,
                    isDark: isDark,
                  ),
                if (propertyCity != null) ...[
                  const SizedBox(width: 8),
                  _InfoChip(
                    icon: Icons.location_on,
                    label: propertyCity +
                        (propertyState != null ? ', $propertyState' : ''),
                    isDark: isDark,
                  ),
                ],
              ],
            ),
          const SizedBox(height: 8),
          // Estatísticas de matches
          Row(
            children: [
              _StatBadge(
                label: 'Total de matches',
                value: totalMatches.toString(),
                color: isDark
                    ? AppColors.status.infoDarkMode
                    : AppColors.status.info,
                isDark: isDark,
              ),
              if (highScoreMatches > 0) ...[
                const SizedBox(width: 8),
                _StatBadge(
                  label: 'Alta compatibilidade',
                  value: highScoreMatches.toString(),
                  color: isDark
                      ? AppColors.status.successDarkMode
                      : AppColors.status.success,
                  isDark: isDark,
                ),
              ],
            ],
          ),
          // Preço se disponível
          if (propertyPrice != null) ...[
            const SizedBox(height: 8),
            Text(
              _formatPrice(propertyPrice),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark
                    ? AppColors.primary.primaryDarkMode
                    : AppColors.primary.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatPrice(double price) {
    if (price >= 1000000) {
      return 'R\$ ${(price / 1000000).toStringAsFixed(2)}M';
    } else if (price >= 1000) {
      return 'R\$ ${(price / 1000).toStringAsFixed(0)}k';
    }
    return 'R\$ ${price.toStringAsFixed(0)}';
  }
}

/// Chip de informação
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.background.backgroundTertiaryDarkMode
            : AppColors.background.backgroundTertiary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isDark
                ? AppColors.text.textSecondaryDarkMode
                : AppColors.text.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: isDark
                  ? AppColors.text.textSecondaryDarkMode
                  : AppColors.text.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge de estatística
class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  const _StatBadge({
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 10,
              color: isDark
                  ? AppColors.text.textSecondaryDarkMode
                  : AppColors.text.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

