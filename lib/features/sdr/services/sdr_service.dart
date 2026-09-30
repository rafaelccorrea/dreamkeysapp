import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../models/sdr_dashboard_filters.dart';
import '../models/sdr_extra_models.dart';
import '../models/sdr_metrics_model.dart';
import '../models/sdr_settings_model.dart';

/// Serviço do Dash SDR — consome os mesmos endpoints do imobx-front:
///   - `GET /kanban/analytics/sdr/metrics` (`kanbanMetricsApi.getSdrMetrics`)
///   - `GET /kanban/analytics/sdr/daily-productivity`
///   - `GET /kanban/analytics/sdr/brokers-stagnation`
///   - `GET /kanban/analytics/sdr/subtask-activity`
///   - `GET /sdr-settings` / `PUT /sdr-settings` / `POST /sdr-settings/reset`
///   - catálogos dos filtros: `/kanban/teams?allActive=true`,
///     `/kanban/projects/teams`, `/integrations/meta-campaign/campaigns/list`,
///     `/system-campaigns`, `/users/company-members/simple`, `/kanban/tags/:teamId`.
///
/// Gating (29/09/2026, sdr-01): paridade com o Drawer web — módulo
/// `kanban_management` + `kanban:view_all_teams`. O console do agente (Zezin)
/// continua exigindo `whatsapp_ai`.
class SdrService {
  SdrService._();

  static final SdrService instance = SdrService._();
  final ApiService _api = ApiService.instance;

  static const String _base = '/kanban/analytics/sdr';
  static const String _sdrSettingsEndpoint = '/sdr-settings';
  static const String _sdrSettingsResetEndpoint = '/sdr-settings/reset';

  /// Timeout da consulta com as listas completas — o web usa 120 s: a
  /// consulta é pesada e 30 s dava falso "sem internet" (sdr-02).
  static const Duration _fullListsTimeout = Duration(seconds: 120);

  String _withQuery(String path, Map<String, List<String>> query) {
    final qs = encodeSdrQuery(query);
    return qs.isEmpty ? path : '$path?$qs';
  }

  Map<String, dynamic>? _unwrap(dynamic raw) {
    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      final inner = m['data'];
      if (inner is Map && !m.containsKey('summary')) {
        return Map<String, dynamic>.from(inner);
      }
      return m;
    }
    return null;
  }

  ApiResponse<T> _fail<T>(ApiResponse<dynamic> r, String fallback) {
    return ApiResponse.error(
      message: r.message ?? fallback,
      statusCode: r.statusCode,
      data: r.error,
    );
  }

  ApiResponse<T> _exception<T>(String where, Object e) {
    debugPrint('[SDR] $where: $e');
    return ApiResponse.error(
      message: 'Erro de conexão: ${e.toString()}',
      statusCode: 0,
    );
  }

  /// `GET /kanban/analytics/sdr/metrics` com `lists=none` — só agregados
  /// (≈140 KB). As listas de leads ficam para o drill-down ([getLeadLists]).
  Future<ApiResponse<SdrMetrics>> getMetrics({
    required SdrDashboardFilters filters,
    SdrQueryContext context = SdrQueryContext.empty,
  }) async {
    try {
      final response = await _api.get<dynamic>(
        _withQuery('$_base/metrics', filters.toQuery(context)),
      );
      if (response.success && response.data != null) {
        final body = _unwrap(response.data);
        return ApiResponse.success(
          data: body != null ? SdrMetrics.fromJson(body) : SdrMetrics.empty,
          statusCode: response.statusCode,
        );
      }
      return _fail(response, 'Erro ao carregar métricas do SDR');
    } catch (e) {
      return _exception('getMetrics', e);
    }
  }

  /// Drill-down (sdr-05): o mesmo recorte com `lists=full`. A resposta passa
  /// de 4 MB em empresa grande, então vai com timeout de 120 s (o do
  /// ApiService é 30 s e cobre o download inteiro) e o JSON é decodificado
  /// fora da thread de UI.
  Future<ApiResponse<SdrLeadLists>> getLeadLists({
    required SdrDashboardFilters filters,
    SdrQueryContext context = SdrQueryContext.empty,
  }) async {
    final endpoint = _withQuery(
      '$_base/metrics',
      filters.toQuery(context, lists: SdrListsMode.full),
    );
    try {
      var result = await _getHeavy(endpoint);
      if (result.statusCode == 401) {
        // Token vencido: o ApiService renova a sessão numa chamada leve e a
        // consulta pesada é refeita uma vez com o token novo.
        await _api.get<dynamic>(_sdrSettingsEndpoint);
        result = await _getHeavy(endpoint);
      }
      if (result.statusCode >= 200 && result.statusCode < 300) {
        final body = _unwrap(result.body);
        return ApiResponse.success(
          data: body != null ? SdrLeadLists.fromJson(body) : SdrLeadLists.empty,
          statusCode: result.statusCode,
        );
      }
      final b = result.body;
      final msg = b is Map && b['message'] != null
          ? b['message'].toString()
          : 'Erro ao carregar a lista de leads';
      return ApiResponse.error(
        message: msg,
        statusCode: result.statusCode,
        data: b,
      );
    } on TimeoutException {
      return ApiResponse.error(
        message:
            'A lista de leads demorou mais de 2 minutos para chegar. Reduza o período ou use filtros e tente de novo.',
        statusCode: 0,
      );
    } catch (e) {
      return _exception('getLeadLists', e);
    }
  }

  Future<({int statusCode, dynamic body})> _getHeavy(String endpoint) async {
    final headers = await _api.buildOutboundHeaders(endpoint: endpoint);
    final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');
    final res =
        await http.get(uri, headers: headers).timeout(_fullListsTimeout);
    dynamic body;
    if (res.body.isNotEmpty) {
      try {
        body = await compute(_decodeJson, res.body);
      } catch (_) {
        body = null;
      }
    }
    return (statusCode: res.statusCode, body: body);
  }

  /// `GET sdr/daily-productivity` — aba Produtividade diária.
  Future<ApiResponse<List<SdrDailyRow>>> getDailyProductivity({
    required SdrDashboardFilters filters,
    SdrQueryContext context = SdrQueryContext.empty,
  }) async {
    try {
      final response = await _api.get<dynamic>(_withQuery(
        '$_base/daily-productivity',
        filters.toQuery(context, lists: null),
      ));
      if (response.success) {
        return ApiResponse.success(
          data: SdrDailyRow.listFrom(response.data),
          statusCode: response.statusCode,
        );
      }
      return _fail(response, 'Erro ao carregar a produtividade diária');
    } catch (e) {
      return _exception('getDailyProductivity', e);
    }
  }

  /// `GET sdr/brokers-stagnation` — aba Por corretor. Recebe TODOS os recortes
  /// do dashboard (`buildBrokerStagnationFilters` do web), sem `openColumnId`.
  Future<ApiResponse<SdrBrokerStagnation>> getBrokersStagnation({
    required SdrDashboardFilters filters,
    SdrQueryContext context = SdrQueryContext.empty,
  }) async {
    try {
      final response = await _api.get<dynamic>(_withQuery(
        '$_base/brokers-stagnation',
        filters.toQuery(context, lists: null, includeOpenColumn: false),
      ));
      if (response.success) {
        final body = _unwrap(response.data);
        return ApiResponse.success(
          data: body != null
              ? SdrBrokerStagnation.fromJson(body)
              : SdrBrokerStagnation.empty,
          statusCode: response.statusCode,
        );
      }
      return _fail(response, 'Erro ao carregar a estagnação por corretor');
    } catch (e) {
      return _exception('getBrokersStagnation', e);
    }
  }

  /// `GET sdr/subtask-activity` — aba Atividades.
  Future<ApiResponse<SdrSubtaskActivity>> getSubtaskActivity({
    required SdrDashboardFilters filters,
    SdrQueryContext context = SdrQueryContext.empty,
  }) async {
    try {
      final response = await _api.get<dynamic>(_withQuery(
        '$_base/subtask-activity',
        filters.toQuery(context, lists: null, includeOpenColumn: false),
      ));
      if (response.success) {
        final body = _unwrap(response.data);
        return ApiResponse.success(
          data: body != null
              ? SdrSubtaskActivity.fromJson(body)
              : SdrSubtaskActivity.empty,
          statusCode: response.statusCode,
        );
      }
      return _fail(response, 'Erro ao carregar as atividades');
    } catch (e) {
      return _exception('getSubtaskActivity', e);
    }
  }

  // ─── Configurações do agente (Zezin) ──────────────────────────────────────

  /// `GET /sdr-settings` — configurações da empresa. Paridade com o web:
  /// 404 (empresa ainda sem registro) devolve os padrões, sem erro.
  Future<ApiResponse<SdrSettings>> getSettings() async {
    try {
      final response =
          await _api.get<Map<String, dynamic>>(_sdrSettingsEndpoint);
      if (response.success && response.data != null) {
        final raw = response.data!;
        final body = raw['data'] is Map<String, dynamic>
            ? raw['data'] as Map<String, dynamic>
            : raw;
        return ApiResponse.success(
          data: SdrSettings.fromJson(body),
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode == 404) {
        return ApiResponse.success(
          data: SdrSettings.defaults(),
          statusCode: 200,
        );
      }
      return _fail(response, 'Erro ao carregar configurações do SDR');
    } catch (e) {
      return _exception('getSettings', e);
    }
  }

  /// `PUT /sdr-settings` — salva o DTO completo. O backend devolve 403 se o
  /// usuário não for líder SDR nem admin/master/manager.
  Future<ApiResponse<SdrSettings>> updateSettings(SdrSettings settings) async {
    try {
      final response = await _api.put<Map<String, dynamic>>(
        _sdrSettingsEndpoint,
        body: settings.toUpdateJson(),
      );
      if (response.success && response.data != null) {
        final raw = response.data!;
        final body = raw['data'] is Map<String, dynamic>
            ? raw['data'] as Map<String, dynamic>
            : raw;
        return ApiResponse.success(
          data: SdrSettings.fromJson(body),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ??
            (response.statusCode == 403
                ? 'Apenas o líder SDR ou administrador pode alterar as configurações do SDR.'
                : 'Erro ao salvar configurações do SDR'),
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      return _exception('updateSettings', e);
    }
  }

  /// `POST /sdr-settings/reset` — restaura os padrões no servidor.
  Future<ApiResponse<SdrSettings>> resetSettings() async {
    try {
      final response =
          await _api.post<Map<String, dynamic>>(_sdrSettingsResetEndpoint);
      if (response.success && response.data != null) {
        final raw = response.data!;
        final body = raw['data'] is Map<String, dynamic>
            ? raw['data'] as Map<String, dynamic>
            : raw;
        return ApiResponse.success(
          data: SdrSettings.fromJson(body),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ??
            (response.statusCode == 403
                ? 'Apenas o líder SDR ou administrador pode resetar as configurações.'
                : 'Erro ao resetar configurações do SDR'),
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      return _exception('resetSettings', e);
    }
  }

  // ─── Catálogos dos filtros ────────────────────────────────────────────────

  List<Map<String, dynamic>> _listOf(dynamic raw, [List<String> keys = const ['data']]) {
    dynamic list = raw;
    if (raw is Map) {
      for (final k in keys) {
        if (raw[k] is List) {
          list = raw[k];
          break;
        }
      }
    }
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  /// `GET /kanban/teams?allActive=true` — equipes do filtro (sdr-09: mesma
  /// fonte do web; antes era `GET /teams`, que lista outro conjunto).
  Future<ApiResponse<List<SdrTeamOption>>> getTeams() async {
    try {
      final response =
          await _api.get<dynamic>('/kanban/teams?allActive=true');
      if (response.success) {
        final seen = <String>{};
        final teams = _listOf(response.data, const ['data', 'teams', 'items'])
            .where((m) => m['isActive'] != false)
            .map(SdrTeamOption.fromJson)
            .where((t) => t.id.isNotEmpty && seen.add(t.id))
            .toList(growable: false);
        return ApiResponse.success(data: teams, statusCode: response.statusCode);
      }
      return _fail(response, 'Erro ao carregar equipes');
    } catch (e) {
      return _exception('getTeams', e);
    }
  }

  /// Funis ativos e não pessoais das equipes (`projectsApi.getProjectsByTeams`;
  /// sem equipe, `getProjectsByCompany`).
  Future<ApiResponse<List<SdrProjectOption>>> getProjects(
      List<String> teamIds) async {
    try {
      final ids = teamIds.where((t) => t.trim().isNotEmpty).toList()..sort();
      final endpoint = ids.isEmpty
          ? '/kanban/projects/company'
          : '/kanban/projects/teams?teamIds=${Uri.encodeQueryComponent(ids.join(','))}';
      final response = await _api.get<dynamic>(endpoint);
      if (response.success) {
        final projects = _listOf(response.data)
            .map(SdrProjectOption.tryParse)
            .whereType<SdrProjectOption>()
            .toList(growable: false);
        return ApiResponse.success(
            data: projects, statusCode: response.statusCode);
      }
      return _fail(response, 'Erro ao carregar funis');
    } catch (e) {
      return _exception('getProjects', e);
    }
  }

  /// Campanhas Meta + campanhas do Sistema (mesmo catálogo do web). Falha de
  /// um lado não derruba o outro (`Promise.allSettled`).
  Future<List<SdrFilterOption>> getCampaignOptions() async {
    final out = <String, SdrFilterOption>{};
    try {
      final meta = await _api
          .get<dynamic>('/integrations/meta-campaign/campaigns/list?all=1');
      if (meta.success) {
        for (final c in _listOf(meta.data)) {
          final id = c['id']?.toString().trim() ?? '';
          if (id.isEmpty) continue;
          out.putIfAbsent(
            id,
            () => SdrFilterOption(
              value: id,
              label: (c['name']?.toString().trim().isNotEmpty ?? false)
                  ? c['name'].toString().trim()
                  : id,
              hint: 'Meta',
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[SDR] campanhas Meta: $e');
    }
    try {
      final sys =
          await _api.get<dynamic>('/system-campaigns?all=1&status=all');
      if (sys.success) {
        for (final c in _listOf(sys.data)) {
          // Campanha do Sistema entra pelo NOME (é o que o card grava).
          final name = c['name']?.toString().trim() ?? '';
          if (name.isEmpty) continue;
          out.putIfAbsent(
            name,
            () => SdrFilterOption(value: name, label: name, hint: 'Sistema'),
          );
        }
      }
    } catch (e) {
      debugPrint('[SDR] campanhas do Sistema: $e');
    }
    return out.values.toList();
  }

  /// Todos os membros da empresa (`/users/company-members/simple`).
  Future<List<SdrFilterOption>> getMemberOptions() async {
    try {
      final r = await _api.get<dynamic>('/users/company-members/simple');
      if (!r.success) return const [];
      return _listOf(r.data)
          .map((m) => SdrFilterOption(
                value: m['id']?.toString() ?? '',
                label: m['name']?.toString().trim().isNotEmpty == true
                    ? m['name'].toString().trim()
                    : (m['email']?.toString() ?? 'Usuário'),
              ))
          .where((o) => o.value.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      debugPrint('[SDR] membros: $e');
      return const [];
    }
  }

  /// Tags do card — únicas por empresa, então qualquer equipe devolve a lista
  /// inteira (`kanbanApi.getTeamTags(firstVisibleTeamId)` do web).
  Future<List<SdrFilterOption>> getTagOptions(String teamId) async {
    if (teamId.isEmpty) return const [];
    try {
      final r = await _api.get<dynamic>('/kanban/tags/$teamId');
      if (!r.success) return const [];
      return _listOf(r.data)
          .where((t) => t['id'] != null && t['name'] != null)
          .map((t) => SdrFilterOption(
                value: t['id'].toString(),
                label: t['name'].toString(),
              ))
          .toList(growable: false);
    } catch (e) {
      debugPrint('[SDR] tags: $e');
      return const [];
    }
  }
}

dynamic _decodeJson(String raw) => jsonDecode(raw);
