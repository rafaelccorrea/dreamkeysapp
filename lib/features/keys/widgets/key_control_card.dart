import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/key_model.dart' as key_models;

/// Card para exibir um controle de chave
class KeyControlCard extends StatelessWidget {
  final key_models.KeyControl control;
  final VoidCallback? onReturn;
  final VoidCallback? onViewHistory;

  const KeyControlCard({
    super.key,
    required this.control,
    this.onReturn,
    this.onViewHistory,
  });

  Color _getStatusColor(key_models.KeyControlStatus status) {
    switch (status) {
      case key_models.KeyControlStatus.checkedOut:
        return AppColors.status.warning;
      case key_models.KeyControlStatus.returned:
        return AppColors.status.success;
      case key_models.KeyControlStatus.overdue:
        return AppColors.status.error;
      case key_models.KeyControlStatus.lost:
        return AppColors.status.error;
    }
  }

  Color _getTypeColor(key_models.KeyControlType type) {
    switch (type) {
      case key_models.KeyControlType.showing:
        return Colors.blue;
      case key_models.KeyControlType.maintenance:
        return Colors.orange;
      case key_models.KeyControlType.inspection:
        return Colors.purple;
      case key_models.KeyControlType.cleaning:
        return Colors.green;
      case key_models.KeyControlType.other:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor(control.status);
    final typeColor = _getTypeColor(control.type);
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: ThemeHelpers.borderLightColor(context),
          width: 1,
        ),
      ),
      color: ThemeHelpers.cardBackgroundColor(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        typeColor.withValues(alpha: 0.2),
                        typeColor.withValues(alpha: 0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: typeColor.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.swap_horiz,
                    color: typeColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        control.key?.name ?? 'Chave',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              control.status.label,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: typeColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              control.type.label,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: typeColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onReturn != null || onViewHistory != null)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'return') {
                        onReturn?.call();
                      } else if (value == 'history') {
                        onViewHistory?.call();
                      }
                    },
                    itemBuilder: (context) => [
                      if (onReturn != null)
                        const PopupMenuItem(
                          value: 'return',
                          child: Row(
                            children: [
                              Icon(Icons.login, size: 18),
                              SizedBox(width: 8),
                              Text('Devolver'),
                            ],
                          ),
                        ),
                      if (onViewHistory != null)
                        const PopupMenuItem(
                          value: 'history',
                          child: Row(
                            children: [
                              Icon(Icons.history, size: 18),
                              SizedBox(width: 8),
                              Text('Histórico'),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Informações
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Retirada',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateFormat.format(DateTime.parse(control.checkoutDate)),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (control.expectedReturnDate != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Previsão',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateFormat.format(DateTime.parse(control.expectedReturnDate!)),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: control.status == key_models.KeyControlStatus.overdue
                                ? AppColors.status.error
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (control.actualReturnDate != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Devolvida',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateFormat.format(DateTime.parse(control.actualReturnDate!)),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.status.success,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (control.reason.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ThemeHelpers.cardBackgroundColor(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: ThemeHelpers.borderLightColor(context),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        control.reason,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (control.user != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.person,
                    size: 16,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    control.user!.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

