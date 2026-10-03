import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// "Lugares próximos" do mapa da carteira — mesma fonte e mesma consulta do
/// web (`services/overpassApi.ts` + `PropertiesMap.tsx`): POIs gratuitos da
/// base do OpenStreetMap pela Overpass API, sem passar pelo nosso back.
///
/// - Espelhos, na ordem: overpass-api.de e overpass.kumi.systems (só espelhos
///   com o PLANETA — extratos regionais devolvem `[]` para o Brasil).
/// - Teto de 18 s por espelho; `timeout:15` na própria query.
/// - Seletores da mesma chave viram um único statement com regex (menos
///   varreduras = menos 504 do servidor público).
/// - Cache de 10 min por centro/raio/seletores.
/// - Falha de todos os espelhos ≠ "nada por perto" ([NearbyPlacesUnavailable]).
class NearbyPlacesService {
  NearbyPlacesService._();
  static final NearbyPlacesService instance = NearbyPlacesService._();

  static const List<String> endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];
  static const Duration endpointTimeout = Duration(seconds: 18);
  static const Duration cacheTtl = Duration(minutes: 10);

  final Map<String, (DateTime, List<NearbyPlace>)> _cache = {};

  /// Cliente injetável nos testes.
  @visibleForTesting
  http.Client Function() clientFactory = http.Client.new;

  Future<List<NearbyPlace>> fetch({
    required double lat,
    required double lng,
    double radiusMeters = kNearbyRadiusMeters,
    List<NearbyCategory> categories = kNearbyCategories,
    int maxPerCategory = kNearbyMaxPerCategory,
  }) async {
    if (categories.isEmpty) return const [];
    final key = nearbyCacheKey(lat, lng, radiusMeters, categories);
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.$1) < cacheTtl) {
      return hit.$2;
    }
    final query = buildOverpassQuery(lat, lng, radiusMeters, categories);
    Object? lastError;
    final client = clientFactory();
    try {
      for (final endpoint in endpoints) {
        try {
          final res = await client
              .post(
                Uri.parse(endpoint),
                headers: const {
                  'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: 'data=${Uri.encodeQueryComponent(query)}',
              )
              .timeout(endpointTimeout);
          if (res.statusCode < 200 || res.statusCode >= 300) {
            lastError = 'Overpass HTTP ${res.statusCode}';
            continue;
          }
          final places = parseOverpassResponse(
            jsonDecode(utf8.decode(res.bodyBytes)),
            categories,
            maxPerCategory: maxPerCategory,
          );
          _cache[key] = (DateTime.now(), places);
          return places;
        } catch (e) {
          lastError = e;
        }
      }
    } finally {
      client.close();
    }
    debugPrint('⚠️ [NEARBY] Overpass falhou em todos os espelhos: $lastError');
    throw NearbyPlacesUnavailable(lastError);
  }
}

/// Todos os espelhos falharam (diferente de "não há nada por perto").
class NearbyPlacesUnavailable implements Exception {
  NearbyPlacesUnavailable([this.cause]);
  final Object? cause;

  @override
  String toString() => 'Não foi possível consultar os locais próximos agora.';
}

enum NearbyCategoryKey { market, health, pharmacy, school }

@immutable
class NearbyCategory {
  final NearbyCategoryKey key;
  final String label;
  final Color color;
  final List<String> selectors;

  const NearbyCategory(this.key, this.label, this.color, this.selectors);
}

/// Mesmas categorias, cores e seletores do web.
const List<NearbyCategory> kNearbyCategories = [
  NearbyCategory(NearbyCategoryKey.market, 'Mercados', Color(0xFF16A34A), [
    'shop=supermarket',
  ]),
  NearbyCategory(NearbyCategoryKey.health, 'Saúde', Color(0xFFDC2626), [
    'amenity=hospital',
    'amenity=clinic',
  ]),
  NearbyCategory(NearbyCategoryKey.pharmacy, 'Farmácias', Color(0xFF0EA5E9), [
    'amenity=pharmacy',
  ]),
  NearbyCategory(NearbyCategoryKey.school, 'Escolas', Color(0xFF7C3AED), [
    'amenity=school',
  ]),
];

const double kNearbyRadiusMeters = 1800;
const int kNearbyMaxPerCategory = 8;

/// Distância mínima (graus, ~300 m) para refazer a busca ao mover o mapa.
const double kNearbyRefetchDelta = 0.0027;

NearbyCategory nearbyCategoryOf(NearbyCategoryKey key) =>
    kNearbyCategories.firstWhere((c) => c.key == key);

@immutable
class NearbyPlace {
  final String id;
  final NearbyCategoryKey category;
  final String name;
  final double lat;
  final double lng;
  final String? address;

  const NearbyPlace({
    required this.id,
    required this.category,
    required this.name,
    required this.lat,
    required this.lng,
    this.address,
  });
}

(String, String)? _parseSelector(String sel) {
  final idx = sel.indexOf('=');
  if (idx <= 0) return null;
  return (sel.substring(0, idx).trim(), sel.substring(idx + 1).trim());
}

String _escapeRegex(String v) =>
    v.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (m) => '\\${m[0]}');

/// Query Overpass QL idêntica à do web (`buildQuery`).
String buildOverpassQuery(
  double lat,
  double lng,
  double radiusMeters,
  List<NearbyCategory> categories,
) {
  final all = <String>{for (final c in categories) ...c.selectors};
  final byKey = <String, List<String>>{};
  for (final sel in all) {
    final parsed = _parseSelector(sel);
    if (parsed == null) continue;
    byKey.putIfAbsent(parsed.$1, () => []).add(parsed.$2);
  }
  final around = '${radiusMeters.round()},$lat,$lng';
  final lines = byKey.entries
      .map((e) {
        final match = e.value.length == 1
            ? '["${e.key}"="${e.value.first}"]'
            : '["${e.key}"~"^(${e.value.map(_escapeRegex).join('|')})\$"]';
        return '  nwr(around:$around)$match;';
      })
      .join('\n');
  return '[out:json][timeout:15];\n(\n$lines\n);\nout center tags 200;';
}

String nearbyCacheKey(
  double lat,
  double lng,
  double radiusMeters,
  List<NearbyCategory> categories,
) {
  final selectors = [for (final c in categories) ...c.selectors]..sort();
  return '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}|'
      '${radiusMeters.round()}|${selectors.join(',')}';
}

NearbyCategoryKey? _classify(
  Map<String, String> tags,
  List<NearbyCategory> categories,
) {
  for (final c in categories) {
    for (final sel in c.selectors) {
      final parsed = _parseSelector(sel);
      if (parsed != null && tags[parsed.$1] == parsed.$2) return c.key;
    }
  }
  return null;
}

String? _address(Map<String, String> tags) {
  final street = [
    tags['addr:street'],
    tags['addr:housenumber'],
  ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
  final parts = [
    street,
    tags['addr:suburb'] ?? tags['addr:neighbourhood'],
    tags['addr:city'],
  ].whereType<String>().where((s) => s.isNotEmpty).toList();
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Converte a resposta do Overpass em POIs classificados, sem repetir
/// elemento e com teto por categoria (mesma regra do web).
List<NearbyPlace> parseOverpassResponse(
  Object? body,
  List<NearbyCategory> categories, {
  int maxPerCategory = kNearbyMaxPerCategory,
}) {
  final elements = body is Map ? body['elements'] : null;
  if (elements is! List) return const [];
  final seen = <String>{};
  final perCategory = <NearbyCategoryKey, int>{};
  final out = <NearbyPlace>[];
  for (final el in elements) {
    if (el is! Map) continue;
    final rawTags = el['tags'];
    final tags = <String, String>{
      if (rawTags is Map)
        for (final e in rawTags.entries) '${e.key}': '${e.value}',
    };
    final center = el['center'];
    final lat = (el['lat'] ?? (center is Map ? center['lat'] : null)) as num?;
    final lng = (el['lon'] ?? (center is Map ? center['lon'] : null)) as num?;
    if (lat == null || lng == null) continue;
    final cat = _classify(tags, categories);
    if (cat == null) continue;
    final id = '${el['type']}/${el['id']}';
    if (seen.contains(id)) continue;
    final count = perCategory[cat] ?? 0;
    if (count >= maxPerCategory) continue;
    seen.add(id);
    perCategory[cat] = count + 1;
    out.add(
      NearbyPlace(
        id: id,
        category: cat,
        name: tags['name'] ?? tags['name:pt'] ?? 'Local sem nome',
        lat: lat.toDouble(),
        lng: lng.toDouble(),
        address: _address(tags),
      ),
    );
  }
  return out;
}

/// Precisa refazer a busca? Sim na primeira vez, ao trocar a base (imóvel
/// selecionado) ou quando o centro andou mais de ~300 m.
bool shouldRefetchNearby({
  required (double, double)? previous,
  required (double, double) next,
  required bool anchoredOnSelection,
}) {
  if (previous == null || anchoredOnSelection) return true;
  return (previous.$1 - next.$1).abs() >= kNearbyRefetchDelta ||
      (previous.$2 - next.$2).abs() >= kNearbyRefetchDelta;
}
