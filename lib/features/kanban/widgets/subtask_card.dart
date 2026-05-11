import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/kanban_subtask_models.dart';
import 'subtask_visual_helpers.dart';

/// Linha **fluida** de uma subtarefa — sem caixa em volta, apenas
/// faixa-timeline lateral + ícone do tipo + conteúdo rico que respira.
///
/// Pensado pra conviver direto sobre o gradiente do shell, com **dividers
/// sutis** entre itens (gerenciados pelo pai), entregando densidade
/// editorial sem visual encapsulado.
class SubTaskCard extends StatelessWidget {
  final KanbanSubTask subtask;
  final bool showParentCard;
  final bool busy;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const SubTaskCard({
    super.key,
    required this.subtask,
    this.showParentCard = false,
    this.busy = false,
    this.onTap,
    this.onToggle,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    final typeStyle = SubTaskTypeStyle.of(context, subtask.taskType);
    final bucketColor = subtaskBucketColor(context, subtask);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: typeStyle.color.withValues(alpha: 0.08),
        highlightColor: typeStyle.color.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Timeline(color: bucketColor),
                const SizedBox(width: 10),
                _TypeIcon(style: typeStyle),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TitleRow(
                        title: subtask.title,
                        isCompleted: subtask.isCompleted,
                        statusLabel: subtaskBucketLabel(subtask),
                        statusColor: bucketColor,
                        statusIcon: _bucketIcon(subtask.bucket),
                      ),
                      if ((subtask.description ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtask.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: neutral,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ],
                      if (showParentCard &&
                          (subtask.parentTask?.title.isNotEmpty == true ||
                              (subtask.parentTaskTitle ?? '').isNotEmpty)) ...[
                        const SizedBox(height: 8),
                        _ParentCardLine(subtask: subtask),
                      ],
                      const SizedBox(height: 8),
                      _MetaWrap(
                        subtask: subtask,
                        typeStyle: typeStyle,
                        bucketColor: bucketColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _RightActions(
                  isCompleted: subtask.isCompleted,
                  color: bucketColor,
                  busy: busy,
                  onToggle: onToggle,
                  onEdit: onEdit,
                  onDelete: onDelete,
                  dangerColor: danger,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _bucketIcon(String bucket) {
    switch (bucket) {
      case 'completed':
        return LucideIcons.checkCircle2;
      case 'overdue':
        return LucideIcons.alertTriangle;
      case 'today':
        return LucideIcons.zap;
      case 'tomorrow':
        return LucideIcons.calendarClock;
      case 'scheduled':
        return LucideIcons.clock;
      case 'no_date':
      default:
        return LucideIcons.circle;
    }
  }
}

/// Divider sutil entre subtarefas (use no pai entre itens consecutivos).
class SubTaskDivider extends StatelessWidget {
  const SubTaskDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Recuo na esquerda para alinhar com o ícone do próximo item — dá
      // a sensação de "linha de tempo contínua" entre as tarefas.
      padding: const EdgeInsets.only(left: 12),
      child: Container(
        height: 1,
        color:
            ThemeHelpers.borderLightColor(context).withValues(alpha: 0.55),
      ),
    );
  }
}

// ─── Internals ──────────────────────────────────────────────────────────

class _Timeline extends StatelessWidget {
  final Color color;
  const _Timeline({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.85),
              color.withValues(alpha: 0.40),
            ],
          ),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _TypeIcon extends StatelessWidget {
  final SubTaskTypeStyle style;
  const _TypeIcon({required this.style});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            style.color.withValues(alpha: isDark ? 0.34 : 0.20),
            style.color.withValues(alpha: isDark ? 0.14 : 0.08),
          ],
        ),
        border: Border.all(
          color: style.color.withValues(alpha: isDark ? 0.5 : 0.32),
        ),
        boxShadow: [
          BoxShadow(
            color: style.color.withValues(alpha: isDark ? 0.18 : 0.10),
            blurRadius: 10,
            offset: const Offset(0, 3),
            spreadRadius: -3,
          ),
        ],
      ),
      child: Icon(style.icon, color: style.color, size: 19),
    );
  }
}

class _TitleRow extends StatelessWidget {
  final String title;
  final bool isCompleted;
  final String statusLabel;
  final Color statusColor;
  final IconData statusIcon;

  const _TitleRow({
    required this.title,
    required this.isCompleted,
    required this.statusLabel,
    required this.statusColor,
    required this.statusIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final neutral = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(statusIcon, size: 12, color: statusColor),
            const SizedBox(width: 5),
            Text(
              statusLabel.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                fontSize: 10,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            height: 1.22,
            letterSpacing: -0.25,
            decoration: isCompleted ? TextDecoration.lineThrough : null,
            decorationColor: neutral.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class _ParentCardLine extends StatelessWidget {
  final KanbanSubTask subtask;
  const _ParentCardLine({required this.subtask});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final accent = isDark
        ? const Color(0xFFFF4D67)
        : AppColors.primary.primary;

    final cardTitle =
        subtask.parentTask?.title ?? subtask.parentTaskTitle ?? '';
    final breadcrumb = <String>[];
    final teamName = subtask.parentTask?.teamName?.trim();
    final projectName = subtask.parentTask?.projectName?.trim();
    final columnTitle = subtask.parentTask?.columnTitle?.trim();
    if (projectName != null && projectName.isNotEmpty) {
      breadcrumb.add(projectName);
    }
    if (teamName != null && teamName.isNotEmpty) breadcrumb.add(teamName);
    if (columnTitle != null && columnTitle.isNotEmpty) {
      breadcrumb.add(columnTitle);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.07 : 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.22 : 0.12),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.folderKanban, size: 12, color: accent),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                    height: 1.2,
                  ),
                ),
                if (breadcrumb.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    breadcrumb.join(' › '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: neutral,
                      fontWeight: FontWeight.w700,
                      fontSize: 9.5,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaWrap extends StatelessWidget {
  final KanbanSubTask subtask;
  final SubTaskTypeStyle typeStyle;
  final Color bucketColor;

  const _MetaWrap({
    required this.subtask,
    required this.typeStyle,
    required this.bucketColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final pieces = <_MetaPiece>[];

    if (subtask.taskType != null) {
      pieces.add(_MetaPiece(
        icon: typeStyle.icon,
        label: subtask.taskType!.label,
        color: typeStyle.color,
        emphasis: true,
      ));
    }

    final due = _formatDue(subtask);
    if (due != null) {
      pieces.add(_MetaPiece(
        icon: LucideIcons.calendar,
        label: due,
        color: neutral,
      ));
    }

    if (subtask.assignedTo != null && subtask.assignedTo!.name.isNotEmpty) {
      pieces.add(_MetaPiece(
        icon: LucideIcons.user,
        label: _firstName(subtask.assignedTo!.name),
        color: neutral,
      ));
    }

    if ((subtask.commentsCount ?? 0) > 0) {
      pieces.add(_MetaPiece(
        icon: LucideIcons.messageSquare,
        label: '${subtask.commentsCount}',
        color: neutral,
      ));
    }

    final relativeCreated = _relativeShort(subtask.createdAt.toLocal());
    if (relativeCreated.isNotEmpty) {
      pieces.add(_MetaPiece(
        icon: LucideIcons.clock,
        label: 'criada $relativeCreated',
        color: neutral,
      ));
    }

    if (pieces.isEmpty) return const SizedBox.shrink();

    final widgets = <Widget>[];
    for (var i = 0; i < pieces.length; i++) {
      widgets.add(_pieceWidget(theme, pieces[i]));
      if (i < pieces.length - 1) widgets.add(_dot(neutral));
    }
    return Wrap(
      spacing: 4,
      runSpacing: 5,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: widgets,
    );
  }

  Widget _pieceWidget(ThemeData theme, _MetaPiece piece) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(piece.icon, size: 12, color: piece.color),
        const SizedBox(width: 4),
        Text(
          piece.label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: piece.color,
            fontWeight: piece.emphasis ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }

  Widget _dot(Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        '·',
        style: TextStyle(
          color: color.withValues(alpha: 0.5),
          fontWeight: FontWeight.w900,
          fontSize: 13,
        ),
      ),
    );
  }

  static String? _formatDue(KanbanSubTask st) {
    if (st.dueDate == null) return null;
    final d = st.dueDate!.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(d.year, d.month, d.day);

    String dateStr;
    if (dueDay == today) {
      dateStr = 'Hoje';
    } else if (dueDay == today.add(const Duration(days: 1))) {
      dateStr = 'Amanhã';
    } else if (dueDay == today.subtract(const Duration(days: 1))) {
      dateStr = 'Ontem';
    } else {
      dateStr = DateFormat("d MMM", 'pt_BR').format(d);
    }

    if (st.dueTime != null && st.dueTime!.isNotEmpty) {
      return '$dateStr · ${st.dueTime!}';
    }
    return dateStr;
  }

  static String _firstName(String full) {
    final parts = full.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    return parts.first;
  }

  static String _relativeShort(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'há ${diff.inHours} h';
    if (diff.inDays < 30) return 'há ${diff.inDays} d';
    return 'em ${DateFormat('dd/MM', 'pt_BR').format(when)}';
  }
}

class _MetaPiece {
  final IconData icon;
  final String label;
  final Color color;
  final bool emphasis;
  const _MetaPiece({
    required this.icon,
    required this.label,
    required this.color,
    this.emphasis = false,
  });
}

class _RightActions extends StatelessWidget {
  final bool isCompleted;
  final Color color;
  final bool busy;
  final VoidCallback? onToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final Color dangerColor;

  const _RightActions({
    required this.isCompleted,
    required this.color,
    required this.busy,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.dangerColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        _CheckCircle(
          completed: isCompleted,
          color: color,
          busy: busy,
          onTap: onToggle,
        ),
        if (onEdit != null || onDelete != null)
          _MoreMenu(
            busy: busy,
            onEdit: onEdit,
            onDelete: onDelete,
            dangerColor: dangerColor,
          ),
      ],
    );
  }
}

class _CheckCircle extends StatelessWidget {
  final bool completed;
  final Color color;
  final bool busy;
  final VoidCallback? onTap;

  const _CheckCircle({
    required this.completed,
    required this.color,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: completed ? color : Colors.transparent,
            border: Border.all(
              color: completed
                  ? color
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.7),
              width: 2,
            ),
            boxShadow: completed
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.32),
                      blurRadius: 10,
                      spreadRadius: -2,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                )
              : (completed
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 18)
                  : null),
        ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  final bool busy;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final Color dangerColor;

  const _MoreMenu({
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.dangerColor,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = ThemeHelpers.textSecondaryColor(context);
    return PopupMenuButton<String>(
      tooltip: 'Mais ações',
      enabled: !busy,
      icon: Icon(LucideIcons.moreHorizontal, size: 16, color: neutral),
      padding: EdgeInsets.zero,
      splashRadius: 16,
      onSelected: (key) {
        if (key == 'edit') onEdit?.call();
        if (key == 'delete') onDelete?.call();
      },
      itemBuilder: (ctx) => [
        if (onEdit != null)
          const PopupMenuItem<String>(
            value: 'edit',
            child: Row(
              children: [
                Icon(LucideIcons.edit2, size: 16),
                SizedBox(width: 10),
                Text('Editar'),
              ],
            ),
          ),
        if (onDelete != null)
          PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                Icon(LucideIcons.trash2, size: 16, color: dangerColor),
                const SizedBox(width: 10),
                Text(
                  'Excluir',
                  style: TextStyle(color: dangerColor),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
