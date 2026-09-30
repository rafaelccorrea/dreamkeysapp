import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../../../shared/services/company_service.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../models/dashboard_overview_model.dart';
import '../widgets/dashboard_filters_drawer.dart'
    show DashboardFilters, DashboardScopeOption;

/// Quem está lendo a Home: papel e dono da conta.
typedef HomeViewer = ({String? role, bool owner});

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

  /// Papéis que recebem a visão executiva — a mesma regra do
  /// `RoleBasedDashboard` do web (admin e master; gestor e corretor seguem
  /// em outras Homes).
  static bool isExecutiveRole(String? role) {
    final r = role?.trim().toLowerCase() ?? '';
    return r == 'admin' || r == 'master';
  }

  /// Claims do access token, sem rede (`sub`, `role`, `owner`). Vazio quando
  /// não há token legível.
  Future<Map<String, dynamic>> _tokenClaims() async {
    try {
      final token = await SecureStorageService.instance.getAccessToken();
      final parts = token?.split('.') ?? const <String>[];
      if (parts.length != 3) return const <String, dynamic>{};
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final json = jsonDecode(payload);
      return json is Map
          ? Map<String, dynamic>.from(json)
          : const <String, dynamic>{};
    } catch (e) {
      debugPrint('[DASHBOARD_OVERVIEW] token: $e');
      return const <String, dynamic>{};
    }
  }

  /// Papel e dono lidos do JWT — o `getOwnerInfoFromToken` do web.
  ///
  /// 29/09/2026 (dash-01): num login novo a Home monta antes de o
  /// `ModuleAccessService` carregar (ele só inicializa no splash ou quando o
  /// drawer abre), então o papel precisa de uma fonte que já exista na hora:
  /// o token. O `owner` também só existe no token (o `/auth/profile` não o
  /// devolve).
  Future<HomeViewer> readViewer() async {
    final claims = await _tokenClaims();
    final role = claims['role']?.toString().trim().toLowerCase() ?? '';
    return (role: role.isEmpty ? null : role, owner: claims['owner'] == true);
  }

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
  /// `IN (id, id)`), e o back só aceita empresas às quais o usuário tem
  /// acesso (`getFilteredCompanyIds`).
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

  /// Chave por usuário + empresa do cabeçalho + recorte (o web guarda por
  /// empresa e compara os filtros): trocar de empresa nunca reaproveita o
  /// dado da anterior, e outra pessoa entrando no mesmo aparelho logo depois
  /// não herda o painel de quem saiu.
  Future<String> _cacheKey(DashboardFilters f) async {
    final companyId = await SecureStorageService.instance.getCompanyId() ?? '';
    final userId = (await _tokenClaims())['sub']?.toString() ?? '';
    return '$userId|$companyId|${buildQuery(f)}';
  }

  /// Dado em cache ainda fresco para este recorte e a hora em que foi
  /// buscado (ou nulo).
  Future<({DateTime at, DashboardOverview data})?> cachedEntry(
    DashboardFilters f,
  ) async {
    final key = await _cacheKey(f);
    final hit = _cache[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _cacheTtl) {
      _cache.remove(key);
      return null;
    }
    return hit;
  }

  /// Descarta o cache deste recorte — o "Atualizar" do web apaga a chave
  /// antes de buscar de novo.
  Future<void> invalidate(DashboardFilters f) async {
    _cache.remove(await _cacheKey(f));
  }

  Future<ApiResponse<DashboardOverview>> getOverview(
    DashboardFilters filters,
  ) async {
    try {
      final query = buildQuery(filters);
      // Chave ANTES da requisição: se a empresa trocar enquanto a resposta
      // viaja, o dado da empresa anterior não pode ser guardado com a chave
      // da nova.
      final key = await _cacheKey(filters);
      final response = await _api.get<dynamic>('$_endpoint?$query');
      if (response.success && response.data is Map) {
        final data = DashboardOverview.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
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

  /// Empresas do usuário para o seletor "Empresa" (`GET /companies`, a mesma
  /// lista do web; só aparece com 2+). Sem repetição e em ordem alfabética.
  /// Falha aqui não bloqueia a tela: o seletor simplesmente some.
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
