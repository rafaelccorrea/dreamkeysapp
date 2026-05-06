import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/notification_model.dart';
import '../utils/notification_type_style.dart';
import '../../../core/theme/app_colors.dart';

/// Item individual de notificação
///
/// Estilização espelha o intellisys-web:
/// - Border-left colorido por **tipo** de notificação (lead, sistema, etc.)
/// - Ícone temático em chip com fundo `tinted` na cor do tipo
/// - Pequeno chip com a categoria (ex.: "Lead", "Sistema", "Tarefa")
/// - Dot pulsante quando não lida
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
    final style = NotificationTypeStyle.fromType(notification.type);

    final unreadBg = isDark
        ? Colors.white.withValues(alpha: 0.03)
        : style.color.withValues(alpha: 0.05);

    final backgroundColor =
        notification.read ? Colors.transparent : unreadBg;

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
            decoration: BoxDecoration(
              color: backgroundColor,
              border: Border(
                left: BorderSide(
                  color: style.color,
                  width: 3,
                ),
                bottom: BorderSide(
                  color: isDark
                      ? AppColors.border.borderDarkMode
                      : AppColors.border.border,
                  width: 0.5,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(13, 13, 16, 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TypeIconChip(style: style),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: notification.read
                              ? FontWeight.w600
                              : FontWeight.w700,
                          letterSpacing: -0.1,
                          color: isDark
                              ? AppColors.text.textDarkMode
                              : AppColors.text.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.message,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.4,
                          color: isDark
                              ? AppColors.text.textSecondaryDarkMode
                              : AppColors.text.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _CategoryChip(style: style),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _formatDate(notification.createdAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? AppColors.text.textLightDarkMode
                                    : AppColors.text.textLight,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!notification.read)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: 8, top: 6),
                    decoration: BoxDecoration(
                      color: style.color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: style.color.withValues(alpha: 0.55),
                          blurRadius: 6,
                        ),
                      ],
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
}

/// Chip do ícone à esquerda com fundo `tinted` na cor do tipo.
class _TypeIconChip extends StatelessWidget {
  final NotificationTypeStyle style;

  const _TypeIconChip({required this.style});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: style.color.withValues(alpha: isDark ? 0.32 : 0.22),
          width: 1,
        ),
      ),
      child: Icon(
        style.icon,
        color: style.color,
        size: 20,
      ),
    );
  }
}

/// Chip da categoria (label + ponto de cor) ao lado da data.
class _CategoryChip extends StatelessWidget {
  final NotificationTypeStyle style;

  const _CategoryChip({required this.style});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: style.color.withValues(alpha: isDark ? 0.32 : 0.22),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: style.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            style.category.label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
              color: style.color,
            ),
          ),
        ],
      ),
    );
  }
}
