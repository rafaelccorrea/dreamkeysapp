import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// Painel enxuto de Fichas de Venda — espelha `saleFormsOverviewApi.ts` (web)
/// e o backend `/sistema/fichas-venda/painel`.
///
/// Foco: VGV, VGC, por corretor, por equipe, por período e por status.

double _double(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
}

double? _doubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '.'));
}

int _int(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

class SaleFormsOverviewKpis {
  final int totalGeradas;
  final int finalizadas;
  final int aguardandoAssinatura;
  final int emProcessamento;
  final int canceladas;
  final double vgv;
  final double vgc;
  final double ticketMedio;
  final double taxaConversao;

  const SaleFormsOverviewKpis({
    required this.totalGeradas,
    required this.finalizadas,
    required this.aguardandoAssinatura,
    required this.emProcessamento,
    required this.canceladas,
    required this.vgv,
    required this.vgc,
    required this.ticketMedio,
    required this.taxaConversao,
  });

  factory SaleFormsOverviewKpis.fromJson(Map<String, dynamic> j) =>
      SaleFormsOverviewKpis(
        totalGeradas: _int(j['totalGeradas']),
        finalizadas: _int(j['finalizadas']),
        aguardandoAssinatura: _int(j['aguardandoAssinatura']),
        emProcessamento: _int(j['emProcessamento']),
        canceladas: _int(j['canceladas']),
        vgv: _double(j['vgv']),
        vgc: _double(j['vgc']),
        ticketMedio: _double(j['ticketMedio']),
        taxaConversao: _double(j['taxaConversao']),
      );
}

class SaleFormsOverviewSharedKpis {
  final int total;
  final int finalizadas;
  final double vgv;
  final double vgc;

  const SaleFormsOverviewSharedKpis({
    required this.total,
    required this.finalizadas,
    required this.vgv,
    required this.vgc,
  });

  factory SaleFormsOverviewSharedKpis.fromJson(Map<String, dynamic> j) =>
      SaleFormsOverviewSharedKpis(
        total: _int(j['total']),
        finalizadas: _int(j['finalizadas']),
        vgv: _double(j['vgv']),
        vgc: _double(j['vgc']),
      );
}

/// Deltas percentuais vs. período anterior (null = sem base de comparação).
class SaleFormsOverviewDeltas {
  final double? vgv;
  final double? vgc;
  final double? finalizadas;
  final double? totalGeradas;

  const SaleFormsOverviewDeltas({
    this.vgv,
    this.vgc,
    this.finalizadas,
    this.totalGeradas,
  });

  factory SaleFormsOverviewDeltas.fromJson(Map<String, dynamic> j) =>
      SaleFormsOverviewDeltas(
        vgv: _doubleOrNull(j['vgv']),
        vgc: _doubleOrNull(j['vgc']),
        finalizadas: _doubleOrNull(j['finalizadas']),
        totalGeradas: _doubleOrNull(j['totalGeradas']),
      );
}

class SaleFormsOverviewStatusSlice {
  final String key;
  final String label;
  final int total;

  const SaleFormsOverviewStatusSlice({
    required this.key,
    required this.label,
    required this.total,
  });

  factory SaleFormsOverviewStatusSlice.fromJson(Map<String, dynamic> j) =>
      SaleFormsOverviewStatusSlice(
        key: j['key']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        total: _int(j['total']),
      );
}

class SaleFormsOverviewTimeseriesPoint {
  final String periodo;
  final int total;
  final int finalizadas;
  final double vgv;
  final double vgc;

  const SaleFormsOverviewTimeseriesPoint({
    required this.periodo,
    required this.total,
    required this.finalizadas,
    required this.vgv,
    required this.vgc,
  });

  factory SaleFormsOverviewTimeseriesPoint.fromJson(Map<String, dynamic> j) =>
      SaleFormsOverviewTimeseriesPoint(
        periodo: j['periodo']?.toString() ?? '',
        total: _int(j['total']),
        finalizadas: _int(j['finalizadas']),
        vgv: _double(j['vgv']),
        vgc: _double(j['vgc']),
      );
}

class SaleFormsOverviewRankingItem {
  final String key;
  final String label;
  final String? avatar;
  final int total;
  final int finalizadas;
  final double vgv;
  final double vgc;
  final double taxaConversao;

  const SaleFormsOverviewRankingItem({
    required this.key,
    required this.label,
    this.avatar,
    required this.total,
    required this.finalizadas,
    required this.vgv,
    required this.vgc,
    required this.taxaConversao,
  });

  factory SaleFormsOverviewRankingItem.fromJson(Map<String, dynamic> j) =>
      SaleFormsOverviewRankingItem(
        key: j['key']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        avatar: j['avatar']?.toString(),
        total: _int(j['total']),
        finalizadas: _int(j['finalizadas']),
        vgv: _double(j['vgv']),
        vgc: _double(j['vgc']),
        taxaConversao: _double(j['taxaConversao']),
      );
}

/// O backend decide o que cada papel enxerga (all/unit/team/self).
class SaleFormsOverviewScopeUi {
  final bool showUserFilter;
  final bool showTeamFilter;
  final bool showUnitFilter;
  final bool showBrokerRanking;
  final bool showTeamRanking;
  final bool showUnitSection;
  final String scopeTier;

  const SaleFormsOverviewScopeUi({
    required this.showUserFilter,
    required this.showTeamFilter,
    required this.showUnitFilter,
    required this.showBrokerRanking,
    required this.showTeamRanking,
    required this.showUnitSection,
    required this.scopeTier,
  });

  /// Padrão do web (`DEFAULT_SCOPE_UI`) enquanto o `scope-ui` não chega.
  static const SaleFormsOverviewScopeUi defaults = SaleFormsOverviewScopeUi(
    showUserFilter: true,
    showTeamFilter: true,
    showUnitFilter: true,
    showBrokerRanking: true,
    showTeamRanking: true,
    showUnitSection: true,
    scopeTier: 'all',
  );

  SaleFormsOverviewScopeUi copyWith({
    bool? showUserFilter,
    bool? showTeamFilter,
    bool? showUnitFilter,
    bool? showBrokerRanking,
    bool? showTeamRanking,
    bool? showUnitSection,
  }) => SaleFormsOverviewScopeUi(
    showUserFilter: showUserFilter ?? this.showUserFilter,
    showTeamFilter: showTeamFilter ?? this.showTeamFilter,
    showUnitFilter: showUnitFilter ?? this.showUnitFilter,
    showBrokerRanking: showBrokerRanking ?? this.showBrokerRanking,
    showTeamRanking: showTeamRanking ?? this.showTeamRanking,
    showUnitSection: showUnitSection ?? this.showUnitSection,
    scopeTier: scopeTier,
  );

  factory SaleFormsOverviewScopeUi.fromJson(Map<String, dynamic> j) {
    bool b(dynamic v) => v == true || v?.toString() == 'true';
    return SaleFormsOverviewScopeUi(
      showUserFilter: b(j['showUserFilter']),
      showTeamFilter: b(j['showTeamFilter']),
      showUnitFilter: b(j['showUnitFilter']),
      showBrokerRanking: b(j['showBrokerRanking']),
      showTeamRanking: b(j['showTeamRanking']),
      showUnitSection: b(j['showUnitSection']),
      scopeTier: j['scopeTier']?.toString() ?? 'self',
    );
  }
}

class SaleFormsOverview {
  final SaleFormsOverviewKpis kpis;
  final SaleFormsOverviewSharedKpis kpisCompartilhadas;
  final SaleFormsOverviewDeltas deltas;
  final List<SaleFormsOverviewStatusSlice> porStatus;
  final List<SaleFormsOverviewTimeseriesPoint> timeseries;
  final List<SaleFormsOverviewRankingItem> rankingCorretores;
  final List<SaleFormsOverviewRankingItem> rankingEquipes;
  final List<SaleFormsOverviewRankingItem> rankingUnidades;
  final SaleFormsOverviewScopeUi scopeUi;

  const SaleFormsOverview({
    required this.kpis,
    required this.kpisCompartilhadas,
    required this.deltas,
    required this.porStatus,
    required this.timeseries,
    required this.rankingCorretores,
    required this.rankingEquipes,
    required this.rankingUnidades,
    required this.scopeUi,
  });

  factory SaleFormsOverview.fromJson(Map<String, dynamic> root) {
    final j = root['data'] is Map
        ? Map<String, dynamic>.from(root['data'] as Map)
        : root;
    Map<String, dynamic> m(dynamic v) =>
        v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    List<T> l<T>(dynamic v, T Function(Map<String, dynamic>) f) => v is List
        ? v
              .whereType<Map>()
              .map((e) => f(Map<String, dynamic>.from(e)))
              .toList()
        : <T>[];
    return SaleFormsOverview(
      kpis: SaleFormsOverviewKpis.fromJson(m(j['kpis'])),
      kpisCompartilhadas: SaleFormsOverviewSharedKpis.fromJson(
        m(j['kpisCompartilhadas']),
      ),
      deltas: SaleFormsOverviewDeltas.fromJson(m(j['deltas'])),
      porStatus: l(j['porStatus'], SaleFormsOverviewStatusSlice.fromJson),
      timeseries: l(j['timeseries'], SaleFormsOverviewTimeseriesPoint.fromJson),
      rankingCorretores: l(
        j['rankingCorretores'],
        SaleFormsOverviewRankingItem.fromJson,
      ),
      rankingEquipes: l(
        j['rankingEquipes'],
        SaleFormsOverviewRankingItem.fromJson,
      ),
      rankingUnidades: l(
        j['rankingUnidades'],
        SaleFormsOverviewRankingItem.fromJson,
      ),
      scopeUi: SaleFormsOverviewScopeUi.fromJson(m(j['scopeUi'])),
    );
  }
}

/// Filtros do painel — espelho de `SaleFormsOverviewFilters` /
/// `OverviewFilterState` do web e do `SaleFormsOverviewFiltersDto` do back.
/// Datas em `YYYY-MM-DD` (dia local). Listas vão separadas por vírgula numa
/// chave só (o `toStringArrayQuery` do DTO faz o `split(',')`), igual ao web.
class SaleFormsOverviewFilters {
  final String? dateFrom;
  final String? dateTo;

  /// day | week | month (o back aceita também quarter | year).
  final String granularity;
  final List<String> userIds;
  final List<String> teamIds;
  final List<String> unitIds;

  /// finalized | waiting_for_signature | processing.
  final List<String> status;

  const SaleFormsOverviewFilters({
    this.dateFrom,
    this.dateTo,
    this.granularity = 'day',
    this.userIds = const [],
    this.teamIds = const [],
    this.unitIds = const [],
    this.status = const [],
  });

  /// Quantos recortes além do período (corretor, equipe, unidade, status).
  int get dimensionCount =>
      (userIds.isNotEmpty ? 1 : 0) +
      (teamIds.isNotEmpty ? 1 : 0) +
      (unitIds.isNotEmpty ? 1 : 0) +
      (status.isNotEmpty ? 1 : 0);

  /// Query do `GET /painel` — `buildParams` do web. [limit] = rankings
  /// (o web manda 10).
  Map<String, String> toQuery({int? limit = 10}) {
    final qp = <String, String>{};
    if (dateFrom != null && dateFrom!.isNotEmpty) qp['dateFrom'] = dateFrom!;
    if (dateTo != null && dateTo!.isNotEmpty) qp['dateTo'] = dateTo!;
    if (granularity.isNotEmpty) qp['granularity'] = granularity;
    if (userIds.isNotEmpty) qp['userIds'] = userIds.join(',');
    if (teamIds.isNotEmpty) qp['teamIds'] = teamIds.join(',');
    if (unitIds.isNotEmpty) qp['unitIds'] = unitIds.join(',');
    if (status.isNotEmpty) qp['status'] = status.join(',');
    if (limit != null) qp['limit'] = '$limit';
    return qp;
  }

  /// Mesmo formato que o web grava no `localStorage`.
  Map<String, dynamic> toJson() => {
    'granularity': granularity,
    'dateFrom': dateFrom,
    'dateTo': dateTo,
    'userIds': userIds,
    'teamIds': teamIds,
    'unitIds': unitIds,
    'status': status,
  };

  SaleFormsOverviewFilters copyWith({
    String? dateFrom,
    String? dateTo,
    String? granularity,
    List<String>? userIds,
    List<String>? teamIds,
    List<String>? unitIds,
    List<String>? status,
  }) => SaleFormsOverviewFilters(
    dateFrom: dateFrom ?? this.dateFrom,
    dateTo: dateTo ?? this.dateTo,
    granularity: granularity ?? this.granularity,
    userIds: userIds ?? this.userIds,
    teamIds: teamIds ?? this.teamIds,
    unitIds: unitIds ?? this.unitIds,
    status: status ?? this.status,
  );

  static bool _sameSet(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final sa = [...a]..sort();
    final sb = [...b]..sort();
    for (var i = 0; i < sa.length; i++) {
      if (sa[i] != sb[i]) return false;
    }
    return true;
  }

  /// `panelFiltersEqual` do web (listas comparadas sem ordem).
  @override
  bool operator ==(Object other) =>
      other is SaleFormsOverviewFilters &&
      other.dateFrom == dateFrom &&
      other.dateTo == dateTo &&
      other.granularity == granularity &&
      _sameSet(other.status, status) &&
      _sameSet(other.userIds, userIds) &&
      _sameSet(other.teamIds, teamIds) &&
      _sameSet(other.unitIds, unitIds);

  @override
  int get hashCode => Object.hash(
    dateFrom,
    dateTo,
    granularity,
    Object.hashAllUnordered(status),
    Object.hashAllUnordered(userIds),
    Object.hashAllUnordered(teamIds),
    Object.hashAllUnordered(unitIds),
  );
}

/// Opção dos filtros do painel (`PickOption` do web).
class SaleFormsOverviewPickOption {
  final String id;
  final String label;
  final String? avatar;

  const SaleFormsOverviewPickOption({
    required this.id,
    required this.label,
    this.avatar,
  });
}

class SaleFormOverviewService {
  SaleFormOverviewService._();
  static final SaleFormOverviewService instance = SaleFormOverviewService._();

  final ApiService _api = ApiService.instance;

  static const String _base = '/sistema/fichas-venda/painel';

  static dynamic _unwrap(dynamic raw) =>
      raw is Map && raw['data'] != null && raw['kpis'] == null
      ? raw['data']
      : raw;

  /// `GET /painel` com os filtros do painel (período, corretores, equipes,
  /// unidades e status).
  Future<ApiResponse<SaleFormsOverview>> getOverview(
    SaleFormsOverviewFilters filters, {
    int? limit = 10,
  }) async {
    try {
      final qp = filters.toQuery(limit: limit);
      final res = await _api.get<Map<String, dynamic>>(
        _base,
        queryParameters: qp.isEmpty ? null : qp,
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar o painel de fichas',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: SaleFormsOverview.fromJson(res.data!),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS_PAINEL] getOverview: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// `GET /painel/scope-ui` — o que o papel enxerga antes do 1º overview.
  Future<ApiResponse<SaleFormsOverviewScopeUi>> getScopeUi() async {
    try {
      final res = await _api.get<dynamic>('$_base/scope-ui');
      final body = _unwrap(res.data);
      if (!res.success || body is! Map) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar o escopo do painel',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: SaleFormsOverviewScopeUi.fromJson(
          Map<String, dynamic>.from(body),
        ),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS_PAINEL] getScopeUi: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// `GET /painel/available-users?limit=300` (o web pede 300).
  Future<ApiResponse<List<SaleFormsOverviewPickOption>>> getAvailableUsers({
    int limit = 300,
  }) => _options(
    '$_base/available-users',
    query: {'limit': '$limit'},
    what: 'corretores',
  );

  /// `GET /painel/available-teams`.
  Future<ApiResponse<List<SaleFormsOverviewPickOption>>> getAvailableTeams() =>
      _options('$_base/available-teams', what: 'equipes');

  /// `GET /painel/available-units`.
  Future<ApiResponse<List<SaleFormsOverviewPickOption>>> getAvailableUnits() =>
      _options('$_base/available-units', what: 'unidades');

  Future<ApiResponse<List<SaleFormsOverviewPickOption>>> _options(
    String path, {
    Map<String, String>? query,
    required String what,
  }) async {
    try {
      final res = await _api.get<dynamic>(path, queryParameters: query);
      final body = _unwrap(res.data);
      if (!res.success || body is! List) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar $what',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: parseOverviewPickOptions(body),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS_PAINEL] $path: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }
}

/// `[{id, name, avatar?}]` → opções (sem id = descartada).
List<SaleFormsOverviewPickOption> parseOverviewPickOptions(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map(
        (m) => SaleFormsOverviewPickOption(
          id: m['id']?.toString() ?? '',
          label: (m['name'] ?? m['label'])?.toString().trim() ?? '',
          avatar: m['avatar']?.toString(),
        ),
      )
      .where((o) => o.id.isNotEmpty)
      .toList();
}
