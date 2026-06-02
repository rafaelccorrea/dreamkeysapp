import 'package:flutter/material.dart';

import '../../../core/theme/theme_helpers.dart';
import '../models/property_score_models.dart';
import 'property_score_appearance.dart';

/// Painel da nota de qualidade — paridade com `PropertyScoreDetails` (surface panel).
class PropertyScorePanel extends StatelessWidget {
  final PropertyScoreResult result;

  const PropertyScorePanel({super.key, required this.result});

  static const _dimensionMeta = {
    PropertyScoreDimensionKey.highImpact: (
      'Fundamentos',
      'Fotos, descrição, preço e dados essenciais',
    ),
    PropertyScoreDimensionKey.mediumImpact: (
      'Qualidade',
      'Composição, endereço, diferenciais e transparência',
    ),
    PropertyScoreDimensionKey.complementary: (
      'Excelência',
      'Tour, planta, título e volume de mídia',
    ),
  };

  String _summary(PropertyScoreResult result) {
    if (result.score >= 90) {
      return 'Cadastro completo, com máximo potencial orgânico.';
    }
    if (result.score >= 70) {
      return 'Cadastro sólido, com boa chance de destaque nos portais.';
    }
    if (result.score >= 40) {
      return 'Publicável, mas ainda com potencial de performance limitado.';
    }
    return 'Cadastro incompleto — revise os critérios abaixo antes de publicar.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final appearance = propertyScoreAppearance(result.level);
    final scoreTen = (result.score / 10).toStringAsFixed(1);
    final summary = _summary(result);
    final high = result.improvements
        .where((i) => i.impact == PropertyScoreImpact.high)
        .toList();
    final medium = result.improvements
        .where((i) => i.impact != PropertyScoreImpact.high)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [
                appearance.color.withValues(alpha: 0.12),
                ThemeHelpers.cardBackgroundColor(context),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: appearance.borderColor.withValues(alpha: 0.55)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ScoreRing(score: result.score, color: appearance.color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NOTA DE QUALIDADE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: appearance.color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          scoreTen,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: appearance.color,
                            height: 1,
                          ),
                        ),
                        Text(
                          '/10',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: appearance.bgColor,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: appearance.borderColor),
                          ),
                          child: Text(
                            appearance.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: appearance.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      summary,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: muted,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionTitle(context, 'Por que essa nota', Icons.trending_up_rounded,
            const Color(0xFF6366F1)),
        const SizedBox(height: 10),
        ...result.breakdown.map((d) => _DimensionCard(dimension: d, accent: appearance.color)),
        if (result.improvements.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle(
            context,
            'Como melhorar',
            Icons.lightbulb_outline_rounded,
            const Color(0xFFF59E0B),
          ),
          const SizedBox(height: 8),
          Text(
            'Próximos passos para subir a nota',
            style: theme.textTheme.labelSmall?.copyWith(
              color: muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (high.isNotEmpty) ...[
            _improvementGroup(context, 'Alta prioridade', const Color(0xFFEF4444), high),
            if (medium.isNotEmpty) const SizedBox(height: 8),
          ],
          if (medium.isNotEmpty)
            _improvementGroup(
              context,
              high.isEmpty ? 'Sugestões' : 'Também vale a pena',
              const Color(0xFFF59E0B),
              medium,
            ),
        ],
      ],
    );
  }

  Widget _sectionTitle(
    BuildContext context,
    String title,
    IconData icon,
    Color tone,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: tone),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }

  Widget _improvementGroup(
    BuildContext context,
    String label,
    Color tone,
    List<PropertyScoreImprovement> items,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
            color: tone,
          ),
        ),
        const SizedBox(height: 6),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tone.withValues(alpha: 0.28)),
              ),
              child: Text(
                item.title,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScoreRing extends StatelessWidget {
  final int score;
  final Color color;

  const _ScoreRing({required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: score / 100,
            strokeWidth: 5,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
          Text(
            '$score',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _DimensionCard extends StatelessWidget {
  final PropertyScoreDimension dimension;
  final Color accent;

  const _DimensionCard({
    required this.dimension,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final meta = PropertyScorePanel._dimensionMeta[dimension.key]!;
    final pct = (dimension.ratio * 100).round();
    final complete = dimension.missingFields.isEmpty;
    final barColor = complete
        ? accent
        : pct >= 50
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ThemeHelpers.borderColor(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meta.$1,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        meta.$2,
                        style: theme.textTheme.labelSmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${dimension.score}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: complete ? accent : null,
                        ),
                      ),
                      TextSpan(
                        text: '/${dimension.maxScore}',
                        style: theme.textTheme.labelSmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: dimension.ratio.clamp(0, 1),
                minHeight: 5,
                backgroundColor: muted.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$pct% do eixo', style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                Text(
                  complete
                      ? 'Eixo completo'
                      : '${dimension.missingFields.length} pendência(s)',
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
              ],
            ),
            if (complete)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 14, color: accent),
                    const SizedBox(width: 6),
                    Text(
                      'Todos os critérios deste eixo estão ok',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final field in dimension.missingFields.take(4))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: (field.critical
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFFF59E0B))
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (field.critical
                                    ? const Color(0xFFEF4444)
                                    : const Color(0xFFF59E0B))
                                .withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 12,
                              color: field.critical
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFFF59E0B),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                field.label,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (dimension.missingFields.length > 4)
                      Text(
                        '+${dimension.missingFields.length - 4} critério(s)',
                        style: theme.textTheme.labelSmall?.copyWith(color: muted),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
