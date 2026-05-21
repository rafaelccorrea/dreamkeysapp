import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../models/kanban_subtask_models.dart';

/// Mapeamento de **tipo de atividade** para ícone/cor (paridade com
/// `imobx-front/src/constants/subTaskTypes.ts`).
class SubTaskTypeStyle {
  final IconData icon;
  final Color color;

  const SubTaskTypeStyle({required this.icon, required this.color});

  static SubTaskTypeStyle of(BuildContext context, SubTaskType? type) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (type == null) {
      return SubTaskTypeStyle(
        icon: LucideIcons.checkSquare,
        color: isDark
            ? AppColors.text.textSecondaryDarkMode
            : AppColors.text.textSecondary,
      );
    }
    switch (type) {
      case SubTaskType.ligar:
        return SubTaskTypeStyle(
          icon: LucideIcons.phone,
          color: isDark
              ? AppColors.status.greenDarkMode
              : AppColors.status.green,
        );
      case SubTaskType.email:
        return SubTaskTypeStyle(
          icon: LucideIcons.mail,
          color: const Color(0xFF3B82F6),
        );
      case SubTaskType.reuniao:
        return SubTaskTypeStyle(
          icon: LucideIcons.users,
          color: const Color(0xFF7C3AED),
        );
      case SubTaskType.tarefa:
        return SubTaskTypeStyle(
          icon: LucideIcons.checkSquare,
          color: const Color(0xFF6366F1),
        );
      case SubTaskType.almoco:
        return SubTaskTypeStyle(
          icon: LucideIcons.utensils,
          color: const Color(0xFFEA580C),
        );
      case SubTaskType.visita:
        return SubTaskTypeStyle(
          icon: LucideIcons.mapPin,
          color: const Color(0xFFEC4899),
        );
      case SubTaskType.whatsapp:
        return SubTaskTypeStyle(
          icon: LucideIcons.messageCircle,
          color: const Color(0xFF22C55E),
        );
    }
  }
}

/// Cor associada ao **bucket** de prazo (today / tomorrow / overdue / …).
Color subtaskBucketColor(BuildContext context, KanbanSubTask st) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (st.bucket) {
    case 'completed':
      return isDark
          ? AppColors.status.greenDarkMode
          : AppColors.status.green;
    case 'overdue':
      return isDark
          ? AppColors.status.errorDarkMode
          : AppColors.status.error;
    case 'today':
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    case 'tomorrow':
      return const Color(0xFF7C3AED);
    case 'scheduled':
      return const Color(0xFF6366F1);
    case 'no_date':
    default:
      return isDark
          ? AppColors.text.textSecondaryDarkMode
          : AppColors.text.textSecondary;
  }
}

/// Label curto e amigável para o bucket de prazo.
String subtaskBucketLabel(KanbanSubTask st) {
  switch (st.bucket) {
    case 'completed':
      return 'Concluída';
    case 'overdue':
      return 'Atrasada';
    case 'today':
      return 'Hoje';
    case 'tomorrow':
      return 'Amanhã';
    case 'scheduled':
      return 'Agendada';
    case 'no_date':
    default:
      return 'Sem prazo';
  }
}
