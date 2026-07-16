// Models do Analytics de Imóveis — espelham `propertyAnalyticsApi.ts` do
// imobx-front (`GET /dashboard/property-analytics*`).

import 'parse_utils.dart';

/// Resumo agregado do portfólio.
class PropertySummaryStats {
  final int totalProperties;
  final int totalAvailable;
  final int totalSold;
  final int totalRented;
  final double avgSalePrice;
  final double avgRentPrice;
  final double avgPricePerSqm;
  final double avgTotalArea;
  final int totalCities;
  final int totalNeighborhoods;

  const PropertySummaryStats({
    required this.totalProperties,
    required this.totalAvailable,
    required this.totalSold,
    required this.totalRented,
    required this.avgSalePrice,
    required this.avgRentPrice,
    required this.avgPricePerSqm,
    required this.avgTotalArea,
    required this.totalCities,
    required this.totalNeighborhoods,
  });

  factory PropertySummaryStats.fromJson(Map<String, dynamic> json) {
    return PropertySummaryStats(
      totalProperties: parseInt(json['totalProperties']),
      totalAvailable: parseInt(json['totalAvailable']),
      totalSold: parseInt(json['totalSold']),
      totalRented: parseInt(json['totalRented']),
      avgSalePrice: parseDouble(json['avgSalePrice']),
      avgRentPrice: parseDouble(json['avgRentPrice']),
      avgPricePerSqm: parseDouble(json['avgPricePerSqm']),
      avgTotalArea: parseDouble(json['avgTotalArea']),
      totalCities: parseInt(json['totalCities']),
      totalNeighborhoods: parseInt(json['totalNeighborhoods']),
    );
  }

  static const empty = PropertySummaryStats(
    totalProperties: 0,
    totalAvailable: 0,
    totalSold: 0,
    totalRented: 0,
    avgSalePrice: 0,
    avgRentPrice: 0,
    avgPricePerSqm: 0,
    avgTotalArea: 0,
    totalCities: 0,
    totalNeighborhoods: 0,
  );

  double pctOfTotal(int part) =>
      totalProperties > 0 ? part / totalProperties * 100 : 0;
}

/// Ranking de vendas por região (bairro/cidade).
class RegionRanking {
  final int rank;
  final String neighborhood;
  final String city;
  final int totalSold;
  final int totalRented;
  final int totalAvailable;
  final double avgSalePrice;
  final double avgRentPrice;
  final double conversionRate;

  const RegionRanking({
    required this.rank,
    required this.neighborhood,
    required this.city,
    required this.totalSold,
    required this.totalRented,
    required this.totalAvailable,
    required this.avgSalePrice,
    required this.avgRentPrice,
    required this.conversionRate,
  });

  factory RegionRanking.fromJson(Map<String, dynamic> json) {
    return RegionRanking(
      rank: parseInt(json['rank']),
      neighborhood: parseString(json['neighborhood'], 'Sem bairro'),
      city: parseString(json['city']),
      totalSold: parseInt(json['totalSold']),
      totalRented: parseInt(json['totalRented']),
      totalAvailable: parseInt(json['totalAvailable']),
      avgSalePrice: parseDouble(json['avgSalePrice']),
      avgRentPrice: parseDouble(json['avgRentPrice']),
      conversionRate: parseDouble(json['conversionRate']),
    );
  }
}

/// Valores médios por tipo de imóvel.
class AvgValuesByType {
  final String propertyType;
  final int totalProperties;
  final double avgSalePrice;
  final double avgRentPrice;
  final double avgTotalArea;
  final double avgPricePerSqm;

  const AvgValuesByType({
    required this.propertyType,
    required this.totalProperties,
    required this.avgSalePrice,
    required this.avgRentPrice,
    required this.avgTotalArea,
    required this.avgPricePerSqm,
  });

  factory AvgValuesByType.fromJson(Map<String, dynamic> json) {
    return AvgValuesByType(
      propertyType: parseString(json['propertyType'], 'outros'),
      totalProperties: parseInt(json['totalProperties']),
      avgSalePrice: parseDouble(json['avgSalePrice']),
      avgRentPrice: parseDouble(json['avgRentPrice']),
      avgTotalArea: parseDouble(json['avgTotalArea']),
      avgPricePerSqm: parseDouble(json['avgPricePerSqm']),
    );
  }

  String get typeLabel => propertyTypeLabel(propertyType);
}

/// Evolução mensal de preços/volumes.
class PriceEvolutionPoint {
  final String month; // YYYY-MM
  final double avgSalePrice;
  final double avgRentPrice;
  final int totalSold;
  final int totalRented;
  final int totalAvailable;

  const PriceEvolutionPoint({
    required this.month,
    required this.avgSalePrice,
    required this.avgRentPrice,
    required this.totalSold,
    required this.totalRented,
    required this.totalAvailable,
  });

  factory PriceEvolutionPoint.fromJson(Map<String, dynamic> json) {
    return PriceEvolutionPoint(
      month: parseString(json['month']),
      avgSalePrice: parseDouble(json['avgSalePrice']),
      avgRentPrice: parseDouble(json['avgRentPrice']),
      totalSold: parseInt(json['totalSold']),
      totalRented: parseInt(json['totalRented']),
      totalAvailable: parseInt(json['totalAvailable']),
    );
  }

  /// "2025-03" → "mar/25".
  String get monthLabel {
    final parts = month.split('-');
    if (parts.length < 2) return month;
    const names = [
      'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
      'jul', 'ago', 'set', 'out', 'nov', 'dez',
    ];
    final m = int.tryParse(parts[1]);
    if (m == null || m < 1 || m > 12) return month;
    final yy = parts[0].length >= 4 ? parts[0].substring(2, 4) : parts[0];
    return '${names[m - 1]}/$yy';
  }
}

/// Engajamento por imóvel (site público).
class PropertyEngagement {
  final String propertyId;
  final String? title;
  final String? code;
  final int views;
  final int prints;
  final int whatsappClicks;
  final int phoneClicks;
  final int emailClicks;
  final int favorites;

  const PropertyEngagement({
    required this.propertyId,
    required this.title,
    required this.code,
    required this.views,
    required this.prints,
    required this.whatsappClicks,
    required this.phoneClicks,
    required this.emailClicks,
    required this.favorites,
  });

  factory PropertyEngagement.fromJson(Map<String, dynamic> json) {
    return PropertyEngagement(
      propertyId: parseString(json['propertyId'], parseString(json['id'])),
      title: parseStringOrNull(json['title']),
      code: parseStringOrNull(json['code']),
      views: parseInt(json['views']),
      prints: parseInt(json['prints']),
      whatsappClicks: parseInt(json['whatsappClicks']),
      phoneClicks: parseInt(json['phoneClicks']),
      emailClicks: parseInt(json['emailClicks']),
      favorites: parseInt(json['favorites']),
    );
  }

  int get total =>
      views + prints + whatsappClicks + phoneClicks + emailClicks + favorites;
}

/// Resposta agregada de `GET /dashboard/property-analytics`.
class PropertyAnalyticsData {
  final PropertySummaryStats summary;
  final List<RegionRanking> regionRanking;
  final List<AvgValuesByType> avgValuesByType;
  final List<PriceEvolutionPoint> priceEvolution;

  const PropertyAnalyticsData({
    required this.summary,
    required this.regionRanking,
    required this.avgValuesByType,
    required this.priceEvolution,
  });

  factory PropertyAnalyticsData.fromJson(Map<String, dynamic> json) {
    final body = unwrapData(json);
    return PropertyAnalyticsData(
      summary: parseMap(body['summary']) != null
          ? PropertySummaryStats.fromJson(parseMap(body['summary'])!)
          : PropertySummaryStats.empty,
      regionRanking: parseMapList(body['regionRanking'])
          .map(RegionRanking.fromJson)
          .toList(growable: false),
      avgValuesByType: parseMapList(body['avgValuesByType'])
          .map(AvgValuesByType.fromJson)
          .toList(growable: false),
      priceEvolution: parseMapList(body['priceEvolution'])
          .map(PriceEvolutionPoint.fromJson)
          .toList(growable: false),
    );
  }

  static const empty = PropertyAnalyticsData(
    summary: PropertySummaryStats.empty,
    regionRanking: [],
    avgValuesByType: [],
    priceEvolution: [],
  );
}

/// Filtros do analytics de imóveis (query de `/dashboard/property-analytics`).
class PropertyAnalyticsFilters {
  final String? status; // available | rented | sold | maintenance | draft
  final String? finality; // sale | rent | both
  final String? propertyType;
  final String? city;
  final String? neighborhood;

  const PropertyAnalyticsFilters({
    this.status,
    this.finality,
    this.propertyType,
    this.city,
    this.neighborhood,
  });

  Map<String, String> toQueryParams() {
    final params = <String, String>{};
    if (status != null && status!.isNotEmpty) params['status'] = status!;
    if (finality != null && finality!.isNotEmpty) {
      params['finality'] = finality!;
    }
    if (propertyType != null && propertyType!.isNotEmpty) {
      params['propertyType'] = propertyType!;
    }
    if (city != null && city!.trim().isNotEmpty) params['city'] = city!.trim();
    if (neighborhood != null && neighborhood!.trim().isNotEmpty) {
      params['neighborhood'] = neighborhood!.trim();
    }
    return params;
  }

  int get activeCount => toQueryParams().length;

  PropertyAnalyticsFilters copyWith({
    String? status,
    String? finality,
    String? propertyType,
    String? city,
    String? neighborhood,
    bool clearStatus = false,
    bool clearFinality = false,
    bool clearType = false,
  }) {
    return PropertyAnalyticsFilters(
      status: clearStatus ? null : (status ?? this.status),
      finality: clearFinality ? null : (finality ?? this.finality),
      propertyType: clearType ? null : (propertyType ?? this.propertyType),
      city: city ?? this.city,
      neighborhood: neighborhood ?? this.neighborhood,
    );
  }
}

/// Tradução pt-BR de tipos de imóvel (paridade `getTypeText` do web).
String propertyTypeLabel(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'house':
      return 'Casa';
    case 'apartment':
      return 'Apartamento';
    case 'commercial':
      return 'Comercial';
    case 'office':
      return 'Escritório';
    case 'store':
      return 'Loja';
    case 'warehouse':
      return 'Galpão';
    case 'townhouse':
      return 'Sobrado';
    case 'penthouse':
      return 'Cobertura';
    case 'studio':
      return 'Studio';
    case 'loft':
      return 'Loft';
    case 'kitnet':
      return 'Kitnet';
    case 'duplex':
      return 'Duplex';
    case 'triplex':
      return 'Triplex';
    case 'farm':
      return 'Chácara/Fazenda';
    case 'land':
      return 'Terreno';
    case 'rural':
      return 'Rural';
    case '':
      return 'Outros';
    default:
      return raw!;
  }
}
