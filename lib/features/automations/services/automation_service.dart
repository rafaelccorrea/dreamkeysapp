import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/automation_models.dart';

/// Serviço das Automações — consome `/automations` (paridade com o
/// `automationApi` do imobx-front). O backend (AutomationsController) protege
/// tudo com JwtAuthGuard + CompanyGuard + ModuleAccessGuard(automations); o
/// `X-Company-ID` vai automático pelo [ApiService].
class AutomationService {
  AutomationService._();

  static final AutomationService instance = AutomationService._();
  final ApiService _api = ApiService.instance;

  // Endpoints (constantes privadas — a fiação central pode promover para
  // ApiConstants depois).
  static const String _automations = '/automations';
  static const String _templates = '/automations/templates';
  static String _createFromTemplate(String templateId) =>
      '/automations/templates/$templateId';
  static String _byId(String id) => '/automations/$id';
  static String _toggle(String id) => '/automations/$id/toggle';
  static String _config(String id) => '/automations/$id/config';
  static String _statistics(String id) => '/automations/$id/statistics';
  static String _executions(String id) => '/automations/$id/executions';
  static String _executionById(String id, String executionId) =>
      '/automations/$id/executions/$executionId';

  List<T> _parseList<T>(
    dynamic raw,
    String nestedKey,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    dynamic list = raw;
    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      list = m[nestedKey] ?? m['data'] ?? const [];
    }
    if (list is! List) return <T>[];
    return list
        .whereType<Map>()
        .map((e) => fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// `GET /automations` — lista de automações da empresa. O backend devolve
  /// array cru; toleramos também `{ automations: [...] }`.
  Future<ApiResponse<List<Automation>>> getAutomations() async {
    try {
      final response = await _api.get<dynamic>(_automations);
      if (response.success) {
        return ApiResponse.success(
          data: _parseList(response.data, 'automations', Automation.fromJson),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar automações',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [AUTOMATION] getAutomations: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /automations/templates` — templates disponíveis para criação.
  Future<ApiResponse<List<AutomationTemplate>>> getTemplates() async {
    try {
      final response = await _api.get<dynamic>(_templates);
      if (response.success) {
        return ApiResponse.success(
          data: _parseList(
              response.data, 'templates', AutomationTemplate.fromJson),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar templates',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [AUTOMATION] getTemplates: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /automations/templates/:templateId` — cria a automação com a
  /// configuração padrão do template (o backend usa o companyId do header).
  Future<ApiResponse<Automation>> createFromTemplate(String templateId) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        _createFromTemplate(templateId),
        body: const <String, dynamic>{},
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: Automation.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar automação',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [AUTOMATION] createFromTemplate: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /automations/:id` — detalhe de uma automação.
  Future<ApiResponse<Automation>> getById(String id) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(_byId(id));
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: Automation.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Automação não encontrada',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [AUTOMATION] getById: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PATCH /automations/:id/toggle` — ativa/desativa.
  Future<ApiResponse<Automation>> toggle(String id, bool isActive) async {
    try {
      final response = await _api.patch<Map<String, dynamic>>(
        _toggle(id),
        body: {'isActive': isActive},
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: Automation.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao alternar automação',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [AUTOMATION] toggle: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PATCH /automations/:id/config` — salva a configuração.
  Future<ApiResponse<Automation>> updateConfig(
    String id,
    AutomationConfig config,
  ) async {
    try {
      final response = await _api.patch<Map<String, dynamic>>(
        _config(id),
        body: {'config': config.toJson()},
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: Automation.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao salvar configurações',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [AUTOMATION] updateConfig: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /automations/:id/statistics` — estatísticas agregadas.
  Future<ApiResponse<AutomationStatistics>> getStatistics(String id) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(_statistics(id));
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: AutomationStatistics.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar estatísticas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [AUTOMATION] getStatistics: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /automations/:id/executions` — histórico paginado.
  Future<ApiResponse<ExecutionPageResult>> getExecutions(
    String id, {
    ExecutionFilters filters = const ExecutionFilters(),
  }) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        _executions(id),
        queryParameters: filters.toQueryParams(),
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: ExecutionPageResult.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar histórico',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [AUTOMATION] getExecutions: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /automations/:id/executions/:executionId` — execução + logs.
  Future<ApiResponse<AutomationExecution>> getExecution(
    String id,
    String executionId,
  ) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        _executionById(id, executionId),
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: AutomationExecution.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Execução não encontrada',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [AUTOMATION] getExecution: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
