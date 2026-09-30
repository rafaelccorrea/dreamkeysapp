import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';

/// Dashboard de Fichas de Proposta (v2) — espelha
/// `imobx-front/src/services/purchaseProposalsDashboardApi.ts` e o backend
/// `/sistema/fichas-proposta/dashboard-v2` (gate `proposal:view_dashboard`;
/// exportações exigem também `proposal:export`).

// ─── Conversores tolerantes ──────────────────────────────────────────────

double _double(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
}

int _int(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.round();
  final s = v.toString();
  return int.tryParse(s) ?? double.tryParse(s)?.round() ?? 0;
}

String _str(dynamic v) => v == null ? '' : v.toString();

String? _strOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) => v is List
    ? v.whereType<Map>().map((e) => f(Map<String, dynamic>.from(e))).toList()
    : <T>[];

/// Alguns proxies embrulham a resposta em `{ data: ... }`; o backend atual
/// devolve o objeto cru. Aceita os dois formatos.
dynamic _unwrap(dynamic raw) {
  if (raw is Map && raw.containsKey('data') && raw['kpis'] == null) {
    return raw['data'];
  }
  return raw;
}

// ─── Filtros ─────────────────────────────────────────────────────────────

class ProposalsDashboardFilters {
  /// `YYYY-MM-DD`.
  final String? dateFrom;
  final String? dateTo;

  /// day | week | month | quarter | year.
  final String? granularity;
  final List<String> excludeUserIds;
  final List<String> excludeTeamIds;

  /// Padrão do web: `true` (só equipes comerciais). Só vai na query quando
  /// `false`, igual ao `buildParams` do web.
  final bool excludeNonCommercialTeams;
  final int? limit;

  const ProposalsDashboardFilters({
    this.dateFrom,
    this.dateTo,
    this.granularity,
    this.excludeUserIds = const [],
    this.excludeTeamIds = const [],
    this.excludeNonCommercialTeams = true,
    this.limit,
  });

  Map<String, String> toQuery() {
    final qp = <String, String>{};
    if (dateFrom != null && dateFrom!.isNotEmpty) qp['dateFrom'] = dateFrom!;
    if (dateTo != null && dateTo!.isNotEmpty) qp['dateTo'] = dateTo!;
    if (granularity != null && granularity!.isNotEmpty) {
      qp['granularity'] = granularity!;
    }
    if (excludeUserIds.isNotEmpty) {
      qp['excludeUserIds'] = excludeUserIds.join(',');
    }
    if (excludeTeamIds.isNotEmpty) {
      qp['excludeTeamIds'] = excludeTeamIds.join(',');
    }
    if (!excludeNonCommercialTeams) qp['excludeNonCommercialTeams'] = 'false';
    if (limit != null) qp['limit'] = '$limit';
    return qp;
  }

  /// Mesmos filtros sem `limit` — o web exporta com o recorte completo.
  ProposalsDashboardFilters withoutLimit() => ProposalsDashboardFilters(
        dateFrom: dateFrom,
        dateTo: dateTo,
        granularity: granularity,
        excludeUserIds: excludeUserIds,
        excludeTeamIds: excludeTeamIds,
        excludeNonCommercialTeams: excludeNonCommercialTeams,
      );
}

// ─── Modelos ─────────────────────────────────────────────────────────────

class ProposalsKpis {
  final int totalGeradas;
  final int finalizadas;
  final int emProcessamento;
  final int canceladas;
  final int excluidas;
  final double valorFinalizado;
  final double valorPendente;
  final double ticketMedio;

  /// Percentual 0–100 (duas casas).
  final double taxaConversao;

  /// Em dias.
  final double tempoMedioPorSignatario;

  /// Em dias.
  final double tempoMedioAtePropostaConcluida;

  /// Percentual 0–100 de propostas com `sale_form_id`.
  final double propPropostasComFicha;

  const ProposalsKpis({
    required this.totalGeradas,
    required this.finalizadas,
    required this.emProcessamento,
    required this.canceladas,
    required this.excluidas,
    required this.valorFinalizado,
    required this.valorPendente,
    required this.ticketMedio,
    required this.taxaConversao,
    required this.tempoMedioPorSignatario,
    required this.tempoMedioAtePropostaConcluida,
    required this.propPropostasComFicha,
  });

  factory ProposalsKpis.fromJson(Map<String, dynamic> j) => ProposalsKpis(
        totalGeradas: _int(j['totalGeradas']),
        finalizadas: _int(j['finalizadas']),
        emProcessamento: _int(j['emProcessamento']),
        canceladas: _int(j['canceladas']),
        excluidas: _int(j['excluidas']),
        valorFinalizado: _double(j['valorFinalizado']),
        valorPendente: _double(j['valorPendente']),
        ticketMedio: _double(j['ticketMedio']),
        taxaConversao: _double(j['taxaConversao']),
        tempoMedioPorSignatario: _double(j['tempoMedioPorSignatario']),
        tempoMedioAtePropostaConcluida:
            _double(j['tempoMedioAtePropostaConcluida']),
        propPropostasComFicha: _double(j['propPropostasComFicha']),
      );
}

class ProposalsTimeseriesPoint {
  /// `YYYY-MM-DD` (início do balde: dia, segunda-feira da semana, dia 1…).
  final String periodo;
  final int total;
  final int finalizadas;
  final int canceladas;
  final double valorFinalizado;

  const ProposalsTimeseriesPoint({
    required this.periodo,
    required this.total,
    required this.finalizadas,
    required this.canceladas,
    required this.valorFinalizado,
  });

  factory ProposalsTimeseriesPoint.fromJson(Map<String, dynamic> j) =>
      ProposalsTimeseriesPoint(
        periodo: _str(j['periodo']),
        total: _int(j['total']),
        finalizadas: _int(j['finalizadas']),
        canceladas: _int(j['canceladas']),
        valorFinalizado: _double(j['valorFinalizado'] ?? j['valor']),
      );
}

class ProposalsRankingItem {
  final String key;
  final String label;
  final String? avatar;
  final int total;
  final int finalizadas;
  final double valor;
  final double taxaConversao;

  const ProposalsRankingItem({
    required this.key,
    required this.label,
    this.avatar,
    required this.total,
    required this.finalizadas,
    required this.valor,
    required this.taxaConversao,
  });

  factory ProposalsRankingItem.fromJson(Map<String, dynamic> j) =>
      ProposalsRankingItem(
        key: _str(j['key']),
        label: _str(j['label']),
        avatar: _strOrNull(j['avatar']),
        total: _int(j['total']),
        finalizadas: _int(j['finalizadas']),
        valor: _double(j['valor']),
        taxaConversao: _double(j['taxaConversao']),
      );
}

class ProposalsSignatureBottleneck {
  final String proposalId;
  final String proposalNumber;
  final String signerName;
  final String? signerEmail;
  final int etapa;
  final double pendingDays;

  const ProposalsSignatureBottleneck({
    required this.proposalId,
    required this.proposalNumber,
    required this.signerName,
    this.signerEmail,
    required this.etapa,
    required this.pendingDays,
  });

  factory ProposalsSignatureBottleneck.fromJson(Map<String, dynamic> j) =>
      ProposalsSignatureBottleneck(
        proposalId: _str(j['proposalId']),
        proposalNumber: _str(j['proposalNumber']),
        signerName: _str(j['signerName']),
        signerEmail: _strOrNull(j['signerEmail']),
        etapa: _int(j['etapa']),
        pendingDays: _double(j['pendingDays']),
      );
}

class ProposalsSignatureStage {
  final int etapa;
  final int signed;
  final int pending;
  final int cancelled;

  const ProposalsSignatureStage({
    required this.etapa,
    required this.signed,
    required this.pending,
    required this.cancelled,
  });

  int get total => signed + pending + cancelled;

  factory ProposalsSignatureStage.fromJson(Map<String, dynamic> j) =>
      ProposalsSignatureStage(
        etapa: _int(j['etapa']),
        signed: _int(j['signed']),
        pending: _int(j['pending']),
        cancelled: _int(j['cancelled']),
      );
}

class ProposalsSignatures {
  final double tempoMedioPorSignatario;
  final double tempoMedioAtePropostaConcluida;
  final int totalAssinadas;
  final int totalPendentes;
  final int totalCanceladas;
  final List<ProposalsSignatureStage> porEtapa;
  final List<ProposalsSignatureBottleneck> gargalos;

  const ProposalsSignatures({
    required this.tempoMedioPorSignatario,
    required this.tempoMedioAtePropostaConcluida,
    required this.totalAssinadas,
    required this.totalPendentes,
    required this.totalCanceladas,
    required this.porEtapa,
    required this.gargalos,
  });

  factory ProposalsSignatures.fromJson(Map<String, dynamic> j) =>
      ProposalsSignatures(
        tempoMedioPorSignatario: _double(j['tempoMedioPorSignatario']),
        tempoMedioAtePropostaConcluida:
            _double(j['tempoMedioAtePropostaConcluida']),
        totalAssinadas: _int(j['totalAssinadas']),
        totalPendentes: _int(j['totalPendentes']),
        totalCanceladas: _int(j['totalCanceladas']),
        porEtapa: _list(j['porEtapa'], ProposalsSignatureStage.fromJson),
        gargalos: _list(j['gargalos'], ProposalsSignatureBottleneck.fromJson),
      );
}

class ProposalsFunnel {
  final int processing;
  final int finalized;
  final int canceled;
  final int excluida;
  final int etapa1Concluida;
  final int etapa2Concluida;
  final int etapa3Concluida;

  const ProposalsFunnel({
    required this.processing,
    required this.finalized,
    required this.canceled,
    required this.excluida,
    required this.etapa1Concluida,
    required this.etapa2Concluida,
    required this.etapa3Concluida,
  });

  factory ProposalsFunnel.fromJson(Map<String, dynamic> j) => ProposalsFunnel(
        processing: _int(j['processing']),
        finalized: _int(j['finalized']),
        canceled: _int(j['canceled']),
        excluida: _int(j['excluida']),
        etapa1Concluida: _int(j['etapa1Concluida']),
        etapa2Concluida: _int(j['etapa2Concluida']),
        etapa3Concluida: _int(j['etapa3Concluida']),
      );
}

class ProposalsCounterStats {
  final int total;
  final int pendente;
  final int aprovada;
  final int recusada;

  const ProposalsCounterStats({
    required this.total,
    required this.pendente,
    required this.aprovada,
    required this.recusada,
  });

  factory ProposalsCounterStats.fromJson(Map<String, dynamic> j) =>
      ProposalsCounterStats(
        total: _int(j['total']),
        pendente: _int(j['pendente']),
        aprovada: _int(j['aprovada']),
        recusada: _int(j['recusada']),
      );
}

class ProposalsScoreItem {
  final String proposalId;
  final String proposalNumber;
  final String proponentName;
  final double proposedPrice;
  final int ageDays;

  /// 0–100.
  final int score;
  final int etapaAtual;
  final int assinaturasConcluidas;

  const ProposalsScoreItem({
    required this.proposalId,
    required this.proposalNumber,
    required this.proponentName,
    required this.proposedPrice,
    required this.ageDays,
    required this.score,
    required this.etapaAtual,
    required this.assinaturasConcluidas,
  });

  factory ProposalsScoreItem.fromJson(Map<String, dynamic> j) =>
      ProposalsScoreItem(
        proposalId: _str(j['proposalId']),
        proposalNumber: _str(j['proposalNumber']),
        proponentName: _str(j['proponentName']),
        proposedPrice: _double(j['proposedPrice']),
        ageDays: _int(j['ageDays']),
        score: _int(j['score']).clamp(0, 100).toInt(),
        etapaAtual: _int(j['etapaAtual']),
        assinaturasConcluidas: _int(j['assinaturasConcluidas']),
      );
}

class ProposalsDashboardData {
  final ProposalsKpis kpis;
  final List<ProposalsTimeseriesPoint> timeseries;
  final List<ProposalsRankingItem> rankingCorretores;
  final List<ProposalsRankingItem> rankingEquipes;
  final List<ProposalsRankingItem> rankingImobiliarias;
  final List<ProposalsRankingItem> rankingRegioes;
  final List<ProposalsRankingItem> rankingEmpreendimentos;
  final List<ProposalsRankingItem> rankingMidias;
  final ProposalsSignatures signatures;
  final ProposalsFunnel funnel;
  final ProposalsCounterStats counterProposals;
  final List<ProposalsScoreItem> scoreFechamento;

  const ProposalsDashboardData({
    required this.kpis,
    required this.timeseries,
    required this.rankingCorretores,
    required this.rankingEquipes,
    required this.rankingImobiliarias,
    required this.rankingRegioes,
    required this.rankingEmpreendimentos,
    required this.rankingMidias,
    required this.signatures,
    required this.funnel,
    required this.counterProposals,
    required this.scoreFechamento,
  });

  factory ProposalsDashboardData.fromJson(Map<String, dynamic> j) =>
      ProposalsDashboardData(
        kpis: ProposalsKpis.fromJson(_map(j['kpis'])),
        timeseries: _list(j['timeseries'], ProposalsTimeseriesPoint.fromJson),
        rankingCorretores:
            _list(j['rankingCorretores'], ProposalsRankingItem.fromJson),
        rankingEquipes:
            _list(j['rankingEquipes'], ProposalsRankingItem.fromJson),
        rankingImobiliarias:
            _list(j['rankingImobiliarias'], ProposalsRankingItem.fromJson),
        rankingRegioes:
            _list(j['rankingRegioes'], ProposalsRankingItem.fromJson),
        rankingEmpreendimentos:
            _list(j['rankingEmpreendimentos'], ProposalsRankingItem.fromJson),
        rankingMidias: _list(j['rankingMidias'], ProposalsRankingItem.fromJson),
        signatures: ProposalsSignatures.fromJson(_map(j['signatures'])),
        funnel: ProposalsFunnel.fromJson(_map(j['funnel'])),
        counterProposals:
            ProposalsCounterStats.fromJson(_map(j['counterProposals'])),
        scoreFechamento:
            _list(j['scoreFechamento'], ProposalsScoreItem.fromJson),
      );

  ProposalsDashboardData withTimeseries(List<ProposalsTimeseriesPoint> ts) =>
      ProposalsDashboardData(
        kpis: kpis,
        timeseries: ts,
        rankingCorretores: rankingCorretores,
        rankingEquipes: rankingEquipes,
        rankingImobiliarias: rankingImobiliarias,
        rankingRegioes: rankingRegioes,
        rankingEmpreendimentos: rankingEmpreendimentos,
        rankingMidias: rankingMidias,
        signatures: signatures,
        funnel: funnel,
        counterProposals: counterProposals,
        scoreFechamento: scoreFechamento,
      );
}

/// Opção de corretor/equipe para os filtros avançados.
class ProposalsPickOption {
  final String id;
  final String label;
  final String? avatar;

  const ProposalsPickOption({
    required this.id,
    required this.label,
    this.avatar,
  });
}

/// Escopo de unidades de venda do usuário (`/sistema/sale-units/me`).
/// `allowed == null` → enxerga todas as unidades.
class ProposalsUnitScope {
  final List<String>? allowed;
  final List<String> resolvedLabels;

  const ProposalsUnitScope({this.allowed, this.resolvedLabels = const []});

  bool get isRestricted => allowed != null && allowed!.isNotEmpty;
}

/// Arquivo exportado (bytes crus + extensão).
class ProposalsExportFile {
  final Uint8List bytes;
  final String extension;
  final String fileName;

  const ProposalsExportFile({
    required this.bytes,
    required this.extension,
    required this.fileName,
  });
}

// ─── Service ─────────────────────────────────────────────────────────────

class ProposalsDashboardService {
  ProposalsDashboardService._();
  static final ProposalsDashboardService instance =
      ProposalsDashboardService._();

  final ApiService _api = ApiService.instance;

  static const String _base = '/sistema/fichas-proposta/dashboard-v2';
  static const String _timeseries = '$_base/timeseries';
  static const String _availableTeams = '$_base/available-teams';
  static const String _availableUsers = '$_base/available-users';
  static const String _exportExcel = '$_base/export/excel';
  static const String _exportPdf = '$_base/export/pdf';
  static const String _saleUnitsMe = '/sistema/sale-units/me';

  /// Payload completo (KPIs, série, rankings, assinaturas, funil,
  /// contrapropostas e score). Se a série vier vazia, busca `/timeseries`
  /// à parte — mesmo fallback do web.
  Future<ApiResponse<ProposalsDashboardData>> getDashboard(
    ProposalsDashboardFilters filters,
  ) async {
    try {
      final qp = filters.toQuery();
      final res = await _api.get<dynamic>(
        _base,
        queryParameters: qp.isEmpty ? null : qp,
      );
      final body = _unwrap(res.data);
      if (!res.success || body is! Map) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar o dashboard de propostas',
          statusCode: res.statusCode,
        );
      }
      var data = ProposalsDashboardData.fromJson(
        Map<String, dynamic>.from(body),
      );
      if (data.timeseries.isEmpty) {
        final ts = await getTimeseries(filters);
        if (ts.success && ts.data != null && ts.data!.isNotEmpty) {
          data = data.withTimeseries(ts.data!);
        }
      }
      return ApiResponse.success(data: data, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('[PROPOSALS_DASHBOARD] getDashboard: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<List<ProposalsTimeseriesPoint>>> getTimeseries(
    ProposalsDashboardFilters filters,
  ) async {
    try {
      final qp = filters.toQuery();
      final res = await _api.get<dynamic>(
        _timeseries,
        queryParameters: qp.isEmpty ? null : qp,
      );
      final body = _unwrap(res.data);
      if (!res.success || body is! List) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar a série temporal',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: _list(body, ProposalsTimeseriesPoint.fromJson),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('[PROPOSALS_DASHBOARD] getTimeseries: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<List<ProposalsPickOption>>> getAvailableTeams() async {
    try {
      final res = await _api.get<dynamic>(_availableTeams);
      final body = _unwrap(res.data);
      if (!res.success || body is! List) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar equipes',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: _list(
          body,
          (m) => ProposalsPickOption(id: _str(m['id']), label: _str(m['name'])),
        ).where((o) => o.id.isNotEmpty).toList(),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('[PROPOSALS_DASHBOARD] getAvailableTeams: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<List<ProposalsPickOption>>> getAvailableUsers({
    int limit = 200,
  }) async {
    try {
      final res = await _api.get<dynamic>(
        _availableUsers,
        queryParameters: {'limit': '$limit'},
      );
      final body = _unwrap(res.data);
      if (!res.success || body is! List) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar corretores',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: _list(
          body,
          (m) => ProposalsPickOption(
            id: _str(m['id']),
            label: _str(m['name']),
            avatar: _strOrNull(m['avatar']),
          ),
        ).where((o) => o.id.isNotEmpty).toList(),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('[PROPOSALS_DASHBOARD] getAvailableUsers: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<ProposalsUnitScope>> getMyUnitScope() async {
    try {
      final res = await _api.get<dynamic>(_saleUnitsMe);
      final body = _unwrap(res.data);
      if (!res.success || body is! Map) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar o escopo de unidades',
          statusCode: res.statusCode,
        );
      }
      final allowedRaw = body['allowed'];
      final allowed = allowedRaw is List
          ? allowedRaw.map((e) => e.toString()).toList()
          : null;
      final resolved = body['resolved'] is List
          ? (body['resolved'] as List)
              .whereType<Map>()
              .map((m) => _str(m['label']).trim())
              .where((s) => s.isNotEmpty)
              .toList()
          : <String>[];
      return ApiResponse.success(
        data: ProposalsUnitScope(allowed: allowed, resolvedLabels: resolved),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('[PROPOSALS_DASHBOARD] getMyUnitScope: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Excel gerado no servidor (mesmo arquivo do web).
  Future<ApiResponse<ProposalsExportFile>> exportExcel(
    ProposalsDashboardFilters filters,
  ) =>
      _download(
        _exportExcel,
        filters,
        extension: 'xlsx',
        accept:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );

  /// PDF gerado no servidor (mesmo arquivo do web).
  Future<ApiResponse<ProposalsExportFile>> exportPdf(
    ProposalsDashboardFilters filters,
  ) =>
      _download(
        _exportPdf,
        filters,
        extension: 'pdf',
        accept: 'application/pdf',
      );

  Future<ApiResponse<ProposalsExportFile>> _download(
    String endpoint,
    ProposalsDashboardFilters filters, {
    required String extension,
    required String accept,
  }) async {
    try {
      final qp = filters.toQuery();
      final base = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');
      final uri = qp.isEmpty ? base : base.replace(queryParameters: qp);

      final headers = await _api.buildOutboundHeaders(
        endpoint: endpoint,
        excludeContentType: true,
      );
      headers.remove('Content-Type');
      headers['Accept'] = accept;

      // Exportação monta o relatório inteiro no servidor: teto maior que o
      // de uma leitura comum.
      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 90));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final today = DateTime.now().toIso8601String().substring(0, 10);
        return ApiResponse.success(
          data: ProposalsExportFile(
            bytes: res.bodyBytes,
            extension: extension,
            fileName: 'dashboard-fichas-proposta-$today.$extension',
          ),
          statusCode: res.statusCode,
        );
      }
      String message;
      try {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map && body['message'] != null) {
          final m = body['message'];
          message = m is List ? m.join(' ') : m.toString();
        } else {
          message = 'Erro ao exportar (${res.statusCode})';
        }
      } catch (_) {
        message = 'Erro ao exportar (${res.statusCode})';
      }
      return ApiResponse.error(message: message, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('[PROPOSALS_DASHBOARD] export $extension: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }
}
