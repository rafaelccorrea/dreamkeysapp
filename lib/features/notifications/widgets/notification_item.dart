import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/notification_model.dart';
import '../utils/notification_navigation.dart';
import '../../../core/theme/app_colors.dart';

/// Item individual de notificação
class NotificationItem extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const NotificationItem({
    super.key,
    required this.notification,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = notification.read
        ? Colors.transparent
        : (isDark
            ? AppColors.background.backgroundSecondaryDarkMode.withOpacity(0.3)
            : AppColors.primary.primary.withOpacity(0.05));

    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (direction) {
        onDelete?.call();
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.status.errorDarkMode
              : AppColors.status.error,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.delete,
          color: Colors.white,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: backgroundColor,
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? AppColors.border.borderDarkMode
                      : AppColors.border.border,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ícone de prioridade
                _PriorityIcon(priority: notification.priority),
                const SizedBox(width: 12),
                // Conteúdo
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Título
                      Text(
                        notification.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: notification.read
                              ? FontWeight.normal
                              : FontWeight.bold,
                          color: isDark
                              ? AppColors.text.textDarkMode
                              : AppColors.text.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Mensagem
                      Text(
                        notification.message,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.text.textSecondaryDarkMode
                              : AppColors.text.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      // Data e tipo
                      Row(
                        children: [
                          Text(
                            _formatDate(notification.createdAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.text.textLightDarkMode
                                  : AppColors.text.textLight,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.background.backgroundTertiaryDarkMode
                                  : AppColors.background.backgroundTertiary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              NotificationNavigation.getNotificationTypeLabel(
                                notification.type,
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 10,
                                color: isDark
                                    ? AppColors.text.textSecondaryDarkMode
                                    : AppColors.text.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Indicador de não lida
                if (!notification.read)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      color: _getPriorityColor(notification.priority, isDark),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Agora';
        }
        return '${difference.inMinutes}m atrás';
      }
      return '${difference.inHours}h atrás';
    } else if (difference.inDays == 1) {
      return 'Ontem';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d atrás';
    } else {
      return DateFormat('dd/MM/yyyy').format(date);
    }
  }

  Color _getPriorityColor(NotificationPriority priority, bool isDark) {
    switch (priority) {
      case NotificationPriority.urgent:
        return isDark
            ? AppColors.status.errorDarkMode
            : AppColors.status.error;
      case NotificationPriority.high:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case NotificationPriority.medium:
        return isDark
            ? AppColors.status.infoDarkMode
            : AppColors.status.info;
      case NotificationPriority.low:
        return isDark
            ? AppColors.text.textLightDarkMode
            : AppColors.text.textLight;
    }
  }
}

/// Ícone de prioridade
class _PriorityIcon extends StatelessWidget {
  final NotificationPriority priority;

  const _PriorityIcon({
    required this.priority,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _getPriorityColor(priority, isDark);
    final icon = _getPriorityIcon(priority);

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: color,
        size: 20,
      ),
    );
  }

  Color _getPriorityColor(NotificationPriority priority, bool isDark) {
    switch (priority) {
      case NotificationPriority.urgent:
        return isDark
            ? AppColors.status.errorDarkMode
            : AppColors.status.error;
      case NotificationPriority.high:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case NotificationPriority.medium:
        return isDark
            ? AppColors.status.infoDarkMode
            : AppColors.status.info;
      case NotificationPriority.low:
        return isDark
            ? AppColors.text.textLightDarkMode
            : AppColors.text.textLight;
    }
  }

  IconData _getPriorityIcon(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.urgent:
        return Icons.error;
      case NotificationPriority.high:
        return Icons.warning;
      case NotificationPriority.medium:
        return Icons.info;
      case NotificationPriority.low:
        return Icons.message;
    }
  }
}

