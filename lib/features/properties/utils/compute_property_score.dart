import '../../../../shared/services/property_service.dart';
import '../models/property_score_models.dart';

const _minDescriptionLength = 300;
const _minExcellentDescriptionLength = 600;
const _minRecommendedImageCount = 15;
const _minExcellentImageCount = 25;
const _maxImprovements = 5;

const _thresholdExcellent = 90;
const _thresholdGood = 70;
const _thresholdRegular = 40;

class _FieldCheck {
  final String label;
  final bool ok;
  final bool critical;

  const _FieldCheck({
    required this.label,
    required this.ok,
    this.critical = false,
  });
}

class _DimensionConfig {
  final PropertyScoreDimensionKey key;
  final String label;
  final int weight;

  const _DimensionConfig({
    required this.key,
    required this.label,
    required this.weight,
  });
}

const _dimensions = [
  _DimensionConfig(
    key: PropertyScoreDimensionKey.highImpact,
    label: 'Peso alto (fundamentos)',
    weight: 50,
  ),
  _DimensionConfig(
    key: PropertyScoreDimensionKey.mediumImpact,
    label: 'Peso médio (qualidade)',
    weight: 30,
  ),
  _DimensionConfig(
    key: PropertyScoreDimensionKey.complementary,
    label: 'Peso complementar (excelência)',
    weight: 20,
  ),
];

bool _hasText(String? value) =>
    value != null && value.trim().isNotEmpty;

bool _hasPositive(num? value) =>
    value != null && value.isFinite && value > 0;

bool _hasNumeric(num? value) => value != null && value.isFinite;

int _clampScore(num value) {
  if (!value.isFinite) return 0;
  return value.round().clamp(0, 100);
}

double _ratioFromChecks(List<_FieldCheck> checks) {
  if (checks.isEmpty) return 1;
  final ok = checks.where((c) => c.ok).length;
  return ok / checks.length;
}

bool _isResidential(PropertyType type) {
  return type != PropertyType.land &&
      type != PropertyType.commercial &&
      type != PropertyType.rural;
}

bool _hasMeaningfulTitle(String title) {
  if (!_hasText(title)) return false;
  final normalized = title.trim().toLowerCase();
  const generic = ['imóvel', 'imovel', 'casa', 'apartamento', 'sala comercial', 'terreno'];
  if (normalized.length < 18) return false;
  return !generic.contains(normalized);
}

bool _isVideoImage(PropertyImage image) {
  final cat = image.category.toLowerCase();
  if (cat.contains('video')) return true;
  final url = image.url.toLowerCase();
  return url.contains('.mp4') ||
      url.contains('.mov') ||
      url.contains('/video');
}

int _countValidPhotos(Property property) {
  final images = property.images ?? const <PropertyImage>[];
  return images
      .where(
        (img) =>
            !_isVideoImage(img) &&
            (_hasText(img.url) || _hasText(img.thumbnailUrl)),
      )
      .length;
}

bool _hasUploadedVideo(Property property) {
  return (property.images ?? const <PropertyImage>[]).any(_isVideoImage);
}

bool _hasVirtualTour(Property property) {
  if (_hasUploadedVideo(property)) return true;
  return property.features.any((f) {
    final lower = f.toLowerCase();
    return lower.contains('tour') ||
        lower.contains('vídeo') ||
        lower.contains('video');
  });
}

bool _hasFloorPlan(Property property) {
  final fromFeatures = property.features.any((f) => f.toLowerCase().contains('planta'));
  final fromImages = (property.images ?? const <PropertyImage>[]).any((img) {
    final cat = img.category.toLowerCase();
    return cat.contains('planta') || cat.contains('floor');
  });
  return fromFeatures || fromImages;
}

bool _hasFacadePhoto(Property property) {
  return (property.images ?? const <PropertyImage>[]).any((img) {
    final cat = img.category.toLowerCase();
    return cat.contains('fachada') ||
        cat.contains('facade') ||
        cat.contains('frontal') ||
        cat.contains('front');
  });
}

PropertyScoreLevel _levelFromScore(int score) {
  if (score >= _thresholdExcellent) return PropertyScoreLevel.excellent;
  if (score >= _thresholdGood) return PropertyScoreLevel.good;
  if (score >= _thresholdRegular) return PropertyScoreLevel.regular;
  return PropertyScoreLevel.low;
}

PropertyScoreDimension _buildDimension(
  PropertyScoreDimensionKey key,
  List<_FieldCheck> checks,
) {
  final config = _dimensions.firstWhere((d) => d.key == key);
  final ratio = _ratioFromChecks(checks);
  final score = _clampScore(ratio * config.weight);
  final missing = checks
      .where((c) => !c.ok)
      .map((c) => PropertyScoreFieldStatus(label: c.label, critical: c.critical))
      .toList();
  final completed = checks
      .where((c) => c.ok)
      .map((c) => PropertyScoreFieldStatus(label: c.label, critical: c.critical))
      .toList();

  return PropertyScoreDimension(
    key: key,
    label: config.label,
    score: score,
    maxScore: config.weight,
    ratio: ratio,
    completedFields: completed,
    missingFields: missing,
  );
}

PropertyScoreImprovement? _dimensionImprovement(PropertyScoreDimension dimension) {
  if (dimension.missingFields.isEmpty) return null;
  final critical = dimension.missingFields.where((f) => f.critical).length;
  final impact = critical > 0
      ? PropertyScoreImpact.high
      : dimension.missingFields.length >= 2
          ? PropertyScoreImpact.medium
          : PropertyScoreImpact.low;
  final missingText = dimension.missingFields
      .take(3)
      .map((f) => f.label.toLowerCase())
      .join(', ');
  return PropertyScoreImprovement(
    id: 'improve-${dimension.key.name}',
    title: 'Melhore ${dimension.label.toLowerCase()}',
    description: dimension.missingFields.length > 3
        ? 'Complete os critérios de ${dimension.label.toLowerCase()} ($missingText e outros) para subir a classificação.'
        : 'Complete $missingText para elevar a nota.',
    impact: impact,
    dimensionKey: dimension.key,
  );
}

PropertyScoreImprovement? _criterionImprovement(PropertyScoreDimension dimension) {
  if (dimension.missingFields.isEmpty) return null;
  final first = dimension.missingFields.first;
  final critical = dimension.missingFields.where((f) => f.critical).length;
  return PropertyScoreImprovement(
    id:
        'criterion-${dimension.key.name}-${first.label.toLowerCase().replaceAll(RegExp(r'\s+'), '-')}',
    title: first.label,
    description:
        'Ajuste "${first.label.toLowerCase()}" para aumentar a nota em ${dimension.label.toLowerCase()}.',
    impact: critical > 0 ? PropertyScoreImpact.high : PropertyScoreImpact.medium,
    dimensionKey: dimension.key,
  );
}

List<_FieldCheck> _highImpactChecks(Property property) {
  return [
    _FieldCheck(
      label: 'Fotos do imóvel (mín. $_minRecommendedImageCount)',
      ok: _countValidPhotos(property) >= _minRecommendedImageCount,
      critical: true,
    ),
    _FieldCheck(
      label: 'Descrição do imóvel (mín. $_minDescriptionLength caracteres)',
      ok: _hasText(property.description) &&
          property.description.trim().length >= _minDescriptionLength,
      critical: true,
    ),
    _FieldCheck(
      label: 'Preço definido',
      ok: _hasPositive(property.salePrice) || _hasPositive(property.rentPrice),
      critical: true,
    ),
    _FieldCheck(
      label: 'Tipo e finalidade preenchidos',
      ok: _hasPositive(property.salePrice) ||
          _hasPositive(property.rentPrice) ||
          property.status != PropertyStatus.draft,
      critical: true,
    ),
    _FieldCheck(
      label: 'Área útil/total preenchida',
      ok: _hasPositive(property.totalArea) || _hasPositive(property.builtArea),
      critical: true,
    ),
  ];
}

List<_FieldCheck> _mediumImpactChecks(Property property) {
  final requiresRooms = _isResidential(property.type);
  return [
    _FieldCheck(
      label: requiresRooms
          ? 'Quartos, banheiros e vagas preenchidos'
          : 'Banheiros e vagas preenchidos',
      ok: requiresRooms
          ? _hasNumeric(property.bedrooms) &&
              _hasNumeric(property.bathrooms) &&
              _hasNumeric(property.parkingSpaces)
          : _hasNumeric(property.bathrooms) &&
              _hasNumeric(property.parkingSpaces),
      critical: true,
    ),
    _FieldCheck(
      label: 'Endereço completo com bairro',
      ok: _hasText(property.street) &&
          _hasText(property.number) &&
          _hasText(property.city) &&
          _hasText(property.state) &&
          _hasText(property.neighborhood),
      critical: true,
    ),
    _FieldCheck(
      label: 'Diferenciais do imóvel',
      ok: property.features.length >= 3,
    ),
    _FieldCheck(
      label: 'Foto de fachada identificada',
      ok: _hasFacadePhoto(property),
    ),
    _FieldCheck(
      label: 'Condomínio e IPTU preenchidos (quando aplicável)',
      ok: _hasNumeric(property.condominiumFee) ||
          _hasNumeric(property.iptu) ||
          property.isAvailableForSite != true,
    ),
  ];
}

List<_FieldCheck> _complementaryChecks(Property property) {
  return [
    _FieldCheck(
      label: 'Vídeo do imóvel ou tour virtual',
      ok: _hasVirtualTour(property),
    ),
    _FieldCheck(
      label: 'Planta baixa enviada',
      ok: _hasFloorPlan(property),
    ),
    _FieldCheck(
      label:
          'Descrição rica (acima de $_minExcellentDescriptionLength caracteres)',
      ok: _hasText(property.description) &&
          property.description.trim().length >= _minExcellentDescriptionLength,
    ),
    _FieldCheck(
      label: 'Volume de fotos acima de $_minExcellentImageCount',
      ok: _countValidPhotos(property) > _minExcellentImageCount,
    ),
    _FieldCheck(
      label: 'Título personalizado do anúncio',
      ok: _hasMeaningfulTitle(property.title),
    ),
  ];
}

String _classificationMeaning(double scoreTen) {
  if (scoreTen >= 9) return 'Cadastro completo, máximo potencial orgânico.';
  if (scoreTen >= 7) return 'Cadastro sólido, boa chance de destaque nos portais.';
  if (scoreTen >= 4) return 'Publicável, mas com baixo potencial de performance.';
  return 'Cadastro incompleto, não recomendado para publicação.';
}

String _levelLabel(PropertyScoreLevel level) {
  switch (level) {
    case PropertyScoreLevel.excellent:
      return 'Excelente';
    case PropertyScoreLevel.good:
      return 'Bom';
    case PropertyScoreLevel.regular:
      return 'Regular';
    case PropertyScoreLevel.low:
      return 'Crítico';
  }
}

String _reasonFromDimension(PropertyScoreDimension dimension) {
  if (dimension.missingFields.isEmpty) {
    return '${dimension.label}: completo (${dimension.score}/${dimension.maxScore}).';
  }
  return '${dimension.label}: ${dimension.score}/${dimension.maxScore}, faltando ${dimension.missingFields.length} critério(s).';
}

/// Calcula a nota de qualidade localmente (mesma regra do web).
PropertyScoreResult computePropertyScore(Property property) {
  final breakdown = [
    _buildDimension(
      PropertyScoreDimensionKey.highImpact,
      _highImpactChecks(property),
    ),
    _buildDimension(
      PropertyScoreDimensionKey.mediumImpact,
      _mediumImpactChecks(property),
    ),
    _buildDimension(
      PropertyScoreDimensionKey.complementary,
      _complementaryChecks(property),
    ),
  ];

  final raw = breakdown.fold<int>(0, (sum, d) => sum + d.score);
  final score = _clampScore(raw);
  final level = _levelFromScore(score);
  final scoreTen = double.parse((score / 10).toStringAsFixed(1));

  final reasons = [
    'Classificação atual: ${_levelLabel(level)} ($scoreTen/10). ${_classificationMeaning(scoreTen)}',
    ...breakdown.map(_reasonFromDimension),
  ];

  final improvements = breakdown
      .expand((d) => [_dimensionImprovement(d), _criterionImprovement(d)])
      .whereType<PropertyScoreImprovement>()
      .toList()
    ..sort((a, b) {
      const w = {
        PropertyScoreImpact.high: 3,
        PropertyScoreImpact.medium: 2,
        PropertyScoreImpact.low: 1,
      };
      return w[b.impact]! - w[a.impact]!;
    });

  final seen = <String>{};
  final unique = <PropertyScoreImprovement>[];
  for (final item in improvements) {
    if (seen.add(item.id)) unique.add(item);
  }

  return PropertyScoreResult(
    score: score,
    level: level,
    breakdown: breakdown,
    reasons: reasons,
    improvements: unique.take(_maxImprovements).toList(),
  );
}
