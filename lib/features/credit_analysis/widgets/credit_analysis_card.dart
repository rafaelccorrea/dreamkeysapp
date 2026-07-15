import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/utils/masks.dart';
import '../models/credit_analysis_model.dart';

/// Cor semântica do STATUS da análise (verde=ok, âmbar=atenção, vermelho=erro).
Color creditStatusColor(BuildContext context, CreditAnalysisStatus status) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (status) {
    case CreditAnalysisStatus.approved:
    case CreditAnalysisStatus.completed:
      return isDark
          ? AppColors.status.successDarkMode
          : AppColors.status.success;
    case CreditAnalysisStatus.processing:
      return isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    case CreditAnalysisStatus.manualReview:
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    case CreditAnalysisStatus.rejected:
    case CreditAnalysisStatus.error:
    case CreditAnalysisStatus.failed:
      return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    case CreditAnalysisStatus.pending:
    case CreditAnalysisStatus.unknown:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

/// Cor semântica do NÍVEL DE RISCO.
Color creditRiskColor(BuildContext context, CreditRiskLevel risk) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (risk) {
    case CreditRiskLevel.veryLow:
      return isDark
          ? AppColors.status.successDarkMode
          : AppColors.status.success;
    case CreditRiskLevel.low:
      return isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    case CreditRiskLevel.medium:
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    case CreditRiskLevel.high:
    case CreditRiskLevel.veryHigh:
      return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    case CreditRiskLevel.unknown:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

/// Cor semântica da RECOMENDAÇÃO do parecer.
Color creditRecommendationColor(
    BuildContext context, CreditRecommendation rec) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (rec) {
    case CreditRecommendation.approve:
      return isDark
          ? AppColors.status.successDarkMode
          : AppColors.status.success;
    case CreditRecommendation.reject:
      return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    case CreditRecommendation.manualReview:
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    case CreditRecommendation.unknown:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

/// Item da lista de análises — **linha flush** (sem card/sombra), coerente com
/// o DNA do app: glyph tonal, CPF/nome no meio, score à direita e a ação
/// "refazer" no próprio item quando liberada (15 dias após a última).
class CreditAnalysisCard extends StatelessWidget {
  final CreditAnalysis analysis;
  final VoidCallback? onTap;
  final VoidCallback? onRedo;
  final bool redoing;

  const CreditAnalysisCard({
    super.key,
    required this.analysis,
    this.onTap,
    this.onRedo,
    this.redoing = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final tone = creditStatusColor(context, analysis.status);
    final scoreTone = analysis.status.isError
        ? neutral
        : analysis.hasGoodScore
            ? (isDark
                ? AppColors.status.successDarkMode
                : AppColors.status.success)
            : (isDark ? AppColors.status.errorDarkMode : AppColors.status.error);

    final name = (analysis.analyzedName ?? '').trim();
    final fmt = DateFormat('dd/MM/yy', 'pt_BR');
    final dateLabel = analysis.createdAt == null
        ? null
        : fmt.format(analysis.createdAt!.toLocal());

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
              // Glyph tonal do status.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
                  border: Border.all(color: tone.withValues(alpha: 0.28)),
                ),
                child: Icon(_statusIcon(analysis.status), color: tone, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: _Pill(label: analysis.status.label, color: tone),
                        ),
                        if (analysis.riskLevel != CreditRiskLevel.unknown) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: _Pill(
                              label: 'Risco ${analysis.riskLevel.label.toLowerCase()}',
                              color: creditRiskColor(context, analysis.riskLevel),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      name.isNotEmpty ? name : Masks.cpf(analysis.analyzedCpf),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                        height: 1.2,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (name.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(LucideIcons.idCard, size: 12, color: neutral),
                          const SizedBox(width: 4),
                          Text(
                            Masks.cpf(analysis.analyzedCpf),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: neutral,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (analysis.recommendation !=
                        CreditRecommendation.unknown) ...[
                      const SizedBox(height: 5),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _recommendationIcon(analysis.recommendation),
                            size: 12,
                            color: creditRecommendationColor(
                                context, analysis.recommendation),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Parecer: ${analysis.recommendation.label}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: creditRecommendationColor(
                                    context, analysis.recommendation),
                                fontWeight: FontWeight.w700,
                                fontSize: 11.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Score + data + ação refazer no próprio item.
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!analysis.status.isError && analysis.creditScore > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          analysis.hasGoodScore
                              ? LucideIcons.trendingUp
                              : LucideIcons.trendingDown,
                          size: 14,
                          color: scoreTone,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${analysis.creditScore}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: scoreTone,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      '—',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: neutral,
                      ),
                    ),
                  const SizedBox(height: 4),
                  if (dateLabel != null)
                    Text(
                      dateLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: neutral,
                        fontWeight: FontWeight.w700,
                        fontSize: 10.5,
                      ),
                    ),
                  if (onRedo != null) ...[
                    const SizedBox(height: 6),
                    redoing
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: neutral,
                            ),
                          )
                        : InkResponse(
                            radius: 18,
                            onTap: analysis.canRedo ? onRedo : null,
                            child: Tooltip(
                              message: analysis.canRedo
                                  ? 'Refazer análise'
                                  : 'Refazer disponível após 15 dias da última análise',
                              child: Icon(
                                LucideIcons.rotateCcw,
                                size: 16,
                                color: analysis.canRedo
                                    ? neutral
                                    : neutral.withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _statusIcon(CreditAnalysisStatus status) {
    switch (status) {
      case CreditAnalysisStatus.approved:
      case CreditAnalysisStatus.completed:
        return LucideIcons.shieldCheck;
      case CreditAnalysisStatus.rejected:
        return LucideIcons.shieldX;
      case CreditAnalysisStatus.manualReview:
        return LucideIcons.shieldQuestionMark;
      case CreditAnalysisStatus.error:
      case CreditAnalysisStatus.failed:
        return LucideIcons.shieldAlert;
      case CreditAnalysisStatus.processing:
      case CreditAnalysisStatus.pending:
      case CreditAnalysisStatus.unknown:
        return LucideIcons.gauge;
    }
  }

  IconData _recommendationIcon(CreditRecommendation rec) {
    switch (rec) {
      case CreditRecommendation.approve:
        return LucideIcons.circleCheck;
      case CreditRecommendation.reject:
        return LucideIcons.circleX;
      case CreditRecommendation.manualReview:
        return LucideIcons.circleAlert;
      case CreditRecommendation.unknown:
        return LucideIcons.circle;
    }
  }
}

/// Pílula de status — tint da cor + texto na cor (mesma gramática do app).
class _Pill extends StatelessWidget {
  final String label;
  final Color color;

  const _Pill({required this.label, required this.color});

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
