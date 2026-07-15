import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/collection_models.dart';
import 'collection_message_card.dart' show collectionChannelColor,
    collectionChannelIcon;

IconData collectionTriggerIcon(CollectionTrigger trigger) {
  switch (trigger) {
    case CollectionTrigger.daysBeforeDue:
      return LucideIcons.calendarClock;
    case CollectionTrigger.onDueDate:
      return LucideIcons.calendarCheck;
    case CollectionTrigger.daysAfterDue:
      return LucideIcons.alarmClock;
    case CollectionTrigger.unknown:
      return LucideIcons.calendarDays;
  }
}

/// Tom semântico do gatilho — antes = azul (lembrete), no dia = âmbar
/// (atenção), depois = vermelho (atraso).
Color collectionTriggerColor(BuildContext context, CollectionTrigger trigger) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (trigger) {
    case CollectionTrigger.daysBeforeDue:
      return isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    case CollectionTrigger.onDueDate:
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    case CollectionTrigger.daysAfterDue:
      return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    case CollectionTrigger.unknown:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

/// Item da lista de réguas — **linha flush** com ações no próprio item
/// (pausar/ativar, editar, excluir), coerente com o DNA do app. O corpo toca
/// para editar.
class CollectionRuleCard extends StatelessWidget {
  final CollectionRule rule;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;
  final VoidCallback? onDelete;

  /// Esconde as ações quando o usuário não tem `collection:manage`.
  final bool canManage;

  const CollectionRuleCard({
    super.key,
    required this.rule,
    this.onTap,
    this.onToggle,
    this.onDelete,
    this.canManage = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final triggerTone = collectionTriggerColor(context, rule.trigger);
    final channelTone = collectionChannelColor(context, rule.channel);

    // Régua inativa fica "apagada" — glyph neutro e conteúdo esmaecido.
    final glyphTone = rule.isActive ? triggerTone : neutral;
    final contentOpacity = rule.isActive ? 1.0 : 0.62;

    final description = rule.description?.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(
                opacity: contentOpacity,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    color: glyphTone.withValues(alpha: isDark ? 0.16 : 0.1),
                    border:
                        Border.all(color: glyphTone.withValues(alpha: 0.28)),
                  ),
                  child: Icon(collectionTriggerIcon(rule.trigger),
                      color: glyphTone, size: 21),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Opacity(
                  opacity: contentOpacity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _MiniPill(
                            label: rule.isActive ? 'Ativa' : 'Inativa',
                            color: rule.isActive ? green : neutral,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Prioridade ${rule.priority}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: neutral,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        rule.name.trim().isNotEmpty ? rule.name.trim() : 'Régua',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ThemeHelpers.textColor(context),
                          height: 1.2,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: neutral,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          _SpecBit(
                            icon: collectionTriggerIcon(rule.trigger),
                            text: rule.trigger.shortLabel(rule.triggerDays),
                            color: neutral,
                          ),
                          _SpecBit(
                            icon: collectionChannelIcon(rule.channel),
                            text: rule.channel.label,
                            color: rule.isActive ? channelTone : neutral,
                          ),
                          _SpecBit(
                            icon: LucideIcons.clock3,
                            text: rule.sendTimeShort,
                            color: neutral,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (canManage) ...[
                const SizedBox(width: 6),
                // Ações no próprio item — pausar/ativar, excluir.
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionIcon(
                      icon: rule.isActive
                          ? LucideIcons.pause
                          : LucideIcons.play,
                      tooltip: rule.isActive ? 'Desativar' : 'Ativar',
                      color: rule.isActive ? neutral : green,
                      onTap: onToggle,
                    ),
                    const SizedBox(height: 6),
                    _ActionIcon(
                      icon: LucideIcons.trash2,
                      tooltip: 'Excluir',
                      color: danger,
                      onTap: onDelete,
                    ),
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

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onTap;

  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        radius: 20,
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: color.withValues(alpha: isDark ? 0.14 : 0.09),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}

class _SpecBit extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _SpecBit({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: color,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _MiniPill extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniPill({required this.label, required this.color});

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
