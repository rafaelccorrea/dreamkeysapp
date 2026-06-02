import 'package:flutter/material.dart';

import '../models/property_score_models.dart';

class PropertyScoreAppearance {
  final Color color;
  final Color bgColor;
  final Color borderColor;
  final String label;

  const PropertyScoreAppearance({
    required this.color,
    required this.bgColor,
    required this.borderColor,
    required this.label,
  });
}

PropertyScoreAppearance propertyScoreAppearance(PropertyScoreLevel level) {
  switch (level) {
    case PropertyScoreLevel.excellent:
      return const PropertyScoreAppearance(
        color: Color(0xFF047857),
        bgColor: Color(0xFFD1FAE5),
        borderColor: Color(0xFF6EE7B7),
        label: 'Excelente',
      );
    case PropertyScoreLevel.good:
      return const PropertyScoreAppearance(
        color: Color(0xFF1D4ED8),
        bgColor: Color(0xFFDBEAFE),
        borderColor: Color(0xFF93C5FD),
        label: 'Bom',
      );
    case PropertyScoreLevel.regular:
      return const PropertyScoreAppearance(
        color: Color(0xFFB45309),
        bgColor: Color(0xFFFEF3C7),
        borderColor: Color(0xFFFCD34D),
        label: 'Regular',
      );
    case PropertyScoreLevel.low:
      return const PropertyScoreAppearance(
        color: Color(0xFFB91C1C),
        bgColor: Color(0xFFFEE2E2),
        borderColor: Color(0xFFFCA5A5),
        label: 'Crítico',
      );
  }
}
