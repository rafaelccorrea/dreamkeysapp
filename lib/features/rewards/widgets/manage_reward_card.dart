import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/reward_model.dart';
import 'rewards_ui.dart';

/// Card de prêmio na tela **Configurar Resgates** — visão do gestor com as
/// ações **no próprio item**: editar, ativar/desativar e excluir (cada uma só
/// aparece quando a página fornece o callback, isto é, quando o usuário tem a
/// permissão correspondente).
class ManageRewardCard extends StatelessWidget {
  final Reward reward;
  final VoidCallback? onEdit;
  final VoidCallback? onToggleActive;
  final VoidCallback? onDelete;
  final bool busy;

  const ManageRewardCard({
    super.key,
    required this.reward,
    this.onEdit,
    this.onToggleActive,
    this.onDelete,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = rewardsAccent(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    final active = reward.isActive;
    final stockLeft = reward.availableStock;
    final description = (reward.description ?? '').trim();
    final glyphTone = active ? accent : secondary;

    return Opacity(
      opacity: active ? 1 : 0.72,
      child: Container(
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: BorderRadius.circular(18),
          boxShadow: ThemeHelpers.cardShadow(context),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        glyphTone.withValues(alpha: isDark ? 0.22 : 0.14),
                        glyphTone.withValues(alpha: isDark ? 0.1 : 0.05),
                      ],
                    ),
                    border:
                        Border.all(color: glyphTone.withValues(alpha: 0.22)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    reward.displayIcon,
                    style: const TextStyle(fontSize: 23, height: 1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reward.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ThemeHelpers.textColor(context),
                          letterSpacing: -0.2,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(LucideIcons.tag, size: 11, color: secondary),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              reward.category.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: secondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                RewardsStatusPill(
                  label: active ? 'Ativo' : 'Inativo',
                  color: active ? emerald : secondary,
                  icon: active ? LucideIcons.circleCheck : LucideIcons.circleOff,
                ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondary,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Métricas do prêmio — custo, valor, estoque e resgates.
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                RewardsPointsChip(points: reward.pointsCost),
                if (reward.monetaryValue != null && reward.monetaryValue! > 0)
                  _metric(
                    context,
                    LucideIcons.banknote,
                    rewardsMoneyFormat.format(reward.monetaryValue),
                    emerald,
                  ),
                _metric(
                  context,
                  LucideIcons.box,
                  reward.stockQuantity == null
                      ? 'Ilimitado'
                      : !reward.hasStock
                          ? 'Esgotado'
                          : '$stockLeft em estoque',
                  reward.stockQuantity != null && !reward.hasStock
                      ? amber
                      : secondary,
                ),
                _metric(
                  context,
                  LucideIcons.gift,
                  '${reward.redeemedCount} resgate${reward.redeemedCount == 1 ? '' : 's'}',
                  secondary,
                ),
              ],
            ),
            if (onEdit != null || onToggleActive != null || onDelete != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (onEdit != null)
                    Expanded(
                      child: SizedBox(
                        height: 38,
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : onEdit,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accent,
                            side: BorderSide(
                                color: accent.withValues(alpha: 0.45)),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          icon: const Icon(LucideIcons.pencil, size: 14),
                          label: const Text('Editar'),
                        ),
                      ),
                    ),
                  if (onEdit != null && onToggleActive != null)
                    const SizedBox(width: 8),
                  if (onToggleActive != null)
                    Expanded(
                      child: SizedBox(
                        height: 38,
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : onToggleActive,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: active ? amber : emerald,
                            side: BorderSide(
                              color: (active ? amber : emerald)
                                  .withValues(alpha: 0.45),
                            ),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          icon: busy
                              ? const SizedBox(
                                  width: 13,
                                  height: 13,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : Icon(
                                  active
                                      ? LucideIcons.eyeOff
                                      : LucideIcons.eye,
                                  size: 14,
                                ),
                          label: Text(active ? 'Desativar' : 'Ativar'),
                        ),
                      ),
                    ),
                  if (onDelete != null) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 38,
                      height: 38,
                      child: IconButton(
                        onPressed: busy ? null : onDelete,
                        tooltip: 'Excluir prêmio',
                        style: IconButton.styleFrom(
                          foregroundColor: danger,
                          side: BorderSide(
                              color: danger.withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                        icon: const Icon(LucideIcons.trash2, size: 15),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metric(
      BuildContext context, IconData icon, String label, Color tone) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: tone),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: tone,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
