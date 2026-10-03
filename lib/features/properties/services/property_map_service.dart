import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../../../shared/services/property_service.dart';

/// Mapa da carteira — paridade com `PropertiesMapExplorer.tsx` (web) sobre
/// `GET /properties/map` (back `properties.controller.ts` ~3012).
///
/// O back devolve no máximo 120 marcadores por consulta (os mais visitados no
/// site, completando com os mais novos), aplicando os MESMOS filtros e o
/// mesmo escopo de dados da listagem. Com `n/s/e/w` a consulta fica restrita
/// ao retângulo visível ("Pesquisar nesta área").
class PropertyMapService {
  PropertyMapService._();
  static final PropertyMapService instance = PropertyMapService._();

  final ApiService _api = ApiService.instance;

  Future<ApiResponse<PropertyMapResult>> getMarkers({
    PropertyFilters? filters,
    PropertyMapBounds? bounds,
  }) async {
    try {
      final response = await _api.get<dynamic>(
        '/properties/map',
        queryParameters: buildPropertyMapQuery(filters, bounds: bounds),
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: PropertyMapResult.fromJson(response.data),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar o mapa de imóveis',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_MAP] /properties/map: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}

/// Parâmetros que o `GET /properties/map` lê (o resto da listagem — ordem,
/// `features`, `isActive`… — ele ignora; não mandamos). Desde 03/10 o back
/// usa no mapa o mesmo `buildPropertyListFilters` da listagem.
const Set<String> kPropertyMapQueryKeys = {
  'type',
  'status',
  'city',
  'state',
  'neighborhood',
  'sector',
  'zipCode',
  'minPrice',
  'maxPrice',
  'minSalePrice',
  'maxSalePrice',
  'minRentPrice',
  'maxRentPrice',
  'operation',
  'finalidade',
  'minArea',
  'maxArea',
  'bedrooms',
  'rooms',
  'suites',
  'bathrooms',
  'parkingSpaces',
  'isFeatured',
  'search',
  'code',
  'ownerName',
  'ownerPhone',
  'number',
  'propertyUnity',
  'tower',
  'block',
  'lot',
  'street',
  'condominium',
  'onlyMyData',
  'teamId',
  'captorsTeamId',
  'createdFrom',
  'createdTo',
  'condominiumId',
  'responsibleUserId',
  'responsibleWithoutCaptor',
  'includeInactive',
  'listDeletedOnly',
  'portfolioScope',
};

/// Monta a query do mapa: os filtros da listagem (só as chaves que o
/// endpoint lê) + o retângulo visível, quando houver.
Map<String, String> buildPropertyMapQuery(
  PropertyFilters? filters, {
  PropertyMapBounds? bounds,
}) {
  final out = <String, String>{};
  final raw = filters?.toQueryParams() ?? const <String, dynamic>{};
  raw.forEach((key, value) {
    if (!kPropertyMapQueryKeys.contains(key) || value == null) return;
    if (value is List) return;
    final text = _queryValue(value);
    if (text.isEmpty) return;
    out[key] = text;
  });
  if (bounds != null) {
    out['n'] = '${bounds.north}';
    out['s'] = '${bounds.south}';
    out['e'] = '${bounds.east}';
    out['w'] = '${bounds.west}';
  }
  return out;
}

String _queryValue(Object value) {
  if (value is double) {
    return value == value.truncateToDouble()
        ? value.toInt().toString()
        : value.toString();
  }
  return value.toString().trim();
}

/// Retângulo do mapa (graus). Mesmo formato do `MapBounds` do web.
@immutable
class PropertyMapBounds {
  final double north;
  final double south;
  final double east;
  final double west;

  const PropertyMapBounds({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  bool contains(double lat, double lng) =>
      lat <= north && lat >= south && lng <= east && lng >= west;
}

double? _toDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  final parsed = double.tryParse(v.toString().trim());
  return parsed;
}

int? _toInt(Object? v) {
  final d = _toDouble(v);
  return d?.round();
}

String? _toStr(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// Marcador enxuto do mapa (contrato do back, `getPropertiesMapMarkers`).
@immutable
class PropertyMapMarker {
  final String id;
  final double lat;
  final double lng;
  final String title;
  final String? code;
  final String type;
  final String status;
  final double? price;
  final double? salePrice;
  final double? rentPrice;
  final String? thumbnail;
  final int? bedrooms;
  final int? bathrooms;
  final int? parkingSpaces;
  final double? area;
  final String? city;
  final String? state;
  final String? neighborhood;

  const PropertyMapMarker({
    required this.id,
    required this.lat,
    required this.lng,
    required this.title,
    this.code,
    required this.type,
    required this.status,
    this.price,
    this.salePrice,
    this.rentPrice,
    this.thumbnail,
    this.bedrooms,
    this.bathrooms,
    this.parkingSpaces,
    this.area,
    this.city,
    this.state,
    this.neighborhood,
  });

  /// `null` quando falta id ou coordenada válida (o back já filtra, mas o
  /// app não confia: um marcador sem posição derrubaria o mapa).
  static PropertyMapMarker? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final id = _toStr(json['id']);
    final lat = _toDouble(json['lat'] ?? json['latitude']);
    final lng = _toDouble(json['lng'] ?? json['longitude']);
    if (id == null || lat == null || lng == null) return null;
    if (!lat.isFinite || !lng.isFinite) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return PropertyMapMarker(
      id: id,
      lat: lat,
      lng: lng,
      title: _toStr(json['title']) ?? 'Imóvel',
      code: _toStr(json['code']),
      type: _toStr(json['type']) ?? '',
      status: _toStr(json['status']) ?? '',
      price: _toDouble(json['price']),
      salePrice: _toDouble(json['salePrice']),
      rentPrice: _toDouble(json['rentPrice']),
      thumbnail: _toStr(json['thumbnail']),
      bedrooms: _toInt(json['bedrooms']),
      bathrooms: _toInt(json['bathrooms']),
      parkingSpaces: _toInt(json['parkingSpaces']),
      area: _toDouble(json['area']),
      city: _toStr(json['city']),
      state: _toStr(json['state']),
      neighborhood: _toStr(json['neighborhood']),
    );
  }

  bool get hasSale => (salePrice ?? 0) > 0;
  bool get hasRent => (rentPrice ?? 0) > 0;

  /// Preço usado nas ordenações (mesma regra do web: `price || sale || rent`).
  double get sortPrice {
    for (final v in [price, salePrice, rentPrice]) {
      if (v != null && v > 0) return v;
    }
    return 0;
  }
}

@immutable
class PropertyMapResult {
  final List<PropertyMapMarker> markers;
  final int total;
  final bool truncated;

  const PropertyMapResult({
    required this.markers,
    required this.total,
    required this.truncated,
  });

  factory PropertyMapResult.fromJson(Object? raw) {
    Map<String, dynamic> body = const {};
    if (raw is Map) {
      body = Map<String, dynamic>.from(raw);
      // Envelope `{ success, data: {...} }` (alguns interceptors embrulham).
      final inner = body['data'];
      if (body['markers'] == null && inner is Map) {
        body = Map<String, dynamic>.from(inner);
      }
    }
    final list = body['markers'];
    final markers = <PropertyMapMarker>[];
    if (list is List) {
      for (final item in list) {
        final m = PropertyMapMarker.tryParse(item);
        if (m != null) markers.add(m);
      }
    }
    return PropertyMapResult(
      markers: markers,
      total: _toInt(body['total']) ?? markers.length,
      truncated: body['truncated'] == true || body['truncated'] == 'true',
    );
  }
}

// ─── Agrupamento (paridade `utils/propertyMapGrouping.ts`) ────────────────

enum PropertyMapGroupBy {
  city('Cidade'),
  price('Valor'),
  operation('Operação'),
  type('Tipo'),
  status('Status');

  final String label;
  const PropertyMapGroupBy(this.label);

  static PropertyMapGroupBy fromName(String? raw) {
    for (final g in values) {
      if (g.name == raw) return g;
    }
    return PropertyMapGroupBy.city;
  }
}

enum PropertyMapOperation { sale, rent, both, none }

PropertyMapOperation markerOperation(PropertyMapMarker m) {
  if (m.hasSale && m.hasRent) return PropertyMapOperation.both;
  if (m.hasSale) return PropertyMapOperation.sale;
  if (m.hasRent) return PropertyMapOperation.rent;
  return PropertyMapOperation.none;
}

const Map<PropertyMapOperation, (String, Color)> kOperationMeta = {
  PropertyMapOperation.sale: ('Venda', Color(0xFF2563EB)),
  PropertyMapOperation.rent: ('Aluguel', Color(0xFF7C3AED)),
  PropertyMapOperation.both: ('Venda e aluguel', Color(0xFF0891B2)),
  PropertyMapOperation.none: ('Sem preço', Color(0xFF64748B)),
};

const List<Color> kMapCategoricalPalette = [
  Color(0xFF2563EB),
  Color(0xFF059669),
  Color(0xFFD97706),
  Color(0xFFDC2626),
  Color(0xFF7C3AED),
  Color(0xFF0891B2),
  Color(0xFFDB2777),
  Color(0xFF65A30D),
  Color(0xFFEA580C),
  Color(0xFF4F46E5),
  Color(0xFF0D9488),
  Color(0xFFB45309),
];

const Color kMapNeutralColor = Color(0xFF64748B);

/// Faixas de valor (ordem crescente), iguais às do web.
const List<(double, String, Color)> kMapPriceTiers = [
  (250000, 'Até R\$ 250 mil', Color(0xFF0EA5E9)),
  (500000, 'R\$ 250–500 mil', Color(0xFF22C55E)),
  (1000000, 'R\$ 500 mil – 1 mi', Color(0xFFF59E0B)),
  (2000000, 'R\$ 1 – 2 mi', Color(0xFFEF4444)),
  (double.infinity, 'Acima de R\$ 2 mi', Color(0xFF8B5CF6)),
];

const Map<String, Color> kMapStatusColors = {
  'available': Color(0xFF059669),
  'sold': Color(0xFF475569),
  'rented': Color(0xFFB45309),
  'pending_approval': Color(0xFF2563EB),
  'pending_publication': Color(0xFF7C3AED),
  'pending_owner_authorization': Color(0xFF0891B2),
  'rejected': Color(0xFFDC2626),
  'draft': Color(0xFF64748B),
};

/// Hash de string idêntico ao do web (`(h << 5) - h + c`, inteiro de 32
/// bits) — a mesma cidade/tipo ganha a mesma cor nas duas plataformas.
int mapHashString(String value) {
  var hash = 0;
  for (final unit in value.codeUnits) {
    hash = ((hash << 5) - hash + unit).toSigned(32);
  }
  return hash.abs();
}

Color mapColorFromPalette(String value) =>
    kMapCategoricalPalette[mapHashString(value) %
        kMapCategoricalPalette.length];

int mapPriceTierIndex(double? price) {
  if (price == null || price <= 0) return -1;
  for (var i = 0; i < kMapPriceTiers.length; i++) {
    if (price <= kMapPriceTiers[i].$1) return i;
  }
  return kMapPriceTiers.length - 1;
}

@immutable
class PropertyMapGroup {
  final String key;
  final String label;
  final Color color;
  final List<PropertyMapMarker> markers;

  const PropertyMapGroup({
    required this.key,
    required this.label,
    required this.color,
    required this.markers,
  });
}

@immutable
class PropertyMapGrouping {
  final List<PropertyMapGroup> groups;
  final Map<String, Color> colorByMarkerId;

  const PropertyMapGrouping(this.groups, this.colorByMarkerId);
}

/// Agrupa os marcadores pela dimensão escolhida (legenda + lista + cor do
/// pino). Faixas de valor ficam em ordem crescente; as demais por tamanho.
PropertyMapGrouping buildPropertyMapGroups(
  List<PropertyMapMarker> markers,
  PropertyMapGroupBy groupBy, {
  String Function(String raw)? typeLabel,
  String Function(String raw)? statusLabel,
}) {
  final colorById = <String, Color>{};
  final tLabel = typeLabel ?? PropertyType.labelOf;
  final sLabel = statusLabel ?? PropertyStatus.labelOf;

  if (groupBy == PropertyMapGroupBy.price) {
    final buckets = <int, List<PropertyMapMarker>>{};
    for (final m in markers) {
      final idx = mapPriceTierIndex(m.price);
      buckets.putIfAbsent(idx, () => []).add(m);
      colorById[m.id] = idx < 0 ? kMapNeutralColor : kMapPriceTiers[idx].$3;
    }
    final groups = <PropertyMapGroup>[];
    for (var i = 0; i < kMapPriceTiers.length; i++) {
      final list = buckets[i];
      if (list != null && list.isNotEmpty) {
        groups.add(
          PropertyMapGroup(
            key: 'tier-$i',
            label: kMapPriceTiers[i].$2,
            color: kMapPriceTiers[i].$3,
            markers: list,
          ),
        );
      }
    }
    final noPrice = buckets[-1];
    if (noPrice != null && noPrice.isNotEmpty) {
      groups.add(
        PropertyMapGroup(
          key: 'no-price',
          label: 'Sem preço',
          color: kMapNeutralColor,
          markers: noPrice,
        ),
      );
    }
    return PropertyMapGrouping(groups, colorById);
  }

  (String, String, Color) keyOf(PropertyMapMarker m) {
    switch (groupBy) {
      case PropertyMapGroupBy.operation:
        final op = markerOperation(m);
        final meta = kOperationMeta[op]!;
        return (op.name, meta.$1, meta.$2);
      case PropertyMapGroupBy.city:
        final label = (m.city ?? '').trim().isEmpty
            ? 'Sem cidade'
            : m.city!.trim();
        return (
          label.toLowerCase(),
          label,
          label == 'Sem cidade'
              ? kMapNeutralColor
              : mapColorFromPalette(label.toLowerCase()),
        );
      case PropertyMapGroupBy.status:
        final label = sLabel(m.status);
        return (
          m.status,
          label.isEmpty ? 'Sem status' : label,
          kMapStatusColors[m.status] ?? mapColorFromPalette(m.status),
        );
      case PropertyMapGroupBy.type:
      case PropertyMapGroupBy.price:
        final label = tLabel(m.type);
        return (
          m.type,
          label.isEmpty ? 'Sem tipo' : label,
          mapColorFromPalette(m.type),
        );
    }
  }

  final byKey = <String, PropertyMapGroup>{};
  final order = <String>[];
  for (final m in markers) {
    final (key, label, color) = keyOf(m);
    colorById[m.id] = color;
    final existing = byKey[key];
    if (existing == null) {
      byKey[key] = PropertyMapGroup(
        key: key,
        label: label,
        color: color,
        markers: [m],
      );
      order.add(key);
    } else {
      existing.markers.add(m);
    }
  }
  final groups = [for (final k in order) byKey[k]!]
    ..sort((a, b) => b.markers.length.compareTo(a.markers.length));
  return PropertyMapGrouping(groups, colorById);
}

// ─── Ordenação da lista ───────────────────────────────────────────────────

enum PropertyMapSort {
  relevance('Relevância'),
  priceAsc('Menor preço'),
  priceDesc('Maior preço');

  final String label;
  const PropertyMapSort(this.label);
}

/// Relevância = ordem do back (mais visitados no site). Sem preço vai para o
/// fim no "menor preço" (igual ao `|| Infinity` do web).
List<PropertyMapMarker> sortPropertyMapMarkers(
  List<PropertyMapMarker> markers,
  PropertyMapSort sort,
) {
  final out = [...markers];
  switch (sort) {
    case PropertyMapSort.relevance:
      return out;
    case PropertyMapSort.priceAsc:
      double key(PropertyMapMarker m) =>
          m.sortPrice > 0 ? m.sortPrice : double.infinity;
      out.sort((a, b) => key(a).compareTo(key(b)));
      return out;
    case PropertyMapSort.priceDesc:
      out.sort((a, b) => b.sortPrice.compareTo(a.sortPrice));
      return out;
  }
}

// ─── Estatísticas da área visível ─────────────────────────────────────────

@immutable
class PropertyMapAreaStats {
  final int count;
  final double? avgSale;
  final double? avgRent;
  final double? avgPricePerSqm;

  const PropertyMapAreaStats({
    required this.count,
    this.avgSale,
    this.avgRent,
    this.avgPricePerSqm,
  });
}

/// Médias dos imóveis dentro do retângulo visível (sem retângulo = todos).
PropertyMapAreaStats computePropertyMapAreaStats(
  Iterable<PropertyMapMarker> markers,
  PropertyMapBounds? bounds,
) {
  var count = 0;
  var saleSum = 0.0, saleN = 0;
  var rentSum = 0.0, rentN = 0;
  var ppmSum = 0.0, ppmN = 0;
  for (final m in markers) {
    if (bounds != null && !bounds.contains(m.lat, m.lng)) continue;
    count++;
    if (m.hasSale) {
      saleSum += m.salePrice!;
      saleN++;
      if ((m.area ?? 0) > 0) {
        ppmSum += m.salePrice! / m.area!;
        ppmN++;
      }
    }
    if (m.hasRent) {
      rentSum += m.rentPrice!;
      rentN++;
    }
  }
  return PropertyMapAreaStats(
    count: count,
    avgSale: saleN > 0 ? saleSum / saleN : null,
    avgRent: rentN > 0 ? rentSum / rentN : null,
    avgPricePerSqm: ppmN > 0 ? ppmSum / ppmN : null,
  );
}

// ─── Pílula de preço ──────────────────────────────────────────────────────

/// Preço compacto da pílula do pino (R$ 450 mil / R$ 1,2 mi).
String compactMapPrice(double? value) {
  if (value == null || value <= 0) return 'Consulte';
  if (value >= 1000000) {
    final mi = value / 1000000;
    return 'R\$ ${mi.toStringAsFixed(mi >= 10 ? 0 : 1).replaceAll('.', ',')} mi';
  }
  if (value >= 1000) return 'R\$ ${(value / 1000).round()} mil';
  return 'R\$ ${value.round()}';
}

/// Rótulo da pílula: venda; senão aluguel com "/mês"; senão o `price`.
String mapPillPriceLabel(PropertyMapMarker m) {
  if (m.hasSale) return compactMapPrice(m.salePrice);
  if (m.hasRent) return '${compactMapPrice(m.rentPrice)}/mês';
  return compactMapPrice(m.price);
}

// ─── Enquadramento inicial e agrupamento por proximidade ──────────────────

/// Região com mais imóveis (grade de ~11 km + vizinhança 3×3), para o mapa
/// abrir focado na cidade principal em vez do país inteiro — igual ao web.
List<PropertyMapMarker> pickDensestMapRegion(List<PropertyMapMarker> markers) {
  if (markers.length <= 1) return [...markers];
  const cell = 0.1;
  (int, int) cellOf(PropertyMapMarker m) =>
      ((m.lat / cell).round(), (m.lng / cell).round());

  final counts = <(int, int), int>{};
  (int, int)? best;
  var bestCount = 0;
  for (final m in markers) {
    final c = cellOf(m);
    final next = (counts[c] ?? 0) + 1;
    counts[c] = next;
    if (next > bestCount) {
      bestCount = next;
      best = c;
    }
  }
  if (best == null || bestCount < 3) return [...markers];
  final (by, bx) = best;
  final group = markers.where((m) {
    final (cy, cx) = cellOf(m);
    return (cy - by).abs() <= 1 && (cx - bx).abs() <= 1;
  }).toList();
  return group.isEmpty ? [...markers] : group;
}

/// Projeção Web Mercator em pixels lógicos (tiles de 256) no [zoom].
math.Point<double> projectMapPoint(double lat, double lng, double zoom) {
  final scale = 256.0 * math.pow(2, zoom);
  final x = (lng + 180.0) / 360.0 * scale;
  final clamped = lat.clamp(-85.05112878, 85.05112878);
  final sinLat = math.sin(clamped * math.pi / 180.0);
  final y =
      (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * scale;
  return math.Point(x, y);
}

@immutable
class PropertyMapCluster {
  final List<PropertyMapMarker> markers;
  final double lat;
  final double lng;

  const PropertyMapCluster(this.markers, this.lat, this.lng);

  bool get isSingle => markers.length == 1;
}

/// Agrupamento por proximidade na tela — equivalente ao
/// `leaflet.markercluster` do web (raio 70 px, desligado a partir do zoom 18).
List<PropertyMapCluster> clusterPropertyMapMarkers(
  List<PropertyMapMarker> markers,
  double zoom, {
  double radiusPx = 70,
  double disableAtZoom = 18,
}) {
  if (zoom >= disableAtZoom) {
    return [
      for (final m in markers) PropertyMapCluster([m], m.lat, m.lng),
    ];
  }
  final seeds = <math.Point<double>>[];
  final buckets = <List<PropertyMapMarker>>[];
  final r2 = radiusPx * radiusPx;
  for (final m in markers) {
    final p = projectMapPoint(m.lat, m.lng, zoom);
    var placed = false;
    for (var i = 0; i < seeds.length; i++) {
      final dx = seeds[i].x - p.x;
      final dy = seeds[i].y - p.y;
      if (dx * dx + dy * dy <= r2) {
        buckets[i].add(m);
        placed = true;
        break;
      }
    }
    if (!placed) {
      seeds.add(p);
      buckets.add([m]);
    }
  }
  return [
    for (final b in buckets)
      PropertyMapCluster(
        b,
        b.map((m) => m.lat).reduce((a, c) => a + c) / b.length,
        b.map((m) => m.lng).reduce((a, c) => a + c) / b.length,
      ),
  ];
}

// ─── Filtros ativos (chips removíveis) ────────────────────────────────────

/// Abas do mapa — as mesmas do web (`PORTFOLIO_TABS`). `null` = Todos.
const List<(PortfolioScope?, String)> kPropertyMapTabs = [
  (null, 'Todos'),
  (PortfolioScope.available, 'Disponíveis'),
  (PortfolioScope.sold, 'Vendidos'),
  (PortfolioScope.pending, 'Pendentes'),
  (PortfolioScope.rejected, 'Recusados'),
];

@immutable
class PropertyMapFilterChip {
  final String key;
  final String label;
  const PropertyMapFilterChip(this.key, this.label);
}

String _brl(double v) {
  final whole = v.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    final fromEnd = whole.length - i;
    buf.write(whole[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buf.write('.');
  }
  return 'R\$ $buf';
}

String _num(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

/// Chips dos filtros vindos da listagem (paridade `buildActiveChips` do web
/// + os que o app manda a mais: finalidade, código, condomínio, "só meus").
List<PropertyMapFilterChip> buildPropertyMapFilterChips(PropertyFilters? f) {
  if (f == null) return const [];
  final chips = <PropertyMapFilterChip>[];
  void add(String key, String? label) {
    if (label != null && label.trim().isNotEmpty) {
      chips.add(PropertyMapFilterChip(key, label.trim()));
    }
  }

  add('type', f.type?.label);
  add('status', f.status?.label);
  add('city', f.city);
  add('neighborhood', f.neighborhood);
  add('state', f.state);
  add('street', f.street);
  if ((f.condominiumId ?? '').isNotEmpty) add('condominiumId', 'Condomínio');
  if (f.minPrice != null) add('minPrice', 'Mín ${_brl(f.minPrice!)}');
  if (f.maxPrice != null) add('maxPrice', 'Máx ${_brl(f.maxPrice!)}');
  if (f.bedrooms != null) add('bedrooms', '${f.bedrooms}+ quartos');
  if (f.bathrooms != null) add('bathrooms', '${f.bathrooms}+ banh.');
  if (f.parkingSpaces != null) {
    add('parkingSpaces', '${f.parkingSpaces}+ vagas');
  }
  if (f.minArea != null) add('minArea', '≥ ${_num(f.minArea!)}m²');
  if (f.maxArea != null) add('maxArea', '≤ ${_num(f.maxArea!)}m²');
  switch (f.finalidade) {
    case 'venda':
      add('finalidade', 'Venda');
    case 'locacao':
      add('finalidade', 'Locação');
    case 'ambos':
      add('finalidade', 'Venda e locação');
  }
  if ((f.code ?? '').trim().isNotEmpty) add('code', 'Cód. ${f.code!.trim()}');
  if ((f.responsibleUserId ?? '').isNotEmpty) {
    add('responsibleUserId', 'Responsável');
  }
  if (f.isFeatured == true) add('isFeatured', 'Destaques');
  if ((f.sector ?? '').trim().isNotEmpty) {
    add('sector', 'Setor ${f.sector!.trim()}');
  }
  if ((f.ownerName ?? '').trim().isNotEmpty) {
    add('ownerName', 'Proprietário: ${f.ownerName!.trim()}');
  }
  if ((f.teamId ?? '').isNotEmpty) add('teamId', 'Equipe do imóvel');
  if ((f.captorsTeamId ?? '').isNotEmpty) {
    add('captorsTeamId', 'Equipe dos captadores');
  }
  if (f.responsibleWithoutCaptor == true) {
    add('responsibleWithoutCaptor', 'Sem captador');
  }
  if (f.includeInactive == true) add('includeInactive', 'Inclui inativos');
  if (f.listDeletedOnly == true) add('listDeletedOnly', 'Só excluídos');
  return chips;
}

/// Cópia dos filtros sem o campo [key] (o `copyWith` não sabe anular).
PropertyFilters propertyFiltersWithout(PropertyFilters f, String key) {
  bool keep(String k) => k != key;
  return PropertyFilters(
    type: keep('type') ? f.type : null,
    status: keep('status') ? f.status : null,
    city: keep('city') ? f.city : null,
    state: keep('state') ? f.state : null,
    neighborhood: keep('neighborhood') ? f.neighborhood : null,
    street: keep('street') ? f.street : null,
    condominiumId: keep('condominiumId') ? f.condominiumId : null,
    minPrice: keep('minPrice') ? f.minPrice : null,
    maxPrice: keep('maxPrice') ? f.maxPrice : null,
    minArea: keep('minArea') ? f.minArea : null,
    maxArea: keep('maxArea') ? f.maxArea : null,
    bedrooms: keep('bedrooms') ? f.bedrooms : null,
    bathrooms: keep('bathrooms') ? f.bathrooms : null,
    parkingSpaces: keep('parkingSpaces') ? f.parkingSpaces : null,
    features: keep('features') ? f.features : null,
    isActive: keep('isActive') ? f.isActive : null,
    isFeatured: keep('isFeatured') ? f.isFeatured : null,
    companyId: keep('companyId') ? f.companyId : null,
    responsibleUserId: keep('responsibleUserId') ? f.responsibleUserId : null,
    search: keep('search') ? f.search : null,
    onlyMyData: keep('onlyMyData') ? f.onlyMyData : null,
    portfolioScope: keep('portfolioScope') ? f.portfolioScope : null,
    includeInactive: keep('includeInactive') ? f.includeInactive : null,
    sortBy: keep('sortBy') ? f.sortBy : null,
    sortOrder: keep('sortOrder') ? f.sortOrder : null,
    finalidade: keep('finalidade') ? f.finalidade : null,
    code: keep('code') ? f.code : null,
    zipCode: keep('zipCode') ? f.zipCode : null,
    sector: keep('sector') ? f.sector : null,
    ownerName: keep('ownerName') ? f.ownerName : null,
    ownerPhone: keep('ownerPhone') ? f.ownerPhone : null,
    number: keep('number') ? f.number : null,
    propertyUnity: keep('propertyUnity') ? f.propertyUnity : null,
    tower: keep('tower') ? f.tower : null,
    block: keep('block') ? f.block : null,
    lot: keep('lot') ? f.lot : null,
    createdFrom: keep('createdFrom') ? f.createdFrom : null,
    createdTo: keep('createdTo') ? f.createdTo : null,
    teamId: keep('teamId') ? f.teamId : null,
    captorsTeamId: keep('captorsTeamId') ? f.captorsTeamId : null,
    responsibleWithoutCaptor: keep('responsibleWithoutCaptor')
        ? f.responsibleWithoutCaptor
        : null,
    minSalePrice: keep('minSalePrice') ? f.minSalePrice : null,
    maxSalePrice: keep('maxSalePrice') ? f.maxSalePrice : null,
    minRentPrice: keep('minRentPrice') ? f.minRentPrice : null,
    maxRentPrice: keep('maxRentPrice') ? f.maxRentPrice : null,
    suites: keep('suites') ? f.suites : null,
    rooms: keep('rooms') ? f.rooms : null,
    listDeletedOnly: keep('listDeletedOnly') ? f.listDeletedOnly : null,
  );
}

/// Chaves que não são filtro (ordem, escopo técnico) — fora da contagem.
const Set<String> _kNonFilterKeys = {
  'sortBy',
  'sortOrder',
  'isActive',
  'companyId',
};

/// Filtros vindos do drawer que o `GET /properties/map` NÃO lê (o back só
/// aplica o recorte da [kPropertyMapQueryKeys]). O web manda e o back
/// ignora em silêncio; aqui a tela avisa quais ficaram de fora.
List<String> propertyMapIgnoredFilterKeys(PropertyFilters? f) {
  if (f == null) return const [];
  return [
    for (final e in f.toQueryParams().entries)
      if (!kPropertyMapQueryKeys.contains(e.key) &&
          !_kNonFilterKeys.contains(e.key) &&
          e.value != null &&
          !(e.value is List && (e.value as List).isEmpty))
        e.key,
  ];
}

/// Filtros efetivos do mapa: base (da listagem) + aba + busca + "só meus".
PropertyFilters composePropertyMapFilters({
  PropertyFilters? base,
  PortfolioScope? scope,
  String search = '',
  bool onlyMine = false,
}) {
  var f = base ?? PropertyFilters();
  f = propertyFiltersWithout(f, 'portfolioScope');
  f = propertyFiltersWithout(f, 'search');
  f = propertyFiltersWithout(f, 'onlyMyData');
  f = propertyFiltersWithout(f, 'sortBy');
  f = propertyFiltersWithout(f, 'sortOrder');
  return f.copyWith(
    portfolioScope: scope,
    search: search.trim().isEmpty ? null : search.trim(),
    onlyMyData: onlyMine ? true : null,
  );
}
