import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/reward_model.dart';
import 'rewards_ui.dart';

/// Abre o bottom sheet de confirmação de análise (aprovar/rejeitar).
/// Resolve com as observações do gestor quando confirma; `null` quando cancela.
Future<String?> showReviewRedemptionSheet(
  BuildContext context, {
  required RewardRedemption redemption,
  required bool approve,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) =>
        _ReviewRedemptionSheet(redemption: redemption, approve: approve),
  );
}

/// Bottom sheet **Aprovar/Rejeitar resgate** — resumo da solicitação + campo
/// de resposta ao colaborador (paridade com o `ReviewModal` do web).
class _ReviewRedemptionSheet extends StatefulWidget {
  final RewardRedemption redemption;
  final bool approve;

  const _ReviewRedemptionSheet({
    required this.redemption,
    required this.approve,
  });

  @override
  State<_ReviewRedemptionSheet> createState() => _ReviewRedemptionSheetState();
}

class _ReviewRedemptionSheetState extends State<_ReviewRedemptionSheet> {
  final TextEditingController _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final tone = widget.approve
        ? (isDark ? AppColors.status.greenDarkMode : AppColors.status.green)
        : (isDark ? AppColors.status.errorDarkMode : AppColors.status.error);

    final userName = (widget.redemption.userName ?? '').trim().isNotEmpty
        ? widget.redemption.userName!.trim()
        : 'o colaborador';

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
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
                        border: Border.all(color: tone.withValues(alpha: 0.3)),
                      ),
                      child: Icon(
                        widget.approve ? LucideIcons.check : LucideIcons.x,
                        color: tone,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.approve
                                ? 'APROVAR RESGATE'
                                : 'REJEITAR RESGATE',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: tone,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.4,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.redemption.rewardName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: textColor,
                              letterSpacing: -0.3,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    RewardsPointsChip(points: widget.redemption.pointsSpent),
                    RewardsStatusPill(
                      label: userName,
                      color: secondary,
                      icon: LucideIcons.user,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: tone.withValues(alpha: isDark ? 0.12 : 0.07),
                    border: Border.all(color: tone.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    widget.approve
                        ? 'Ao aprovar, ${formatPoints(widget.redemption.pointsSpent)} '
                            'serão debitados dos pontos de $userName.'
                        : 'Ao rejeitar, nenhum ponto será debitado e o '
                            'colaborador será notificado.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _notes,
                  maxLines: 3,
                  maxLength: 500,
                  cursorColor: tone,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    labelText: widget.approve
                        ? 'Resposta ao colaborador (opcional)'
                        : 'Motivo da rejeição (opcional)',
                    hintText: widget.approve
                        ? 'Ex.: aprovado! Retire com o RH…'
                        : 'Ex.: estoque indisponível neste mês…',
                    labelStyle: TextStyle(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                    floatingLabelStyle: TextStyle(
                      color: tone,
                      fontWeight: FontWeight.w700,
                    ),
                    hintStyle: TextStyle(
                      color: secondary.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.045)
                        : Colors.black.withValues(alpha: 0.025),
                    counterStyle: TextStyle(color: secondary, fontSize: 11),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: tone, width: 1.6),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: secondary,
                            side: BorderSide(
                              color: ThemeHelpers.borderColor(context),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 46,
                        child: FilledButton.icon(
                          onPressed: () =>
                              Navigator.of(context).pop(_notes.text),
                          style: FilledButton.styleFrom(
                            backgroundColor: tone,
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
                          icon: Icon(
                            widget.approve ? LucideIcons.check : LucideIcons.x,
                            size: 17,
                          ),
                          label: Text(widget.approve
                              ? 'Aprovar resgate'
                              : 'Rejeitar resgate'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
