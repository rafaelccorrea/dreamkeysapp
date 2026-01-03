import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../core/routes/app_routes.dart';
import '../models/inspection_model.dart';

/// Card para exibir uma vistoria na listagem
class InspectionCard extends StatelessWidget {
  final Inspection inspection;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const InspectionCard({
    super.key,
    required this.inspection,
    this.onTap,
    this.onLongPress,
  });

  Color _getStatusColor(InspectionStatus status) {
    switch (status) {
      case InspectionStatus.scheduled:
        return AppColors.status.info;
      case InspectionStatus.inProgress:
        return AppColors.status.warning;
      case InspectionStatus.completed:
        return AppColors.status.success;
      case InspectionStatus.cancelled:
        return AppColors.status.error;
    }
  }

  Color _getTypeColor(InspectionType type) {
    switch (type) {
      case InspectionType.entry:
        return Colors.blue;
      case InspectionType.exit:
        return Colors.red;
      case InspectionType.maintenance:
        return Colors.orange;
      case InspectionType.sale:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor(inspection.status);
    final typeColor = _getTypeColor(inspection.type);
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: ThemeHelpers.borderLightColor(context),
          width: 1,
        ),
      ),
      color: ThemeHelpers.cardBackgroundColor(context),
      child: InkWell(
        onTap: onTap ??
            () {
              Navigator.of(context).pushNamed(
                AppRoutes.inspectionDetails(inspection.id),
              );
            },
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header com título e status
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ícone/avatar
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          typeColor.withOpacity(0.2),
                          typeColor.withOpacity(0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: typeColor.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.home_repair_service,
                      color: typeColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Título e informações
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          inspection.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            // Badge de tipo
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: typeColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: typeColor.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                inspection.type.label,
                                style: TextStyle(
                                  color: typeColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Badge de status
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: statusColor.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                inspection.status.label,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Informações adicionais
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    dateFormat.format(inspection.scheduledDate),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                  if (inspection.property != null) ...[
                    const SizedBox(width: 16),
                    Icon(
                      Icons.home,
                      size: 16,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        inspection.property!['title']?.toString() ?? 
                        inspection.property!['address']?.toString() ?? 
                        'Propriedade',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              // Valor e aprovação financeira
              if (inspection.value != null && inspection.value! > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.attach_money,
                      size: 16,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'R\$ ${inspection.value!.toStringAsFixed(2)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (inspection.hasFinancialApproval) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: inspection.approvalStatus == 'approved'
                              ? AppColors.status.success.withOpacity(0.1)
                              : inspection.approvalStatus == 'rejected'
                                  ? AppColors.status.error.withOpacity(0.1)
                                  : AppColors.status.warning.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          inspection.approvalStatus == 'approved'
                              ? 'Aprovado'
                              : inspection.approvalStatus == 'rejected'
                                  ? 'Rejeitado'
                                  : 'Pendente',
                          style: TextStyle(
                            fontSize: 10,
                            color: inspection.approvalStatus == 'approved'
                                ? AppColors.status.success
                                : inspection.approvalStatus == 'rejected'
                                    ? AppColors.status.error
                                    : AppColors.status.warning,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

