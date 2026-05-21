import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/kanban_subtask_models.dart';
import 'subtask_visual_helpers.dart';

/// Card visual de uma subtarefa — agora é um cartão de verdade com
/// fundo, borda e sombra, NÃO uma linha listada.
///
/// Estrutura:
///   [Stripe colorido lateral 4px] [conteúdo do card]
///
/// O conteúdo tem:
///   - Header: chip do bucket (status) + chip do tipo + ações à direita
///   - Título grande
///   - Descrição (opcional, 2 linhas)
///   - Parent card line (opcional)
///   - Meta footer com chips densos (data, autor, comentários, criada há)
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
    final completed = subtask.isCompleted;
    final cardBg = isDark
        ? AppColors.background.cardBackgroundDarkMode
        : AppColors.background.cardBackground;
    final borderColor = isDark
        ? AppColors.border.borderDarkMode
        : AppColors.border.border;

    // Cor de borda tintada na cor do bucket — substitui a stripe lateral
    // sem precisar de Row+stretch (que estourava layout em scroll vertical)
    // e sem violar a regra do Flutter de "borderRadius exige borda uniforme".
    final tintedBorder = completed
        ? borderColor.withValues(alpha: 0.55)
        : bucketColor.withValues(alpha: isDark ? 0.36 : 0.26);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: completed
            ? (isDark
                ? cardBg.withValues(alpha: 0.62)
                : cardBg.withValues(alpha: 0.86))
            : cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tintedBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.18)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
            spreadRadius: -6,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: (onEdit != null || onDelete != null)
              ? () => _showLongPressMenu(context, danger)
              : null,
          borderRadius: BorderRadius.circular(16),
          splashColor: bucketColor.withValues(alpha: 0.08),
          highlightColor: bucketColor.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Row 1: título grande + check (sem menu) ──────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        subtask.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ThemeHelpers.textColor(context),
                          height: 1.22,
                          letterSpacing: -0.25,
                          decoration: completed
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor:
                              neutral.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _CheckCircle(
                      completed: completed,
                      color: bucketColor,
                      busy: busy,
                      onTap: onToggle,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // ── Row 2: chips de contexto (status, tipo, prazo) ──
                _ContextChips(
                  bucketLabel: subtaskBucketLabel(subtask),
                  bucketColor: bucketColor,
                  bucketIcon: _bucketIcon(subtask.bucket),
                  typeStyle: typeStyle,
                  typeLabel: subtask.taskType?.label,
                  dueLabel: _formatDuePill(subtask),
                  dueIsOverdue: subtask.bucket == 'overdue',
                  dueIsToday: subtask.bucket == 'today',
                  dangerColor: danger,
                ),
                if ((subtask.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 9),
                  _ParentCardLine(subtask: subtask),
                ],
                const SizedBox(height: 9),
                // ── Row final: footer (autor + comentários + criada há) ──
                _FooterMeta(subtask: subtask),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Long-press menu — substitui o `_MoreMenu` no canto do card, mantendo
  /// a tela limpa mas sem perder as ações de editar/excluir.
  Future<void> _showLongPressMenu(BuildContext context, Color dangerColor) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final res = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: isDark
          ? AppColors.background.cardBackgroundDarkMode
          : AppColors.background.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ThemeHelpers.borderColor(ctx)
                    .withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            if (onEdit != null)
              ListTile(
                leading: const Icon(LucideIcons.edit2, size: 18),
                title: const Text('Editar'),
                onTap: () => Navigator.of(ctx).pop('edit'),
              ),
            if (onDelete != null)
              ListTile(
                leading: Icon(LucideIcons.trash2,
                    size: 18, color: dangerColor),
                title: Text('Excluir',
                    style: TextStyle(color: dangerColor)),
                onTap: () => Navigator.of(ctx).pop('delete'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (res == 'edit') onEdit?.call();
    if (res == 'delete') onDelete?.call();
  }

  String? _formatDuePill(KanbanSubTask st) {
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
      dateStr = DateFormat('d MMM', 'pt_BR').format(d);
    }
    if (st.dueTime != null && st.dueTime!.isNotEmpty) {
      return '$dateStr · ${st.dueTime!}';
    }
    return dateStr;
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

/// **DEPRECADO** — mantido por compatibilidade com a tela ainda não
/// migrada. Os cards novos têm separação por gap, não por divider.
/// Renderiza um `SizedBox` neutro de 10px.
class SubTaskDivider extends StatelessWidget {
  const SubTaskDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 10);
  }
}

// ─── Internals ──────────────────────────────────────────────────────────

/// Linha única e calma de "chips de contexto" — bucket, tipo, prazo.
/// Mantém densidade de informação sem virar "header bar" pesado: os chips
/// são inline, com bg sutilíssimo, e respiram com o resto do card.
class _ContextChips extends StatelessWidget {
  final String bucketLabel;
  final Color bucketColor;
  final IconData bucketIcon;
  final SubTaskTypeStyle typeStyle;
  final String? typeLabel;
  final String? dueLabel;
  final bool dueIsOverdue;
  final bool dueIsToday;
  final Color dangerColor;

  const _ContextChips({
    required this.bucketLabel,
    required this.bucketColor,
    required this.bucketIcon,
    required this.typeStyle,
    required this.typeLabel,
    required this.dueLabel,
    required this.dueIsOverdue,
    required this.dueIsToday,
    required this.dangerColor,
  });

  @override
  Widget build(BuildContext context) {
    final dueColor = dueIsOverdue
        ? dangerColor
        : (dueIsToday ? bucketColor : ThemeHelpers.textSecondaryColor(context));
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _BucketChip(
          label: bucketLabel,
          color: bucketColor,
          icon: bucketIcon,
        ),
        if (typeLabel != null && typeLabel!.isNotEmpty)
          _TypeChip(style: typeStyle, label: typeLabel!),
        if (dueLabel != null)
          _DueChip(
            label: dueLabel!,
            color: dueColor,
            emphasis: dueIsOverdue || dueIsToday,
          ),
      ],
    );
  }
}

/// Chip discreto de prazo. Não tem bg cheio — só borda + ícone tintados.
class _DueChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool emphasis;
  const _DueChip({
    required this.label,
    required this.color,
    required this.emphasis,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: emphasis
            ? color.withValues(alpha: isDark ? 0.12 : 0.07)
            : Colors.transparent,
        border: Border.all(
          color: emphasis
              ? color.withValues(alpha: isDark ? 0.32 : 0.22)
              : ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.calendar, size: 11.5, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: emphasis ? color : ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Footer com meta — assignee + comentários + "criada há…". Linha
/// horizontal de "pegadas" pequenas — informativa sem ser barulhenta.
class _FooterMeta extends StatelessWidget {
  final KanbanSubTask subtask;
  const _FooterMeta({required this.subtask});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final isDark = theme.brightness == Brightness.dark;

    final hasAssignee =
        subtask.assignedTo != null && subtask.assignedTo!.name.isNotEmpty;
    final commentsCount = subtask.commentsCount ?? 0;
    final createdRel = _relativeShort(subtask.createdAt.toLocal());

    if (!hasAssignee && commentsCount == 0 && createdRel.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        if (hasAssignee) ...[
          _AssigneeChip(
            name: subtask.assignedTo!.name,
            avatarUrl: subtask.assignedTo!.avatar,
            isDark: isDark,
          ),
          if (commentsCount > 0 || createdRel.isNotEmpty)
            const SizedBox(width: 8),
        ],
        if (commentsCount > 0) ...[
          Icon(LucideIcons.messageSquare, size: 12, color: muted),
          const SizedBox(width: 4),
          Text(
            '$commentsCount',
            style: theme.textTheme.labelSmall?.copyWith(
              color: muted,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
            ),
          ),
          if (createdRel.isNotEmpty) const SizedBox(width: 10),
        ],
        if (createdRel.isNotEmpty)
          Expanded(
            child: Text(
              'Criada $createdRel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.labelSmall?.copyWith(
                color: muted,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ),
      ],
    );
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

/// Chip do responsável com avatar (foto ou iniciais) + primeiro nome.
class _AssigneeChip extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final bool isDark;
  const _AssigneeChip({
    required this.name,
    required this.avatarUrl,
    required this.isDark,
  });

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  String get _firstName {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? name : parts.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final hasAvatar = (avatarUrl ?? '').isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: hasAvatar
                ? null
                : LinearGradient(
                    colors: [
                      const Color(0xFF7C3AED),
                      const Color(0xFF4F46E5),
                    ],
                  ),
            image: hasAvatar
                ? DecorationImage(
                    image: NetworkImage(avatarUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.10 : 0.4),
            ),
          ),
          alignment: Alignment.center,
          child: hasAvatar
              ? null
              : Text(
                  _initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
        ),
        const SizedBox(width: 5),
        Text(
          _firstName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

class _BucketChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _BucketChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: isDark ? 0.16 : 0.10),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.36 : 0.26),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final SubTaskTypeStyle style;
  final String label;
  const _TypeChip({required this.style, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: style.color.withValues(alpha: isDark ? 0.12 : 0.07),
        border: Border.all(
          color: style.color.withValues(alpha: isDark ? 0.28 : 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 12, color: style.color),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: style.color,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
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

