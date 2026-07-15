import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/goal_model.dart';

/// Cor semântica do status da meta (clara/escura conforme tema).
Color goalStatusColor(BuildContext context, GoalStatus status) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (status) {
    case GoalStatus.active:
      return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    case GoalStatus.completed:
      return isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    case GoalStatus.failed:
      return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    case GoalStatus.draft:
    case GoalStatus.cancelled:
    case GoalStatus.unknown:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

/// Tom do progresso — verde quando no ritmo, âmbar quando exige atenção
/// (mesma regra do GoalCard web). Metas encerradas herdam a cor do status.
Color goalProgressColor(BuildContext context, Goal goal) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (goal.status == GoalStatus.completed) {
    return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
  }
  if (goal.status == GoalStatus.failed) {
    return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
  }
  if (goal.isOnTrack) {
    return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
  }
  return isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
}

/// Cor de identidade da meta — hex configurado pelo admin, com fallback na
/// cor da marca.
Color goalIdentityColor(BuildContext context, Goal goal) {
  final parsed = parseGoalHex(goal.color);
  if (parsed != null) return parsed;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
}

Color? parseGoalHex(String? hex) {
  final raw = hex?.trim();
  if (raw == null || raw.isEmpty) return null;
  var h = raw.replaceFirst('#', '').toUpperCase();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

IconData goalTypeIcon(GoalType type) {
  switch (type) {
    case GoalType.salesValue:
    case GoalType.salesCount:
      return LucideIcons.house;
    case GoalType.rentalValue:
    case GoalType.rentalCount:
      return LucideIcons.key;
    case GoalType.revenue:
      return LucideIcons.wallet;
    case GoalType.leads:
      return LucideIcons.users;
    case GoalType.conversions:
      return LucideIcons.handshake;
    case GoalType.conversionRate:
      return LucideIcons.percent;
    case GoalType.unknown:
      return LucideIcons.target;
  }
}

/// Ações disponíveis no card (espelham os botões do GoalCard web).
enum GoalCardAction { analytics, edit, duplicate, refresh, delete }

/// Card de meta — nome, período, alvo vs realizado com barra de progresso e
/// status. Ações principais visíveis no próprio item (Análise/Editar) e as
/// secundárias num menu compacto. Card branco com sombra neutra, sem borda
/// lateral colorida (gramática visual do app).
class GoalCard extends StatelessWidget {
  final Goal goal;
  final void Function(GoalCardAction action) onAction;

  const GoalCard({super.key, required this.goal, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final statusTone = goalStatusColor(context, goal.status);
    final progressTone = goalProgressColor(context, goal);
    final identity = goalIdentityColor(context, goal);
    final dateFmt = DateFormat('dd MMM', 'pt_BR');

    final periodRange = goal.startDate != null && goal.endDate != null
        ? '${dateFmt.format(goal.startDate!.toLocal())} – '
            '${dateFmt.format(goal.endDate!.toLocal())}'
        : null;

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ThemeHelpers.borderColor(context)
              .withValues(alpha: isDark ? 0.6 : 1),
        ),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onAction(GoalCardAction.analytics),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, theme, isDark, textColor, secondary,
                    statusTone, identity),
                const SizedBox(height: 12),
                _buildMetaChips(context, theme, secondary, periodRange),
                const SizedBox(height: 14),
                _buildProgress(
                    context, theme, isDark, textColor, secondary, progressTone),
                const SizedBox(height: 12),
                _buildFooter(context, theme, secondary, progressTone),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Header: glyph + título/tipo + status + menu ─────────────────────────

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    Color textColor,
    Color secondary,
    Color statusTone,
    Color identity,
  ) {
    final emoji = goal.icon?.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            color: identity.withValues(alpha: isDark ? 0.18 : 0.1),
            border: Border.all(color: identity.withValues(alpha: 0.3)),
          ),
          alignment: Alignment.center,
          child: emoji != null && emoji.isNotEmpty
              ? Text(emoji, style: const TextStyle(fontSize: 20, height: 1))
              : Icon(goalTypeIcon(goal.type), color: identity, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                goal.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  letterSpacing: -0.2,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                goal.type.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _StatusPill(label: goal.status.label, color: statusTone),
            if (!goal.isActive && goal.status == GoalStatus.active) ...[
              const SizedBox(height: 4),
              Text(
                'Inativa',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ─── Chips: período, escopo/responsável, datas ───────────────────────────

  Widget _buildMetaChips(BuildContext context, ThemeData theme,
      Color secondary, String? periodRange) {
    return Wrap(
      spacing: 10,
      runSpacing: 5,
      children: [
        _MetaBit(icon: LucideIcons.calendarSync, text: goal.period.label),
        _MetaBit(
          icon: goal.scope == GoalScope.user
              ? LucideIcons.user
              : goal.scope == GoalScope.team
                  ? LucideIcons.users2
                  : LucideIcons.building2,
          text: goal.ownerLabel ?? goal.scope.label,
        ),
        if (periodRange != null)
          _MetaBit(icon: LucideIcons.calendarDays, text: periodRange),
      ],
    );
  }

  // ─── Progresso: % + barra + alvo vs realizado ────────────────────────────

  Widget _buildProgress(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    Color textColor,
    Color secondary,
    Color tone,
  ) {
    final pct = goal.progress.clamp(0, 999).toDouble();
    final pctLabel =
        '${NumberFormat('#,##0.0', 'pt_BR').format(pct)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: formatGoalValue(goal.currentValue, goal.type),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: textColor,
                        letterSpacing: -0.4,
                      ),
                    ),
                    TextSpan(
                      text:
                          '  de ${formatGoalValue(goal.targetValue, goal.type)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              pctLabel,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: tone,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 8,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final ratio = goal.progressRatio;
                return Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      color: tone.withValues(alpha: isDark ? 0.16 : 0.12),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                      width: constraints.maxWidth * ratio,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: LinearGradient(
                          colors: [tone.withValues(alpha: 0.65), tone],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            if (goal.remaining > 0)
              _MetaBit(
                icon: LucideIcons.flag,
                text:
                    'Faltam ${formatGoalValue(goal.remaining, goal.type)}',
              ),
            _MetaBit(
              icon: LucideIcons.hourglass,
              text: goal.daysRemaining <= 0
                  ? 'Período encerrado'
                  : '${goal.daysRemaining} '
                      'dia${goal.daysRemaining == 1 ? '' : 's'} restante'
                      '${goal.daysRemaining == 1 ? '' : 's'}',
            ),
            _MetaBit(
              icon: goal.projectedValue >= goal.targetValue
                  ? LucideIcons.trendingUp
                  : LucideIcons.trendingDown,
              text:
                  'Projeção ${formatGoalValueCompact(goal.projectedValue, goal.type)}',
            ),
          ],
        ),
      ],
    );
  }

  // ─── Rodapé: ações no próprio item ───────────────────────────────────────

  Widget _buildFooter(BuildContext context, ThemeData theme, Color secondary,
      Color progressTone) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackLabel = goal.status == GoalStatus.completed
        ? 'Meta atingida'
        : goal.status == GoalStatus.failed
            ? 'Meta não atingida'
            : goal.isOnTrack
                ? 'No caminho'
                : 'Atenção ao ritmo';
    return Row(
      children: [
        Icon(
          goal.status == GoalStatus.completed
              ? LucideIcons.circleCheckBig
              : goal.isOnTrack && goal.status != GoalStatus.failed
                  ? LucideIcons.circleCheck
                  : LucideIcons.triangleAlert,
          size: 13,
          color: progressTone,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            trackLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: progressTone,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
        _ActionChip(
          icon: LucideIcons.chartLine,
          label: 'Análise',
          onTap: () => onAction(GoalCardAction.analytics),
        ),
        const SizedBox(width: 6),
        _ActionChip(
          icon: LucideIcons.pencil,
          label: 'Editar',
          onTap: () => onAction(GoalCardAction.edit),
        ),
        const SizedBox(width: 2),
        PopupMenuButton<GoalCardAction>(
          tooltip: 'Mais ações',
          position: PopupMenuPosition.under,
          color: ThemeHelpers.cardBackgroundColor(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: ThemeHelpers.borderLightColor(context)),
          ),
          onSelected: onAction,
          itemBuilder: (ctx) => [
            _menuItem(ctx, GoalCardAction.duplicate, LucideIcons.copy,
                'Duplicar meta'),
            _menuItem(ctx, GoalCardAction.refresh, LucideIcons.refreshCw,
                'Atualizar progresso'),
            _menuItem(
              ctx,
              GoalCardAction.delete,
              LucideIcons.trash2,
              'Excluir meta',
              color: isDark
                  ? AppColors.status.errorDarkMode
                  : AppColors.status.error,
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(LucideIcons.ellipsisVertical,
                size: 17, color: secondary),
          ),
        ),
      ],
    );
  }

  PopupMenuItem<GoalCardAction> _menuItem(
    BuildContext context,
    GoalCardAction action,
    IconData icon,
    String label, {
    Color? color,
  }) {
    final fg = color ?? ThemeHelpers.textColor(context);
    return PopupMenuItem<GoalCardAction>(
      value: action,
      height: 42,
      child: Row(
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Botão de ação tonal compacto — ação visível no próprio card.
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: ThemeHelpers.borderLightColor(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: secondary),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mini metadado (ícone + texto) — período, dias restantes, projeção.
class _MetaBit extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaBit({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: secondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: secondary,
            height: 1.2,
          ),
        ),
      ],
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
