import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/reward_model.dart';
import 'rewards_ui.dart';

/// Card do catálogo de prêmios — vitrine com sombra neutra (cardShadow), sem
/// borda lateral: glyph emoji tonal, nome + categoria, descrição, chips de
/// custo/valor/estoque e a ação **Resgatar** no próprio item.
class RewardCard extends StatelessWidget {
  final Reward reward;
  final int myPoints;
  final VoidCallback? onRedeem;

  const RewardCard({
    super.key,
    required this.reward,
    required this.myPoints,
    this.onRedeem,
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

    final affordable = reward.canAfford(myPoints);
    final inStock = reward.hasStock;
    final redeemable = affordable && inStock;
    final missing = reward.pointsNeeded(myPoints);
    final stockLeft = reward.availableStock;
    final description = (reward.description ?? '').trim();

    return Container(
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
              // Glyph emoji tonal (violeta do domínio).
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: isDark ? 0.22 : 0.14),
                      accent.withValues(alpha: isDark ? 0.1 : 0.05),
                    ],
                  ),
                  border:
                      Border.all(color: accent.withValues(alpha: 0.22)),
                ),
                alignment: Alignment.center,
                child: Text(
                  reward.displayIcon,
                  style: const TextStyle(fontSize: 25, height: 1),
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
              RewardsPointsChip(points: reward.pointsCost, emphasized: true),
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
          Row(
            children: [
              if (reward.monetaryValue != null &&
                  reward.monetaryValue! > 0) ...[
                Icon(LucideIcons.banknote, size: 13, color: emerald),
                const SizedBox(width: 4),
                Text(
                  rewardsMoneyFormat.format(reward.monetaryValue),
                  style: TextStyle(
                    color: emerald,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Icon(
                LucideIcons.box,
                size: 13,
                color: inStock ? secondary : amber,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  !inStock
                      ? 'Esgotado'
                      : stockLeft == null
                          ? 'Estoque ilimitado'
                          : '$stockLeft disponíve${stockLeft == 1 ? 'l' : 'is'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: inStock ? secondary : amber,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Ação no próprio item: resgatar / quanto falta / esgotado.
          if (redeemable)
            SizedBox(
              width: double.infinity,
              height: 42,
              child: FilledButton.icon(
                onPressed: onRedeem,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: -0.1,
                  ),
                ),
                icon: const Icon(LucideIcons.gift, size: 17),
                label: const Text('Resgatar'),
              ),
            )
          else
            Container(
              width: double.infinity,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                color: (inStock ? amber : secondary)
                    .withValues(alpha: isDark ? 0.14 : 0.09),
                border: Border.all(
                  color: (inStock ? amber : secondary).withValues(alpha: 0.3),
                ),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    inStock ? LucideIcons.hourglass : LucideIcons.circleOff,
                    size: 15,
                    color: inStock ? amber : secondary,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      inStock
                          ? 'Faltam ${formatPoints(missing)}'
                          : 'Estoque esgotado',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: inStock ? amber : secondary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
