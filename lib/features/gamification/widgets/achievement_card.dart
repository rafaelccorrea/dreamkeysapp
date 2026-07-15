// Card de conquista — medalha por tier (bronze/prata/ouro/platina/diamante),
// emoji do backend quando existir, pontos ganhos e data do desbloqueio.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../models/gamification_models.dart';

class GamAchievementCard extends StatelessWidget {
  final UserAchievement userAchievement;

  /// Largura fixa quando usado num carrossel horizontal.
  final double? width;

  const GamAchievementCard({
    super.key,
    required this.userAchievement,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ach = userAchievement.achievement;
    final tone = Color(ach.tier.colorValue);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fmt = DateFormat('dd/MM/yyyy', 'pt_BR');
    final emoji = (ach.iconEmoji ?? '').trim();

    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      tone.withValues(alpha: isDark ? 0.32 : 0.2),
                      tone.withValues(alpha: isDark ? 0.12 : 0.07),
                    ],
                  ),
                  border: Border.all(color: tone.withValues(alpha: 0.45)),
                ),
                alignment: Alignment.center,
                child: emoji.isNotEmpty
                    ? Text(emoji, style: const TextStyle(fontSize: 18))
                    : Icon(LucideIcons.award, size: 18, color: tone),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: isDark ? 0.18 : 0.11),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  ach.tier.label,
                  style: TextStyle(
                    color: tone,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            ach.namePt.isNotEmpty ? ach.namePt : 'Conquista',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            ach.descriptionPt,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(LucideIcons.sparkles, size: 12, color: tone),
              const SizedBox(width: 4),
              Text(
                '+${userAchievement.pointsEarned} pts',
                style: TextStyle(
                  color: tone,
                  fontWeight: FontWeight.w900,
                  fontSize: 11.5,
                ),
              ),
              const Spacer(),
              if (userAchievement.unlockedAt != null)
                Text(
                  fmt.format(userAchievement.unlockedAt!.toLocal()),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
