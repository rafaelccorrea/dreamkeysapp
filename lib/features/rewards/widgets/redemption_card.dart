import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../models/reward_model.dart';
import 'rewards_ui.dart';

final DateFormat _dateShort = DateFormat('dd/MM/yy', 'pt_BR');
final DateFormat _dateFull = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');

/// Item de **Meus Resgates** — linha flush (sem card/sombra), coerente com o
/// DNA do app: glyph emoji tonal do status, prêmio + pontos no meio, status e
/// data à direita. Toca para abrir o detalhe (bottom sheet).
class RedemptionCard extends StatelessWidget {
  final RewardRedemption redemption;

  const RedemptionCard({super.key, required this.redemption});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final tone = redemptionStatusColor(context, redemption.status);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showDetail(context),
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
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
                  border: Border.all(color: tone.withValues(alpha: 0.28)),
                ),
                alignment: Alignment.center,
                child: Text(
                  redemption.displayIcon,
                  style: const TextStyle(fontSize: 21, height: 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RewardsStatusPill(
                      label: redemption.status.label,
                      color: tone,
                      icon: redemptionStatusIcon(redemption.status),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      redemption.rewardName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                        height: 1.2,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if ((redemption.reviewNotes ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(LucideIcons.messageSquare,
                              size: 12, color: neutral),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              redemption.reviewNotes!.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: neutral,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatPoints(redemption.pointsSpent),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: rewardsAccent(context),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (redemption.createdAt != null)
                    Text(
                      _dateShort.format(redemption.createdAt!.toLocal()),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: neutral,
                        fontWeight: FontWeight.w700,
                        fontSize: 10.5,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _RedemptionDetailSheet(redemption: redemption),
    );
  }
}

/// Bottom sheet de detalhe do resgate — linha do tempo da solicitação
/// (solicitado → analisado → entregue) + observações.
class _RedemptionDetailSheet extends StatelessWidget {
  final RewardRedemption redemption;

  const _RedemptionDetailSheet({required this.redemption});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = redemptionStatusColor(context, redemption.status);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: tone.withValues(alpha: isDark ? 0.22 : 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: secondary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
                        border: Border.all(color: tone.withValues(alpha: 0.3)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        redemption.displayIcon,
                        style: const TextStyle(fontSize: 22, height: 1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            redemption.rewardName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: ThemeHelpers.textColor(context),
                              letterSpacing: -0.3,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              RewardsStatusPill(
                                label: redemption.status.label,
                                color: tone,
                                icon: redemptionStatusIcon(redemption.status),
                              ),
                              RewardsPointsChip(
                                  points: redemption.pointsSpent),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (redemption.isPending)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: tone.withValues(alpha: isDark ? 0.12 : 0.07),
                      border: Border.all(color: tone.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.hourglass, size: 16, color: tone),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Aguardando aprovação do gestor — os pontos ainda '
                            'não foram debitados.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ThemeHelpers.textColor(context),
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (redemption.isPending) const SizedBox(height: 14),
                _row(context, 'Pontos', formatPoints(redemption.pointsSpent)),
                if (redemption.createdAt != null)
                  _row(context, 'Solicitado em',
                      _dateFull.format(redemption.createdAt!.toLocal())),
                if (redemption.reviewedAt != null)
                  _row(
                    context,
                    redemption.status == RedemptionStatus.rejected
                        ? 'Rejeitado em'
                        : 'Analisado em',
                    _dateFull.format(redemption.reviewedAt!.toLocal()),
                  ),
                if ((redemption.reviewedByName ?? '').trim().isNotEmpty)
                  _row(context, 'Analisado por',
                      redemption.reviewedByName!.trim(),
                      icon: LucideIcons.userCheck),
                if (redemption.deliveredAt != null)
                  _row(context, 'Entregue em',
                      _dateFull.format(redemption.deliveredAt!.toLocal()),
                      icon: LucideIcons.gift),
                if ((redemption.deliveredByName ?? '').trim().isNotEmpty)
                  _row(context, 'Entregue por',
                      redemption.deliveredByName!.trim()),
                if ((redemption.userNotes ?? '').trim().isNotEmpty)
                  _notesBlock(context, 'SUAS OBSERVAÇÕES',
                      redemption.userNotes!.trim()),
                if ((redemption.reviewNotes ?? '').trim().isNotEmpty)
                  _notesBlock(context, 'RESPOSTA DO GESTOR',
                      redemption.reviewNotes!.trim()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {IconData? icon}) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: secondary),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notesBlock(BuildContext context, String label, String text) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
