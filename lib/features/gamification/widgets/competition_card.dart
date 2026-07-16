// Card de competição — gramática das telas cânone: card sem borda lateral,
// sombra neutra, status com cor por significado, ações no próprio item.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../models/competition_models.dart';
import 'gamification_ui.dart';

final DateFormat _date = DateFormat('dd/MM/yyyy', 'pt_BR');

/// Cor semântica do status da competição.
Color competitionStatusColor(BuildContext context, CompetitionStatus status) {
  switch (status) {
    case CompetitionStatus.active:
      return gamGreen(context);
    case CompetitionStatus.scheduled:
      return gamBlue(context);
    case CompetitionStatus.draft:
      return gamAmber(context);
    case CompetitionStatus.finished:
      return ThemeHelpers.textSecondaryColor(context);
    case CompetitionStatus.cancelled:
      return gamDanger(context);
  }
}

IconData competitionStatusIcon(CompetitionStatus status) {
  switch (status) {
    case CompetitionStatus.active:
      return LucideIcons.play;
    case CompetitionStatus.scheduled:
      return LucideIcons.calendarClock;
    case CompetitionStatus.draft:
      return LucideIcons.pencilRuler;
    case CompetitionStatus.finished:
      return LucideIcons.flagTriangleRight;
    case CompetitionStatus.cancelled:
      return LucideIcons.ban;
  }
}

class CompetitionCard extends StatelessWidget {
  final Competition competition;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onPrizes;
  final VoidCallback? onFinalize;
  final VoidCallback? onDelete;
  final ValueChanged<CompetitionStatus>? onChangeStatus;

  const CompetitionCard({
    super.key,
    required this.competition,
    required this.onTap,
    this.onEdit,
    this.onPrizes,
    this.onFinalize,
    this.onDelete,
    this.onChangeStatus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final c = competition;
    final tone = competitionStatusColor(context, c.status);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final amber = gamAmber(context);

    final days = c.daysRemaining;
    final showCountdown =
        c.status == CompetitionStatus.active && days != null && days >= 0;

    final topPrize = c.prizes.isEmpty
        ? null
        : (c.prizes.toList()
              ..sort((a, b) => a.position.compareTo(b.position)))
            .first;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status + tipo + menu de ações
                Row(
                  children: [
                    GamMiniPill(
                      label: c.status.label,
                      color: tone,
                      icon: competitionStatusIcon(c.status),
                    ),
                    const SizedBox(width: 6),
                    GamMiniPill(
                      label: c.type.label,
                      color: c.type == CompetitionType.team
                          ? gamPurple(context)
                          : c.type == CompetitionType.mixed
                              ? gamBlue(context)
                              : gamAccentColor(context),
                      icon: c.type == CompetitionType.team
                          ? LucideIcons.users2
                          : c.type == CompetitionType.mixed
                              ? LucideIcons.blend
                              : LucideIcons.user,
                    ),
                    const Spacer(),
                    _actionsMenu(context),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  c.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: textColor,
                    letterSpacing: -0.3,
                    height: 1.15,
                  ),
                ),
                if ((c.description ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    c.description!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 12),

                // Métricas em linha (dias / prêmios / participantes / equipes)
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    if (showCountdown)
                      _metric(
                        context,
                        LucideIcons.timer,
                        days == 0
                            ? 'termina hoje'
                            : '$days dia${days == 1 ? '' : 's'} restante${days == 1 ? '' : 's'}',
                        amber,
                        emphasized: true,
                      ),
                    _metric(
                      context,
                      LucideIcons.gift,
                      '${c.prizes.length} prêmio${c.prizes.length == 1 ? '' : 's'}',
                      secondary,
                    ),
                    if (c.type != CompetitionType.team)
                      _metric(
                        context,
                        LucideIcons.users,
                        c.participantUserIds == null
                            ? 'Todos os corretores'
                            : '${c.participantUserIds!.length} corretor${c.participantUserIds!.length == 1 ? '' : 'es'}',
                        secondary,
                      ),
                    if (c.type != CompetitionType.individual)
                      _metric(
                        context,
                        LucideIcons.shield,
                        c.participantTeamIds == null
                            ? 'Todas as equipes'
                            : '${c.participantTeamIds!.length} equipe${c.participantTeamIds!.length == 1 ? '' : 's'}',
                        secondary,
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Período
                Row(
                  children: [
                    Icon(LucideIcons.calendarRange, size: 13, color: secondary),
                    const SizedBox(width: 6),
                    Text(
                      c.startDate != null ? _date.format(c.startDate!) : '—',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(LucideIcons.arrowRight,
                          size: 11, color: secondary),
                    ),
                    Text(
                      c.endDate != null ? _date.format(c.endDate!) : '—',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    if (c.autoStart || c.autoEnd)
                      Tooltip(
                        message: [
                          if (c.autoStart) 'Início automático',
                          if (c.autoEnd) 'Finalização automática',
                        ].join(' · '),
                        child: Icon(LucideIcons.zap,
                            size: 13, color: gamBlue(context)),
                      ),
                  ],
                ),

                // Prêmio do 1º lugar
                if (topPrize != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(colors: [
                        const Color(0xFFD4A017)
                            .withValues(alpha: isDark ? 0.18 : 0.1),
                        const Color(0xFFD4A017)
                            .withValues(alpha: isDark ? 0.06 : 0.03),
                      ]),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.trophy,
                            size: 15, color: Color(0xFFD4A017)),
                        const SizedBox(width: 8),
                        Text(
                          '${topPrize.position}º LUGAR',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: const Color(0xFFD4A017),
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                            fontSize: 9.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            topPrize.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: textColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, IconData icon, String label, Color tone,
      {bool emphasized = false}) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: tone),
        const SizedBox(width: 5),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: emphasized ? tone : ThemeHelpers.textSecondaryColor(context),
            fontWeight: emphasized ? FontWeight.w900 : FontWeight.w600,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _actionsMenu(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final danger = gamDanger(context);
    final hasAny = onEdit != null ||
        onPrizes != null ||
        onFinalize != null ||
        onDelete != null ||
        onChangeStatus != null;
    if (!hasAny) return const SizedBox.shrink();

    final c = competition;
    // Transições de status oferecidas (paridade StatusDropdown do web).
    final statusTargets = <CompetitionStatus>[
      if (c.status == CompetitionStatus.draft) ...[
        CompetitionStatus.scheduled,
        CompetitionStatus.active,
      ],
      if (c.status == CompetitionStatus.scheduled) ...[
        CompetitionStatus.draft,
        CompetitionStatus.active,
        CompetitionStatus.cancelled,
      ],
      if (c.status == CompetitionStatus.active) CompetitionStatus.cancelled,
    ];

    return SizedBox(
      width: 32,
      height: 32,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        tooltip: 'Ações',
        icon: Icon(LucideIcons.ellipsisVertical, size: 17, color: secondary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onSelected: (value) {
          if (value == 'edit') onEdit?.call();
          if (value == 'prizes') onPrizes?.call();
          if (value == 'finalize') onFinalize?.call();
          if (value == 'delete') onDelete?.call();
          if (value.startsWith('status:')) {
            onChangeStatus?.call(
              CompetitionStatus.fromRaw(value.substring(7)),
            );
          }
        },
        itemBuilder: (context) => [
          if (onEdit != null)
            _item(context, 'edit', LucideIcons.pencil, 'Editar'),
          if (onPrizes != null)
            _item(context, 'prizes', LucideIcons.gift, 'Prêmios'),
          if (onFinalize != null && c.canFinalize)
            _item(context, 'finalize', LucideIcons.trophy,
                'Finalizar competição'),
          if (onChangeStatus != null)
            for (final s in statusTargets)
              _item(
                context,
                'status:${s.value}',
                competitionStatusIcon(s),
                'Marcar como ${s.label.toLowerCase()}',
              ),
          if (onDelete != null && c.canDelete)
            PopupMenuItem<String>(
              value: 'delete',
              child: Row(
                children: [
                  Icon(LucideIcons.trash2, size: 15, color: danger),
                  const SizedBox(width: 10),
                  Text(
                    'Excluir',
                    style: TextStyle(
                      color: danger,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _item(
      BuildContext context, String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 15, color: ThemeHelpers.textSecondaryColor(context)),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }
}
