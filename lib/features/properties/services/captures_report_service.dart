import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../shared/services/api_service.dart';
import '../../../shared/services/property_service.dart';

/// Relatório de captações — paridade com `CapturesReportPage.tsx` (web),
/// rota `/properties/captures-report`.
///
/// Endpoints (back `analytics/captures-analytics.controller.ts`):
/// - `GET /analytics/captures/report` (~157): imóveis captados + estatísticas
///   numa consulta só. Filtros: `createdFrom`/`createdTo` (AAAA-MM-DD) ou
///   `allDates=true`, `propertyTeamIds`, `capturerIds`, `responsibleIds`
///   (o back aceita lista separada por vírgula) e `includeInactive`.
/// - `GET /analytics/captures/responsible-changes` e `/image-downloads`
///   (`startDate`/`endDate`): auditorias só para gestor/admin/master — 403
///   para os demais, e aí a seção some (igual ao web).
/// - `GET /properties/form-settings`: equipes configuradas no cadastro de
///   imóveis (o relatório conta pela equipe DO IMÓVEL, não do corretor).
/// - `GET /users/company-members/simple`: opções dos seletores.
class CapturesReportService {
  CapturesReportService._();
  static final CapturesReportService instance = CapturesReportService._();

  final ApiService _api = ApiService.instance;

  Future<ApiResponse<CapturesReportResult>> getReport(
    CapturesReportQuery query,
  ) async {
    try {
      final res = await _api.get<dynamic>(
        '/analytics/captures/report',
        queryParameters: query.toQueryParameters(),
      );
      if (res.success && res.data != null) {
        return ApiResponse.success(
          data: CapturesReportResult.fromJson(_unwrap(res.data)),
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.error(
        message: res.message ?? 'Erro ao carregar o relatório de captações',
        statusCode: res.statusCode,
        data: res.error,
      );
    } catch (e) {
      debugPrint('❌ [CAPTURES_REPORT] report: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  Future<ApiResponse<ResponsibleChangesResult>> getResponsibleChanges({
    required String startDate,
    String? endDate,
  }) async {
    try {
      final res = await _api.get<dynamic>(
        '/analytics/captures/responsible-changes',
        queryParameters: {
          'startDate': startDate,
          'endDate': ?endDate,
        },
      );
      if (res.success && res.data != null) {
        return ApiResponse.success(
          data: ResponsibleChangesResult.fromJson(_unwrap(res.data)),
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.error(
        message: res.message ?? 'Não foi possível carregar as trocas de '
            'responsável.',
        statusCode: res.statusCode,
        data: res.error,
      );
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  Future<ApiResponse<ImageDownloadsResult>> getImageDownloads({
    required String startDate,
    String? endDate,
  }) async {
    try {
      final res = await _api.get<dynamic>(
        '/analytics/captures/image-downloads',
        queryParameters: {
          'startDate': startDate,
          'endDate': ?endDate,
        },
      );
      if (res.success && res.data != null) {
        return ApiResponse.success(
          data: ImageDownloadsResult.fromJson(_unwrap(res.data)),
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.error(
        message: res.message ?? 'Não foi possível carregar os downloads de '
            'imagens.',
        statusCode: res.statusCode,
        data: res.error,
      );
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Membros da empresa para os seletores de corretor e responsável.
  Future<List<CapturesReportPerson>> getCompanyMembers() async {
    try {
      final res = await _api.get<dynamic>('/users/company-members/simple');
      if (!res.success) return const [];
      final raw = res.data;
      final list = raw is List
          ? raw
          : (raw is Map && raw['data'] is List ? raw['data'] as List : const []);
      return [
        for (final e in list)
          ?CapturesReportPerson.tryParse(e),
      ];
    } catch (e) {
      debugPrint('⚠️ [CAPTURES_REPORT] company-members: $e');
      return const [];
    }
  }
}

/// `{ success, data }` → `data`; corpo cru → ele mesmo.
Map<String, dynamic> _unwrap(Object? raw) {
  if (raw is Map) {
    final map = Map<String, dynamic>.from(raw);
    final inner = map['data'];
    if (inner is Map && (map.containsKey('success') || map.length == 1)) {
      return Map<String, dynamic>.from(inner);
    }
    return map;
  }
  return const {};
}

double? _d(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim());
}

int? _i(Object? v) => _d(v)?.round();

String? _s(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

DateTime? _date(Object? v) {
  final s = _s(v);
  if (s == null) return null;
  return DateTime.tryParse(s)?.toLocal();
}

// ─── Período ──────────────────────────────────────────────────────────────

final DateFormat _ymd = DateFormat('yyyy-MM-dd');
final DateFormat _br = DateFormat('dd/MM/yyyy');

String capturesYmd(DateTime d) => _ymd.format(d);

/// Primeiro dia do mês corrente (padrão da tela, como no web).
DateTime capturesStartOfMonth(DateTime now) => DateTime(now.year, now.month);

bool isValidCapturesRange(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  return !a.isAfter(b);
}

String capturesPeriodLabel({
  required bool allDates,
  required DateTime from,
  required DateTime to,
}) =>
    allDates ? 'Todo o cadastro' : '${_br.format(from)} – ${_br.format(to)}';

// ─── Query ────────────────────────────────────────────────────────────────

@immutable
class CapturesReportQuery {
  final bool allDates;
  final DateTime createdFrom;
  final DateTime createdTo;
  final List<String> propertyTeamIds;
  final List<String> capturerIds;
  final List<String> responsibleIds;
  final bool includeInactive;

  const CapturesReportQuery({
    required this.allDates,
    required this.createdFrom,
    required this.createdTo,
    this.propertyTeamIds = const [],
    this.capturerIds = const [],
    this.responsibleIds = const [],
    this.includeInactive = false,
  });

  Map<String, String> toQueryParameters() {
    String? joinIds(List<String> ids) {
      final clean = [
        for (final id in ids)
          if (id.trim().isNotEmpty) id.trim(),
      ];
      return clean.isEmpty ? null : clean.toSet().join(',');
    }

    final teams = joinIds(propertyTeamIds);
    final caps = joinIds(capturerIds);
    final resp = joinIds(responsibleIds);
    return {
      if (allDates) 'allDates': 'true',
      if (!allDates) 'createdFrom': capturesYmd(createdFrom),
      if (!allDates) 'createdTo': capturesYmd(createdTo),
      'propertyTeamIds': ?teams,
      'capturerIds': ?caps,
      'responsibleIds': ?resp,
      if (includeInactive) 'includeInactive': 'true',
    };
  }

  /// Chave para saber se os filtros na tela mudaram desde a última consulta
  /// ("Aplicar filtros" + bloqueio da exportação, como no web).
  String get cacheKey {
    List<String> sorted(List<String> l) => [...l]..sort();
    return [
      allDates ? 'all' : '${capturesYmd(createdFrom)}_${capturesYmd(createdTo)}',
      sorted(propertyTeamIds).join(','),
      sorted(capturerIds).join(','),
      sorted(responsibleIds).join(','),
      includeInactive ? 'inativos' : '',
    ].join('|');
  }

  bool get hasOptionalFilters =>
      allDates ||
      includeInactive ||
      propertyTeamIds.isNotEmpty ||
      capturerIds.isNotEmpty ||
      responsibleIds.isNotEmpty;
}

// ─── Modelos ──────────────────────────────────────────────────────────────

@immutable
class CapturesReportPerson {
  final String id;
  final String? name;
  final String? email;
  final String? phone;

  const CapturesReportPerson({
    required this.id,
    this.name,
    this.email,
    this.phone,
  });

  static CapturesReportPerson? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = _s(raw['id']);
    if (id == null) return null;
    return CapturesReportPerson(
      id: id,
      name: _s(raw['name']),
      email: _s(raw['email']),
      phone: _s(raw['phone']),
    );
  }

  /// Nome para exibir: nome → e-mail → id (mesma ordem do web).
  String get displayName => name ?? email ?? id;
}

List<CapturesReportPerson> _people(Object? raw) => [
      if (raw is List)
        for (final e in raw)
          ?CapturesReportPerson.tryParse(e),
    ];

@immutable
class CapturesReportProperty {
  final String id;
  final String? code;
  final String? alternativeCode;
  final String title;
  final String status;
  final String type;
  final String? teamId;
  final String? teamName;
  final String? capturedById;
  final CapturesReportPerson? capturedBy;
  final List<CapturesReportPerson> captors;
  final String? responsibleUserId;
  final CapturesReportPerson? responsibleUser;
  final List<CapturesReportPerson> responsibles;
  final String? address;
  final String? street;
  final String? number;
  final String? complement;
  final String? city;
  final String? state;
  final String? zipCode;
  final String? neighborhood;
  final String? sector;
  final double? totalArea;
  final double? builtArea;
  final int? bedrooms;
  final int? bathrooms;
  final int? suites;
  final int? parkingSpaces;
  final double? salePrice;
  final double? rentPrice;
  final double? minSalePrice;
  final double? minRentPrice;
  final String? ownerName;
  final String? ownerEmail;
  final String? ownerPhone;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CapturesReportProperty({
    required this.id,
    this.code,
    this.alternativeCode,
    required this.title,
    required this.status,
    required this.type,
    this.teamId,
    this.teamName,
    this.capturedById,
    this.capturedBy,
    this.captors = const [],
    this.responsibleUserId,
    this.responsibleUser,
    this.responsibles = const [],
    this.address,
    this.street,
    this.number,
    this.complement,
    this.city,
    this.state,
    this.zipCode,
    this.neighborhood,
    this.sector,
    this.totalArea,
    this.builtArea,
    this.bedrooms,
    this.bathrooms,
    this.suites,
    this.parkingSpaces,
    this.salePrice,
    this.rentPrice,
    this.minSalePrice,
    this.minRentPrice,
    this.ownerName,
    this.ownerEmail,
    this.ownerPhone,
    this.createdAt,
    this.updatedAt,
  });

  static CapturesReportProperty? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final id = _s(json['id']);
    if (id == null) return null;
    final team = json['team'];
    final owner = json['owner'];
    return CapturesReportProperty(
      id: id,
      code: _s(json['code']),
      alternativeCode: _s(json['alternativeCode']),
      title: _s(json['title']) ?? 'Imóvel',
      status: _s(json['status']) ?? '',
      type: _s(json['type']) ?? '',
      teamId: _s(json['teamId']) ?? (team is Map ? _s(team['id']) : null),
      teamName: team is Map ? _s(team['name']) : null,
      capturedById: _s(json['capturedById']),
      capturedBy: CapturesReportPerson.tryParse(json['capturedBy']),
      captors: _people(json['captors']),
      responsibleUserId: _s(json['responsibleUserId']),
      responsibleUser: CapturesReportPerson.tryParse(json['responsibleUser']),
      responsibles: _people(json['responsibles']),
      address: _s(json['address']),
      street: _s(json['street']),
      number: _s(json['number']),
      complement: _s(json['complement']),
      city: _s(json['city']),
      state: _s(json['state']),
      zipCode: _s(json['zipCode']),
      neighborhood: _s(json['neighborhood']),
      sector: _s(json['sector']),
      totalArea: _d(json['totalArea']),
      builtArea: _d(json['builtArea']),
      bedrooms: _i(json['bedrooms']),
      bathrooms: _i(json['bathrooms']),
      suites: _i(json['suites']),
      parkingSpaces: _i(json['parkingSpaces']),
      salePrice: _d(json['salePrice']),
      rentPrice: _d(json['rentPrice']),
      minSalePrice: _d(json['minSalePrice']),
      minRentPrice: _d(json['minRentPrice']),
      ownerName: owner is Map ? _s(owner['name']) : null,
      ownerEmail: owner is Map ? _s(owner['email']) : null,
      ownerPhone: owner is Map ? _s(owner['phone']) : null,
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
    );
  }

  /// Captador principal: `capturedBy` → captador com o id principal → 1º.
  CapturesReportPerson? get primaryCaptor {
    if (capturedBy != null) return capturedBy;
    for (final c in captors) {
      if (c.id == capturedById) return c;
    }
    return captors.isEmpty ? null : captors.first;
  }

  String get captorName =>
      capturedBy?.name ?? (captors.isEmpty ? null : captors.first.name) ?? '—';

  CapturesReportPerson? get primaryResponsible =>
      responsibleUser ?? (responsibles.isEmpty ? null : responsibles.first);

  String get responsibleName =>
      responsibleUser?.name ??
      (responsibles.isEmpty ? null : responsibles.first.name) ??
      '—';
}

@immutable
class CapturerStat {
  final String capturerId;
  final String capturerName;
  final String capturerEmail;
  final int propertiesCount;

  const CapturerStat({
    required this.capturerId,
    required this.capturerName,
    required this.capturerEmail,
    required this.propertiesCount,
  });
}

@immutable
class CapturesStatistics {
  final int totalProperties;
  final int totalClients;
  final List<CapturerStat> byCapturer;
  final int? propertiesSold;
  final double? propertiesSoldRate;

  const CapturesStatistics({
    this.totalProperties = 0,
    this.totalClients = 0,
    this.byCapturer = const [],
    this.propertiesSold,
    this.propertiesSoldRate,
  });

  factory CapturesStatistics.fromJson(Object? raw) {
    if (raw is! Map) return const CapturesStatistics();
    final conv = raw['conversionRate'];
    final byCap = raw['byCapturer'];
    return CapturesStatistics(
      totalProperties: _i(raw['totalProperties']) ?? 0,
      totalClients: _i(raw['totalClients']) ?? 0,
      byCapturer: [
        if (byCap is List)
          for (final e in byCap)
            if (e is Map && _s(e['capturerId']) != null)
              CapturerStat(
                capturerId: _s(e['capturerId'])!,
                capturerName:
                    _s(e['capturerName']) ?? _s(e['capturerEmail']) ?? '—',
                capturerEmail: _s(e['capturerEmail']) ?? '',
                propertiesCount: _i(e['propertiesCount']) ?? 0,
              ),
      ],
      propertiesSold: conv is Map ? _i(conv['propertiesSold']) : null,
      propertiesSoldRate: conv is Map ? _d(conv['propertiesSoldRate']) : null,
    );
  }
}

@immutable
class CapturesReportResult {
  final int total;
  final List<CapturesReportProperty> properties;
  final CapturesStatistics statistics;

  const CapturesReportResult({
    required this.total,
    required this.properties,
    required this.statistics,
  });

  factory CapturesReportResult.fromJson(Map<String, dynamic> json) {
    final list = json['properties'];
    final props = [
      if (list is List)
        for (final e in list)
          ?CapturesReportProperty.tryParse(e),
    ];
    return CapturesReportResult(
      total: _i(json['total']) ?? props.length,
      properties: props,
      statistics: CapturesStatistics.fromJson(json['statistics']),
    );
  }
}

// ─── Equipes do imóvel ────────────────────────────────────────────────────

const String kNoReportTeamKey = '__sem_equipe__';
const String kOutsideConfiguredTeamKey = '__fora_cadastro__';
const String kNoTeamLabel = 'Sem equipe no cadastro';
const String kOutsideTeamLabel = 'Fora das equipes do cadastro';

/// Equipes configuradas no cadastro de imóveis (`form-settings`).
@immutable
class CapturesTeamContext {
  final Set<String> configuredTeamIds;
  final Map<String, String> teamsMap;

  const CapturesTeamContext(this.configuredTeamIds, this.teamsMap);

  factory CapturesTeamContext.fromTeams(List<PropertyFormTeamOption> teams) {
    final ids = <String>{};
    final names = <String, String>{};
    for (final t in teams) {
      if (t.id.isEmpty) continue;
      ids.add(t.id);
      names[t.id] = t.name.trim().isEmpty ? t.id : t.name.trim();
    }
    return CapturesTeamContext(ids, names);
  }

  static const empty = CapturesTeamContext({}, {});
}

/// Rótulo da coluna "Equipe do imóvel" na lista.
String capturesTableTeamLabel(
  CapturesReportProperty p,
  CapturesTeamContext ctx,
) {
  final id = p.teamId?.trim() ?? '';
  if (id.isEmpty) return kNoTeamLabel;
  if (!ctx.configuredTeamIds.contains(id)) return kOutsideTeamLabel;
  return ctx.teamsMap[id] ?? id;
}

/// Rótulo da equipe na planilha (só equipes configuradas; senão vazio).
String capturesExportTeamLabel(
  CapturesReportProperty p,
  CapturesTeamContext ctx,
) {
  final id = p.teamId?.trim() ?? '';
  if (id.isEmpty || !ctx.configuredTeamIds.contains(id)) return '';
  return ctx.teamsMap[id] ?? '';
}

@immutable
class CapturesRankingItem {
  final String id;
  final String name;
  final String email;
  final int count;

  const CapturesRankingItem({
    required this.id,
    required this.name,
    this.email = '',
    required this.count,
  });
}

/// Ranking de captadores contado a partir dos imóveis carregados.
List<CapturesRankingItem> buildCapturerRanking(
  List<CapturesReportProperty> properties,
) {
  final counts = <String, (String, String, int)>{};
  final order = <String>[];
  for (final p in properties) {
    final primary = p.primaryCaptor;
    final id = (p.capturedById ?? primary?.id ?? '').trim();
    if (id.isEmpty) continue;
    final prev = counts[id];
    if (prev == null) {
      counts[id] = (primary?.name ?? id, primary?.email ?? '', 1);
      order.add(id);
    } else {
      counts[id] = (
        prev.$1 == id ? (primary?.name ?? id) : prev.$1,
        prev.$2.isEmpty ? (primary?.email ?? '') : prev.$2,
        prev.$3 + 1,
      );
    }
  }
  final out = [
    for (final id in order)
      CapturesRankingItem(
        id: id,
        name: counts[id]!.$1,
        email: counts[id]!.$2,
        count: counts[id]!.$3,
      ),
  ];
  // Sort estável: empates mantêm a ordem de aparição.
  final indexed = out.asMap().entries.toList()
    ..sort((a, b) {
      final c = b.value.count.compareTo(a.value.count);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}

/// Ranking por equipe do cadastro do imóvel (inclui "sem equipe" e "fora
/// das equipes" — o card da tela filtra só as configuradas).
List<CapturesRankingItem> buildTeamRanking(
  List<CapturesReportProperty> properties,
  CapturesTeamContext ctx,
) {
  final counts = <String, int>{};
  final order = <String>[];
  for (final p in properties) {
    final id = p.teamId?.trim() ?? '';
    final key = id.isEmpty
        ? kNoReportTeamKey
        : (ctx.configuredTeamIds.contains(id) ? id : kOutsideConfiguredTeamKey);
    if (!counts.containsKey(key)) order.add(key);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  String nameOf(String key) => switch (key) {
        kNoReportTeamKey => kNoTeamLabel,
        kOutsideConfiguredTeamKey => kOutsideTeamLabel,
        _ => ctx.teamsMap[key] ?? key,
      };
  final indexed = order.asMap().entries.toList()
    ..sort((a, b) {
      final c = counts[b.value]!.compareTo(counts[a.value]!);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return [
    for (final e in indexed)
      CapturesRankingItem(id: e.value, name: nameOf(e.value), count: counts[e.value]!),
  ];
}

List<CapturesRankingItem> onlyConfiguredTeams(
  List<CapturesRankingItem> ranking,
  CapturesTeamContext ctx,
) =>
    ranking.where((r) => ctx.configuredTeamIds.contains(r.id)).toList();

/// Busca local da lista (código, título, captador, responsável, equipe).
List<CapturesReportProperty> filterCapturesProperties(
  List<CapturesReportProperty> properties,
  String query,
  CapturesTeamContext ctx,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return properties;
  return properties.where((p) {
    final hay = [
      p.code,
      p.title,
      p.captorName,
      p.responsibleName,
      capturesTableTeamLabel(p, ctx),
    ].whereType<String>().join(' ').toLowerCase();
    return hay.contains(q);
  }).toList();
}

/// Opção de equipe no seletor: um item por NOME (há equipes duplicadas com o
/// mesmo nome); ao filtrar, todos os ids daquele nome vão juntos.
@immutable
class CapturesTeamOption {
  final String id;
  final String name;
  final List<String> allIds;

  const CapturesTeamOption(this.id, this.name, this.allIds);
}

List<CapturesTeamOption> buildCapturesTeamOptions(
  List<PropertyFormTeamOption> teams,
) {
  final byName = <String, List<PropertyFormTeamOption>>{};
  for (final t in teams) {
    if (t.id.isEmpty) continue;
    final key = (t.name.trim().isEmpty ? t.id : t.name.trim()).toLowerCase();
    byName.putIfAbsent(key, () => []).add(t);
  }
  final options = [
    for (final list in byName.values)
      CapturesTeamOption(
        list.first.id,
        list.first.name.trim().isEmpty ? list.first.id : list.first.name.trim(),
        [for (final t in list) t.id],
      ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return options;
}

/// Ids enviados à API para as equipes escolhidas (expande duplicadas).
List<String> expandCapturesTeamIds(
  List<String> selectedIds,
  List<CapturesTeamOption> options,
) {
  final out = <String>{};
  for (final id in selectedIds) {
    final opt = options.where((o) => o.id == id).firstOrNull;
    if (opt == null) {
      out.add(id);
    } else {
      out.addAll(opt.allIds);
    }
  }
  return out.toList();
}

// ─── Auditorias (gestão) ──────────────────────────────────────────────────

@immutable
class ResponsibleChangeItem {
  final String id;
  final DateTime? changedAt;
  final String propertyId;
  final String? propertyCode;
  final String propertyTitle;
  final bool isPrincipal;
  final String previousLabel;
  final String currentLabel;
  final String? changedByName;

  const ResponsibleChangeItem({
    required this.id,
    this.changedAt,
    required this.propertyId,
    this.propertyCode,
    required this.propertyTitle,
    required this.isPrincipal,
    required this.previousLabel,
    required this.currentLabel,
    this.changedByName,
  });

  static ResponsibleChangeItem? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = _s(raw['id']);
    if (id == null) return null;
    String names(Object? list) =>
        list is List ? list.map((e) => '$e').where((e) => e.isNotEmpty).join(', ') : '';
    return ResponsibleChangeItem(
      id: id,
      changedAt: _date(raw['changedAt']),
      propertyId: _s(raw['propertyId']) ?? '',
      propertyCode: _s(raw['propertyCode']),
      propertyTitle: _s(raw['propertyTitle']) ?? 'Imóvel',
      isPrincipal: _s(raw['scope']) != 'additional',
      previousLabel: _s(raw['previousLabel']) ?? names(raw['previousNames']),
      currentLabel: _s(raw['currentLabel']) ?? names(raw['currentNames']),
      changedByName: _s(raw['changedByName']),
    );
  }
}

@immutable
class ResponsibleChangesResult {
  final List<ResponsibleChangeItem> items;
  const ResponsibleChangesResult(this.items);

  factory ResponsibleChangesResult.fromJson(Map<String, dynamic> json) {
    final list = json['items'];
    return ResponsibleChangesResult([
      if (list is List)
        for (final e in list)
          ?ResponsibleChangeItem.tryParse(e),
    ]);
  }
}

@immutable
class ImageDownloadItem {
  final String id;
  final DateTime? downloadedAt;
  final String propertyId;
  final String? propertyCode;
  final String propertyTitle;
  final String? propertyStatus;
  final bool isZip;
  final int count;
  final String? userId;
  final String? userName;

  const ImageDownloadItem({
    required this.id,
    this.downloadedAt,
    required this.propertyId,
    this.propertyCode,
    required this.propertyTitle,
    this.propertyStatus,
    required this.isZip,
    required this.count,
    this.userId,
    this.userName,
  });

  static ImageDownloadItem? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = _s(raw['id']);
    if (id == null) return null;
    return ImageDownloadItem(
      id: id,
      downloadedAt: _date(raw['downloadedAt']),
      propertyId: _s(raw['propertyId']) ?? '',
      propertyCode: _s(raw['propertyCode']),
      propertyTitle: _s(raw['propertyTitle']) ?? 'Imóvel',
      propertyStatus: _s(raw['propertyStatus']),
      isZip: _s(raw['kind']) == 'zip',
      count: _i(raw['count']) ?? 0,
      userId: _s(raw['userId']),
      userName: _s(raw['userName']),
    );
  }
}

@immutable
class ImageDownloadsResult {
  final List<ImageDownloadItem> items;
  final int totalImages;
  const ImageDownloadsResult(this.items, this.totalImages);

  factory ImageDownloadsResult.fromJson(Map<String, dynamic> json) {
    final list = json['items'];
    final items = [
      if (list is List)
        for (final e in list)
          ?ImageDownloadItem.tryParse(e),
    ];
    return ImageDownloadsResult(
      items,
      _i(json['totalImages']) ?? items.fold<int>(0, (s, i) => s + i.count),
    );
  }
}

@immutable
class ImageDownloadsUserSummary {
  final String user;
  final int downloads;
  final int images;
  final DateTime? lastAt;
  const ImageDownloadsUserSummary(
    this.user,
    this.downloads,
    this.images,
    this.lastAt,
  );
}

/// Resumo por usuário (nº de downloads, imagens, último) — maior primeiro.
List<ImageDownloadsUserSummary> summarizeImageDownloads(
  List<ImageDownloadItem> items,
) {
  final map = <String, (String, int, int, DateTime?)>{};
  for (final it in items) {
    final key = it.userId ?? it.userName ?? '—';
    final name = it.userName ?? '(usuário removido)';
    final prev = map[key];
    if (prev == null) {
      map[key] = (name, 1, it.count, it.downloadedAt);
    } else {
      final last = prev.$4 == null ||
              (it.downloadedAt != null && it.downloadedAt!.isAfter(prev.$4!))
          ? it.downloadedAt
          : prev.$4;
      map[key] = (prev.$1, prev.$2 + 1, prev.$3 + it.count, last);
    }
  }
  final out = [
    for (final v in map.values) ImageDownloadsUserSummary(v.$1, v.$2, v.$3, v.$4),
  ]..sort((a, b) => b.images.compareTo(a.images));
  return out;
}

// ─── Exportação (abas iguais às do web) ───────────────────────────────────

@immutable
class CapturesSheet {
  final String name;
  final List<List<Object?>> rows;
  final List<double>? widths;
  const CapturesSheet(this.name, this.rows, [this.widths]);
}

final DateFormat _dateTimeBr = DateFormat('dd/MM/yyyy HH:mm');

String _joinNames(List<CapturesReportPerson> l) =>
    l.map((p) => p.name ?? p.email ?? '').where((s) => s.isNotEmpty).join('; ');
String _joinPhones(List<CapturesReportPerson> l) =>
    l.map((p) => p.phone ?? '').where((s) => s.isNotEmpty).join('; ');
String _joinEmails(List<CapturesReportPerson> l) =>
    l.map((p) => p.email ?? '').where((s) => s.isNotEmpty).join('; ');

/// Planilha do relatório: Resumo, Ranking Captadores, Ranking Equipes
/// (imóvel) e Imóveis — mesmas abas e colunas do `buildCapturesReportWorkbook`.
List<CapturesSheet> buildCapturesWorkbookSheets({
  required List<CapturesReportProperty> properties,
  required CapturesStatistics? statistics,
  required CapturesTeamContext teamContext,
  required CapturesReportQuery query,
  required String teamLabels,
  required String capturerLabels,
  required String responsibleLabels,
  String? publicSiteBase,
}) {
  final byType = <String, int>{};
  final byStatus = <String, int>{};
  for (final p in properties) {
    final t = PropertyType.labelOf(p.type);
    byType[t] = (byType[t] ?? 0) + 1;
    final s = PropertyStatus.labelOf(p.status);
    byStatus[s] = (byStatus[s] ?? 0) + 1;
  }

  final resumo = <List<Object?>>[
    ['Métrica', 'Valor'],
    [
      'Período',
      capturesPeriodLabel(
        allDates: query.allDates,
        from: query.createdFrom,
        to: query.createdTo,
      ),
    ],
    if (query.allDates)
      ['Filtro de data', 'Todo o cadastro (sem recorte)']
    else ...[
      ['Data inicial', capturesYmd(query.createdFrom)],
      ['Data final', capturesYmd(query.createdTo)],
    ],
    ['Equipes do imóvel', teamLabels.trim().isEmpty ? 'Todas' : teamLabels],
    [
      'Corretores / captadores',
      capturerLabels.trim().isEmpty ? 'Todos' : capturerLabels,
    ],
    [
      'Responsáveis',
      responsibleLabels.trim().isEmpty ? 'Todos' : responsibleLabels,
    ],
    ['Total de imóveis captados', properties.length],
    if (statistics?.propertiesSold != null)
      ['Imóveis vendidos/alugados no período', statistics!.propertiesSold],
    if (statistics?.propertiesSoldRate != null)
      ['Taxa conversão imóveis (%)', statistics!.propertiesSoldRate],
    for (final e in (byType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value))))
      ['Tipo: ${e.key}', e.value],
    for (final e in (byStatus.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value))))
      ['Status: ${e.key}', e.value],
  ];

  final capRanking = buildCapturerRanking(properties);
  final capturers = <List<Object?>>[
    ['Captador', 'Email', 'Qtd Imóveis'],
    if (capRanking.isNotEmpty)
      for (final c in capRanking) [c.name, c.email, c.count]
    else
      for (final c in statistics?.byCapturer ?? const <CapturerStat>[])
        [c.capturerName, c.capturerEmail, c.propertiesCount],
  ];

  final teams = <List<Object?>>[
    ['Equipe', 'Qtd Imóveis'],
    for (final t in buildTeamRanking(properties, teamContext)) [t.name, t.count],
  ];

  String fmt(DateTime? d) => d == null ? '' : _dateTimeBr.format(d);
  String siteLink(CapturesReportProperty p) {
    final base = publicSiteBase?.trim() ?? '';
    if (base.isEmpty) return '';
    final ident = (p.code ?? '').isNotEmpty ? p.code! : p.id;
    return '$base/imovel/${Uri.encodeComponent(ident)}';
  }

  final imoveis = <List<Object?>>[
    [
      'Código', 'Código Alternativo', 'Título', 'Status', 'Tipo',
      'Valor Principal', 'Link no Site', 'Endereço', 'Rua', 'Número',
      'Complemento', 'Cidade', 'Estado', 'CEP', 'Bairro', 'Setor',
      'Área Total', 'Área Construída', 'Quartos', 'Suítes', 'Banheiros',
      'Vagas', 'Preço Venda', 'Preço Aluguel', 'Captador (Principal)',
      'Email do Captador', 'Telefone do Captador', 'Captadores (Todos)',
      'Telefones dos Captadores', 'Emails dos Captadores',
      'Responsável (Principal)', 'Email do Responsável',
      'Telefone do Responsável', 'Responsáveis (Todos)',
      'Telefones dos Responsáveis', 'Emails dos Responsáveis',
      'Equipe do imóvel', 'Nome do Proprietário', 'Email do Proprietário',
      'Telefone do Proprietário', 'Data de Criação', 'Última Atualização',
    ],
    for (final p in properties)
      [
        p.code ?? '',
        p.alternativeCode ?? '',
        p.title,
        PropertyStatus.labelOf(p.status),
        PropertyType.labelOf(p.type),
        p.salePrice ?? p.rentPrice ?? p.minSalePrice ?? p.minRentPrice,
        siteLink(p),
        p.address ?? '',
        p.street ?? '',
        p.number ?? '',
        p.complement ?? '',
        p.city ?? '',
        p.state ?? '',
        p.zipCode ?? '',
        p.neighborhood ?? '',
        p.sector ?? '',
        p.totalArea,
        p.builtArea,
        p.bedrooms,
        p.suites,
        p.bathrooms,
        p.parkingSpaces,
        p.salePrice,
        p.rentPrice,
        p.primaryCaptor?.name ?? '',
        p.primaryCaptor?.email ?? '',
        p.primaryCaptor?.phone ?? '',
        _joinNames(p.captors),
        _joinPhones(p.captors),
        _joinEmails(p.captors),
        p.primaryResponsible?.name ?? '',
        p.primaryResponsible?.email ?? '',
        p.primaryResponsible?.phone ?? '',
        _joinNames(p.responsibles),
        _joinPhones(p.responsibles),
        _joinEmails(p.responsibles),
        capturesExportTeamLabel(p, teamContext),
        p.ownerName ?? '',
        p.ownerEmail ?? '',
        p.ownerPhone ?? '',
        fmt(p.createdAt),
        fmt(p.updatedAt),
      ],
  ];

  return [
    CapturesSheet('Resumo', resumo, const [40, 24]),
    CapturesSheet('Ranking Captadores', capturers, const [28, 32, 14]),
    CapturesSheet('Ranking Equipes (imóvel)', teams, const [32, 14]),
    CapturesSheet('Imóveis', imoveis, [
      for (var i = 0; i < imoveis.first.length; i++)
        i == 0 ? 14.0 : (i < 4 ? 22.0 : 18.0),
    ]),
  ];
}

String capturesReportFileName(DateTime now) =>
    'captacoes_imoveis_${DateFormat('yyyyMMdd').format(now)}.xlsx';
