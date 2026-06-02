/// Modelos da nota de qualidade do imóvel — paridade com `imobx-front`.
enum PropertyScoreLevel { excellent, good, regular, low }

enum PropertyScoreDimensionKey { highImpact, mediumImpact, complementary }

enum PropertyScoreImpact { high, medium, low }

class PropertyScoreFieldStatus {
  final String label;
  final bool critical;

  const PropertyScoreFieldStatus({
    required this.label,
    this.critical = false,
  });
}

class PropertyScoreDimension {
  final PropertyScoreDimensionKey key;
  final String label;
  final int score;
  final int maxScore;
  final double ratio;
  final List<PropertyScoreFieldStatus> completedFields;
  final List<PropertyScoreFieldStatus> missingFields;

  const PropertyScoreDimension({
    required this.key,
    required this.label,
    required this.score,
    required this.maxScore,
    required this.ratio,
    required this.completedFields,
    required this.missingFields,
  });
}

class PropertyScoreImprovement {
  final String id;
  final String title;
  final String description;
  final PropertyScoreImpact impact;
  final PropertyScoreDimensionKey dimensionKey;

  const PropertyScoreImprovement({
    required this.id,
    required this.title,
    required this.description,
    required this.impact,
    required this.dimensionKey,
  });
}

class PropertyScoreResult {
  final int score;
  final PropertyScoreLevel level;
  final List<PropertyScoreDimension> breakdown;
  final List<String> reasons;
  final List<PropertyScoreImprovement> improvements;

  const PropertyScoreResult({
    required this.score,
    required this.level,
    required this.breakdown,
    required this.reasons,
    required this.improvements,
  });
}
