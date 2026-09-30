import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../../../shared/services/company_service.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../models/dashboard_overview_model.dart';
import '../widgets/dashboard_filters_drawer.dart'
    show DashboardFilters, DashboardScopeOption;

/// Visão executiva da Home (admin/master) — `GET /dashboard/overview`.
///
/// 29/09/2026 (dash-01): mesma fonte única do `useDashboard.ts` do web. Todos
/// os blocos da tela saem deste payload, então todos os números da Home vêm
/// do mesmo recorte (período, empresa, corretor e comparação).
///
/// O endpoint mora aqui (e não em `ApiConstants`) porque só este serviço o
/// consome; a fiação central continua intocada.
class DashboardOverviewService {
  DashboardOverviewService._();

  static final DashboardOverviewService instance = DashboardOverviewService._();
  final ApiService _api = ApiService.instance;

  static const String _endpoint = '/dashboard/overview';

  /// Mesmo TTL do cache do web (90 s): voltar para a Home pelo menu não
  /// refaz a consulta inteira se o dado ainda está fresco.
  static const Duration _cacheTtl = Duration(seconds: 90);

  final Map<String, ({DateTime at, DashboardOverview data})> _cache = {};

  /// Query idêntica à do web: `dateRange` sempre; `compareWith` só quando
  /// ligado; `teamMember` quando há corretor; `metric` quando não é `all`;
  /// `startDate`/`endDate` só no período personalizado.
  ///
  /// `companyIds`: o web manda `companyIds[]=<id>`, mas a API roda em Express
  /// 5 com o parser de query "simple" — a chave chega como `companyIds[]`, o
  /// ValidationPipe (whitelist) descarta e o filtro de empresa não faz nada
  /// (o número continua sendo o da empresa do cabeçalho). Aqui a chave vai
  /// SEM colchetes e repetida: é assim que o parser "simple" entrega um
  /// array, que é o que o DTO (`@IsArray`) exige. Uma chave só chegaria como
  /// texto e daria 400. Repetir o mesmo id é inócuo no back (o recorte vira
  /// `IN (id, id)`).
  String buildQuery(DashboardFilters f) {
    final parts = <String>[];
    void add(String key, String value) {
      parts.add(
        '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}',
      );
    }

    final range = (f.dateRange == null || f.dateRange!.isEmpty)
        ? '30d'
        : f.dateRange!;
    add('dateRange', range);
    if (f.isComparing) add('compareWith', f.compareWith!);
    final member = f.teamMember?.trim() ?? '';
    if (member.isNotEmpty) add('teamMember', member);
    final companies =
        f.companyIds.map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
    if (companies.length == 1) {
      add('companyIds', companies.first);
      add('companyIds', companies.first);
    } else {
      for (final c in companies) {
        add('companyIds', c);
      }
    }
    final metric = f.metric ?? 'all';
    if (metric.isNotEmpty && metric != 'all') add('metric', metric);
    if (range == 'custom' &&
        (f.startDate?.isNotEmpty ?? false) &&
        (f.endDate?.isNotEmpty ?? false)) {
      add('startDate', f.startDate!);
      add('endDate', f.endDate!);
    }
    return parts.join('&');
  }

  Future<String> _cacheKey(DashboardFilters f) async {
    final companyId = await SecureStorageService.instance.getCompanyId() ?? '';
    return '$companyId|${buildQuery(f)}';
  }

  /// Dado em cache ainda fresco para este recorte (ou nulo).
  Future<DashboardOverview?> cached(DashboardFilters f) async {
    final key = await _cacheKey(f);
    final hit = _cache[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _cacheTtl) {
      _cache.remove(key);
      return null;
    }
    return hit.data;
  }

  /// Hora em que o dado em cache deste recorte foi buscado.
  Future<DateTime?> cachedAt(DashboardFilters f) async {
    final key = await _cacheKey(f);
    return _cache[key]?.at;
  }

  /// Esquece o cache (troca de empresa, "Atualizar").
  void clearCache() => _cache.clear();

  Future<ApiResponse<DashboardOverview>> getOverview(
    DashboardFilters filters,
  ) async {
    try {
      final query = buildQuery(filters);
      final response = await _api.get<dynamic>('$_endpoint?$query');
      if (response.success && response.data is Map) {
        final data = DashboardOverview.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
        final key = await _cacheKey(filters);
        _cache[key] = (at: DateTime.now(), data: data);
        return ApiResponse.success(data: data, statusCode: response.statusCode);
      }
      if (response.success) {
        return ApiResponse.error(
          message: 'O servidor respondeu sem os dados do dashboard.',
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar o dashboard',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('[DASHBOARD_OVERVIEW] getOverview: $e');
      return ApiResponse.error(
        message: 'Erro ao processar o dashboard: $e',
        statusCode: 0,
      );
    }
  }

  /// Empresas do usuário para o seletor "Empresa" (só aparece com 2+, como
  /// no web). Falha aqui não bloqueia a tela: o seletor simplesmente some.
  Future<List<DashboardScopeOption>> getCompanyOptions() async {
    try {
      final r = await CompanyService.instance.getCompanies();
      if (!r.success || r.data == null) return const [];
      final seen = <String>{};
      final out = <DashboardScopeOption>[];
      for (final c in r.data!) {
        if (c.id.isEmpty || !seen.add(c.id)) continue;
        out.add(
          DashboardScopeOption(
            id: c.id,
            name: c.name.trim().isEmpty ? 'Empresa' : c.name.trim(),
          ),
        );
      }
      out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return out;
    } catch (e) {
      debugPrint('[DASHBOARD_OVERVIEW] empresas: $e');
      return const [];
    }
  }
}
