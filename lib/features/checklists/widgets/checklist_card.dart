import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/checklist_models.dart';

/// Cor semântica do status do checklist / item (clara/escura conforme tema).
Color checklistStatusColor(BuildContext context, ChecklistStatus status) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (status) {
    case ChecklistStatus.completed:
      return isDark
          ? AppColors.status.successDarkMode
          : AppColors.status.success;
    case ChecklistStatus.inProgress:
      return isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    case ChecklistStatus.pending:
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    case ChecklistStatus.skipped:
    case ChecklistStatus.unknown:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

IconData checklistTypeIcon(ChecklistType type) {
  switch (type) {
    case ChecklistType.sale:
      return LucideIcons.home;
    case ChecklistType.rental:
      return LucideIcons.key;
    case ChecklistType.unknown:
      return LucideIcons.listChecks;
  }
}

IconData checklistStatusIcon(ChecklistStatus status) {
  switch (status) {
    case ChecklistStatus.pending:
      return LucideIcons.circleDashed;
    case ChecklistStatus.inProgress:
      return LucideIcons.play;
    case ChecklistStatus.completed:
      return LucideIcons.circleCheck;
    case ChecklistStatus.skipped:
      return LucideIcons.skipForward;
    case ChecklistStatus.unknown:
      return LucideIcons.circleDashed;
  }
}

/// Item da lista de checklists — **linha flush** (sem card/sombra), mesmo DNA
/// dos cards de Comissões: glyph tonal do tipo, info no meio, progresso na
/// própria linha e ação de excluir no item.
class ChecklistCard extends StatelessWidget {
  final Checklist checklist;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const ChecklistCard({
    super.key,
    required this.checklist,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final tone = checklistStatusColor(context, checklist.status);
    final stats = checklist.stats;
    final pct = stats.completionPercentage.clamp(0, 100).toDouble();

    final title = (checklist.propertyTitle ?? '').trim().isNotEmpty
        ? checklist.propertyTitle!.trim()
        : 'Imóvel não especificado';
    final client = (checklist.clientName ?? '').trim();
    final dateFmt = DateFormat('dd/MM/yy', 'pt_BR');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom:
                  BorderSide(color: ThemeHelpers.borderLightColor(context)),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Glyph tonal do tipo (venda/aluguel).
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
                  border: Border.all(color: tone.withValues(alpha: 0.28)),
                ),
                child: Icon(checklistTypeIcon(checklist.type),
                    color: tone, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: _StatusPill(
                            label: checklist.status.label,
                            color: tone,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          checklist.type.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: neutral,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        if (checklist.startedAt != null)
                          Text(
                            dateFmt.format(checklist.startedAt!.toLocal()),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: neutral,
                              fontWeight: FontWeight.w700,
                              fontSize: 10.5,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      checklist.propertyCode != null &&
                              checklist.propertyCode!.isNotEmpty
                          ? '$title · CÓD ${checklist.propertyCode}'
                          : title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                        height: 1.2,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (client.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(LucideIcons.user, size: 12, color: neutral),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              client,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: neutral,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    // Progresso na própria linha: barra fina + contagem + %.
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: pct / 100,
                              minHeight: 5,
                              backgroundColor: ThemeHelpers.borderLightColor(
                                context,
                              ).withValues(alpha: 0.8),
                              valueColor: AlwaysStoppedAnimation<Color>(tone),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${stats.completedItems}/${stats.totalItems}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: neutral,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${pct.round()}%',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: tone,
                            fontWeight: FontWeight.w900,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 6),
                // Excluir direto no item (com confirmação na página).
                InkResponse(
                  radius: 20,
                  onTap: onDelete,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      LucideIcons.trash2,
                      size: 17,
                      color: neutral.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Pílula de status — tint da cor + texto na cor.
class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.3)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}
