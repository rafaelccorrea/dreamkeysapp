import '../models/property_score_models.dart';

/// Paridade com `compactImprovements` do web (`PropertyScoreDetails.tsx`).
List<PropertyScoreImprovement> compactPropertyScoreImprovements(
  PropertyScoreResult result,
) {
  final seen = <String>{};
  final deduped = result.improvements.where((item) {
    if (seen.contains(item.id)) return false;
    seen.add(item.id);
    return true;
  }).toList();

  final dimensionsWithCriteria = deduped
      .where((item) => item.id.startsWith('criterion-'))
      .map((item) => item.dimensionKey)
      .toSet();

  final filtered = deduped.where((item) {
    if (item.id.startsWith('improve-')) {
      return !dimensionsWithCriteria.contains(item.dimensionKey);
    }
    return true;
  }).toList();

  if (filtered.isNotEmpty) return filtered.take(4).toList();

  return result.breakdown
      .expand(
        (dimension) => dimension.missingFields.map(
          (field) => PropertyScoreImprovement(
            id: 'field-${dimension.key.name}-${field.label}',
            title: field.label,
            description: '',
            impact: field.critical
                ? PropertyScoreImpact.high
                : PropertyScoreImpact.medium,
            dimensionKey: dimension.key,
          ),
        ),
      )
      .take(4)
      .toList();
}

String propertyScoreSummaryText(PropertyScoreResult result) {
  final first = result.reasons.isNotEmpty ? result.reasons.first : '';
  if (first.contains('Classificação atual:')) {
    final parts = first.split('. ');
    if (parts.length > 1) {
      return parts.sublist(1).join('. ');
    }
  }
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
