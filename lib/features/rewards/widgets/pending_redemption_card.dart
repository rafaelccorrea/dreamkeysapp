import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/reward_model.dart';
import 'rewards_ui.dart';

final DateFormat _dateFull = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');

/// Card de solicitação na tela **Aprovar Resgates** — quem pediu, o quê e as
/// ações **Aprovar / Rejeitar no próprio item** (somente pendentes). Para
/// solicitações aprovadas, exibe **Marcar como entregue** quando [onDeliver]
/// for fornecido (gated `reward:deliver` na página).
class PendingRedemptionCard extends StatelessWidget {
  final RewardRedemption redemption;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onDeliver;
  final bool busy;

  const PendingRedemptionCard({
    super.key,
    required this.redemption,
    this.onApprove,
    this.onReject,
    this.onDeliver,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tone = redemptionStatusColor(context, redemption.status);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    final userName = (redemption.userName ?? '').trim().isNotEmpty
        ? redemption.userName!.trim()
        : 'Usuário';
    final userEmail = (redemption.userEmail ?? '').trim();
    final userNotes = (redemption.userNotes ?? '').trim();
    final avatarUrl = (redemption.userAvatarUrl ?? '').trim();

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quem solicitou.
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tone.withValues(alpha: isDark ? 0.18 : 0.12),
                  border: Border.all(color: tone.withValues(alpha: 0.3)),
                ),
                clipBehavior: Clip.antiAlias,
                child: avatarUrl.isNotEmpty
                    ? Image.network(
                        avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _initial(context, userName, tone),
                      )
                    : _initial(context, userName, tone),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (userEmail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(LucideIcons.mail, size: 11, color: secondary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              userEmail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: secondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              RewardsStatusPill(
                label: redemption.status.shortLabel,
                color: tone,
                icon: redemptionStatusIcon(redemption.status),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // O que foi pedido.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: ThemeHelpers.backgroundColor(context)
                  .withValues(alpha: isDark ? 0.5 : 0.6),
              border: Border.all(
                color: ThemeHelpers.borderLightColor(context),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  redemption.displayIcon,
                  style: const TextStyle(fontSize: 24, height: 1.1),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        redemption.rewardName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ThemeHelpers.textColor(context),
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          RewardsPointsChip(points: redemption.pointsSpent),
                          if (redemption.createdAt != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.calendarDays,
                                    size: 11, color: secondary),
                                const SizedBox(width: 4),
                                Text(
                                  _dateFull.format(
                                      redemption.createdAt!.toLocal()),
                                  style: TextStyle(
                                    color: secondary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      if (userNotes.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '“$userNotes”',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondary,
                            fontStyle: FontStyle.italic,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if ((redemption.reviewNotes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.messageSquare, size: 13, color: secondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    redemption.reviewNotes!.trim(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
          // Ações no próprio item — apenas pendentes.
          if (redemption.canReview) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : onReject,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: danger,
                        side: BorderSide(
                            color: danger.withValues(alpha: 0.45)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                      icon: const Icon(LucideIcons.x, size: 16),
                      label: const Text('Rejeitar'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: FilledButton.icon(
                      onPressed: busy ? null : onApprove,
                      style: FilledButton.styleFrom(
                        backgroundColor: emerald,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                      icon: busy
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(LucideIcons.check, size: 16),
                      label: const Text('Aprovar'),
                    ),
                  ),
                ),
              ],
            ),
          ],
          // Entrega — apenas aprovados e quando a página fornece a ação.
          if (redemption.canDeliver && onDeliver != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton.icon(
                onPressed: busy ? null : onDeliver,
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark
                      ? AppColors.status.infoDarkMode
                      : AppColors.status.info,
                  side: BorderSide(
                    color: (isDark
                            ? AppColors.status.infoDarkMode
                            : AppColors.status.info)
                        .withValues(alpha: 0.45),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                icon: busy
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.packageCheck, size: 16),
                label: const Text('Marcar como entregue'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _initial(BuildContext context, String name, Color tone) {
    final letter = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Center(
      child: Text(
        letter,
        style: TextStyle(
          color: tone,
          fontWeight: FontWeight.w900,
          fontSize: 16,
        ),
      ),
    );
  }
}
