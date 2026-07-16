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
        ? v.whereType<Map>().map((e) => f(Map<String, dynamic>.from(e))).toList()
        : <T>[];
    return SaleFormsOverview(
      kpis: SaleFormsOverviewKpis.fromJson(m(j['kpis'])),
      kpisCompartilhadas:
          SaleFormsOverviewSharedKpis.fromJson(m(j['kpisCompartilhadas'])),
      deltas: SaleFormsOverviewDeltas.fromJson(m(j['deltas'])),
      porStatus: l(j['porStatus'], SaleFormsOverviewStatusSlice.fromJson),
      timeseries:
          l(j['timeseries'], SaleFormsOverviewTimeseriesPoint.fromJson),
      rankingCorretores:
          l(j['rankingCorretores'], SaleFormsOverviewRankingItem.fromJson),
      rankingEquipes:
          l(j['rankingEquipes'], SaleFormsOverviewRankingItem.fromJson),
      rankingUnidades:
          l(j['rankingUnidades'], SaleFormsOverviewRankingItem.fromJson),
      scopeUi: SaleFormsOverviewScopeUi.fromJson(m(j['scopeUi'])),
    );
  }
}

class SaleFormOverviewService {
  SaleFormOverviewService._();
  static final SaleFormOverviewService instance = SaleFormOverviewService._();

  final ApiService _api = ApiService.instance;

  static const String _base = '/sistema/fichas-venda/painel';

  /// `dateFrom`/`dateTo` em `YYYY-MM-DD`; `granularity` day|week|month|quarter|year.
  Future<ApiResponse<SaleFormsOverview>> getOverview({
    String? dateFrom,
    String? dateTo,
    String? granularity,
    List<String>? status,
  }) async {
    try {
      final qp = <String, String>{};
      if (dateFrom != null && dateFrom.isNotEmpty) qp['dateFrom'] = dateFrom;
      if (dateTo != null && dateTo.isNotEmpty) qp['dateTo'] = dateTo;
      if (granularity != null && granularity.isNotEmpty) {
        qp['granularity'] = granularity;
      }
      if (status != null && status.isNotEmpty) {
        qp['status'] = status.join(',');
      }
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
}
