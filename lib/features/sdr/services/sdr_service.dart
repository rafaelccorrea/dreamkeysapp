import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/sdr_dashboard_filters.dart';
import '../models/sdr_metrics_model.dart';
import '../models/sdr_settings_model.dart';

/// Serviço do SDR com IA — consome os mesmos endpoints do imobx-front:
///   - `GET  /kanban/analytics/sdr/metrics` (`kanbanMetricsApi.getSdrMetrics`)
///   - `GET  /sdr-settings` / `PUT /sdr-settings` / `POST /sdr-settings/reset`
///     (`sdrSettingsService.ts`)
///   - `GET  /teams` (opções do filtro de equipes)
///
/// Gating (paridade `admin.routes.tsx`): módulo `whatsapp_ai` (strict) +
/// permissão `whatsapp:manage_config`.
class SdrService {
  SdrService._();

  static final SdrService instance = SdrService._();
  final ApiService _api = ApiService.instance;

  // Endpoints privados (a fiação central fica em `ApiConstants`; aqui só o
  // que este serviço consome).
  static const String _sdrMetricsEndpoint = '/kanban/analytics/sdr/metrics';
  static const String _sdrSettingsEndpoint = '/sdr-settings';
  static const String _sdrSettingsResetEndpoint = '/sdr-settings/reset';
  static const String _teamsEndpoint = '/teams';

  /// `GET /kanban/analytics/sdr/metrics` — KPIs completos do pré-atendimento.
  Future<ApiResponse<SdrMetrics>> getMetrics({
    SdrDashboardFilters filters = SdrDashboardFilters.initial,
  }) async {
    try {
      final response = await _api.get<dynamic>(
        _sdrMetricsEndpoint,
        queryParameters: filters.toQueryParams(),
      );
      if (response.success && response.data != null) {
        final raw = response.data;
        final body = raw is Map<String, dynamic>
            ? (raw['data'] is Map<String, dynamic>
                ? raw['data'] as Map<String, dynamic>
                : raw)
            : raw is Map
                ? Map<String, dynamic>.from(raw)
                : null;
        return ApiResponse.success(
          data: body != null ? SdrMetrics.fromJson(body) : SdrMetrics.empty,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar métricas do SDR',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SDR] getMetrics: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

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
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar configurações do SDR',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SDR] getSettings: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
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
      debugPrint('❌ [SDR] updateSettings: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
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
      debugPrint('❌ [SDR] resetSettings: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /teams` — opções do filtro de equipes do dashboard. Falha aqui não
  /// bloqueia a tela: o modal só esconde a seção de equipes.
  Future<ApiResponse<List<SdrTeamOption>>> getTeams() async {
    try {
      final response = await _api.get<dynamic>(_teamsEndpoint);
      if (response.success && response.data != null) {
        final raw = response.data;
        List<dynamic> list = const [];
        if (raw is List) {
          list = raw;
        } else if (raw is Map) {
          final m = Map<String, dynamic>.from(raw);
          final inner = m['data'] ?? m['teams'] ?? m['items'];
          if (inner is List) list = inner;
        }
        final teams = list
            .whereType<Map>()
            .map((e) => SdrTeamOption.fromJson(Map<String, dynamic>.from(e)))
            .where((t) => t.id.isNotEmpty)
            .toList(growable: false);
        return ApiResponse.success(
          data: teams,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar equipes',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SDR] getTeams: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
