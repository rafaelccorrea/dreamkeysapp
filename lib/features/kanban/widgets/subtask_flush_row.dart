import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/kanban_subtask_models.dart';
import 'subtask_visual_helpers.dart';

/// Linha **flush** de uma tarefa na lista global — mesmo DNA das filas de
/// Aprovação: sem card/sombra, separada por filete inferior. O check de
/// conclusão fica à esquerda (identidade da tela de tarefas), seguido pelo
/// bloco de conteúdo (chips de contexto, título, card pai e rodapé de meta).
///
/// Toque no corpo abre o card pai; toque no check alterna a conclusão;
/// pressionar e segurar abre o menu de excluir.
class SubTaskFlushRow extends StatelessWidget {
  final KanbanSubTask subtask;
  final bool busy;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;
  final VoidCallback? onDelete;

  const SubTaskFlushRow({
    super.key,
    required this.subtask,
    this.busy = false,
    this.onTap,
    this.onToggle,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final bucketColor = subtaskBucketColor(context, subtask);
    final typeStyle = SubTaskTypeStyle.of(context, subtask.taskType);
    final completed = subtask.isCompleted;

    final dueLabel = _formatDuePill(subtask);
    final hasParent = subtask.parentTask?.title.isNotEmpty == true ||
        (subtask.parentTaskTitle ?? '').isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onDelete != null ? () => _showMenu(context, danger) : null,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CheckCircle(
                completed: completed,
                color: bucketColor,
                busy: busy,
                onTap: onToggle,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Chips de contexto (status de prazo, tipo, prazo).
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Chip(
                          icon: _bucketIcon(subtask.bucket),
                          label: subtaskBucketLabel(subtask).toUpperCase(),
                          color: bucketColor,
                          filled: true,
                          letterSpacing: 0.8,
                        ),
                        if (subtask.taskType != null)
                          _Chip(
                            icon: typeStyle.icon,
                            label: subtask.taskType!.label,
                            color: typeStyle.color,
                            filled: false,
                          ),
                        if (dueLabel != null)
                          _Chip(
                            icon: LucideIcons.calendar,
                            label: dueLabel,
                            color: subtask.bucket == 'overdue'
                                ? danger
                                : (subtask.bucket == 'today'
                                    ? bucketColor
                                    : neutral),
                            filled: false,
                          ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    // Título.
                    Text(
                      subtask.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: completed
                            ? neutral
                            : ThemeHelpers.textColor(context),
                        height: 1.2,
                        letterSpacing: -0.2,
                        decoration:
                            completed ? TextDecoration.lineThrough : null,
                        decorationColor: neutral.withValues(alpha: 0.6),
                      ),
                    ),
                    if ((subtask.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtask.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: neutral,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (hasParent) ...[
                      const SizedBox(height: 7),
                      _ParentLine(subtask: subtask),
                    ],
                    const SizedBox(height: 8),
                    _FooterMeta(subtask: subtask),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context, Color danger) async {
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
                color: ThemeHelpers.borderColor(ctx).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(LucideIcons.trash2, size: 18, color: danger),
              title: Text('Excluir', style: TextStyle(color: danger)),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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

/// Chip genérico — tint cheio (filled) ou só contorno tonal.
class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool filled;
  final double letterSpacing;

  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
    required this.filled,
    this.letterSpacing = 0.2,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: filled
            ? color.withValues(alpha: isDark ? 0.16 : 0.10)
            : Colors.transparent,
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.34 : 0.24),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11.5, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: letterSpacing,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// Linha discreta do card pai (negociação) + breadcrumb projeto › time › coluna.
class _ParentLine extends StatelessWidget {
  final KanbanSubTask subtask;
  const _ParentLine({required this.subtask});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final cardTitle =
        subtask.parentTask?.title ?? subtask.parentTaskTitle ?? '';
    final crumbs = <String>[];
    final project = subtask.parentTask?.projectName?.trim();
    final team = subtask.parentTask?.teamName?.trim();
    final column = subtask.parentTask?.columnTitle?.trim();
    if (project != null && project.isNotEmpty) crumbs.add(project);
    if (team != null && team.isNotEmpty) crumbs.add(team);
    if (column != null && column.isNotEmpty) crumbs.add(column);

    return Row(
      children: [
        Icon(LucideIcons.folderKanban, size: 12, color: neutral),
        const SizedBox(width: 6),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: cardTitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
                if (crumbs.isNotEmpty)
                  TextSpan(
                    text: '   ${crumbs.join(' › ')}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: neutral,
                      fontWeight: FontWeight.w600,
                      fontSize: 9.5,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Rodapé de meta — responsável + comentários + "criada há…".
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
    final comments = subtask.commentsCount ?? 0;
    final createdRel = _relativeShort(subtask.createdAt.toLocal());

    if (!hasAssignee && comments == 0 && createdRel.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        if (hasAssignee) ...[
          _Avatar(
            name: subtask.assignedTo!.name,
            avatarUrl: subtask.assignedTo!.avatar,
            isDark: isDark,
          ),
          const SizedBox(width: 8),
        ],
        if (comments > 0) ...[
          Icon(LucideIcons.messageSquare, size: 12, color: muted),
          const SizedBox(width: 4),
          Text(
            '$comments',
            style: theme.textTheme.labelSmall?.copyWith(
              color: muted,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 10),
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

class _Avatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final bool isDark;
  const _Avatar({
    required this.name,
    required this.avatarUrl,
    required this.isDark,
  });

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
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
                : const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
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
          ),
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
    return InkResponse(
      onTap: busy ? null : onTap,
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: completed ? color : Colors.transparent,
            border: Border.all(
              color: completed
                  ? color
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.8),
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
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                )
              : (completed
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 17)
                  : null),
        ),
      ),
    );
  }
}
