import 'package:flutter/foundation.dart';

import '../../core/constants/api_constants.dart';
import '../models/sdr_metrics_models.dart';
import 'api_service.dart';

/// Métricas analíticas do Kanban (`/kanban/analytics/*`) — mesmas rotas do `imobx-front`.
class KanbanAnalyticsService {
  KanbanAnalyticsService._();

  static final KanbanAnalyticsService instance = KanbanAnalyticsService._();

  final ApiService _api = ApiService.instance;

  /// `GET /kanban/analytics/sdr/metrics` — parâmetros espelham query do web.
  Future<ApiResponse<SdrMetricsPayload>> getSdrMetrics({
    List<String>? teamIds,
    String? startDate,
    String? endDate,
    List<String>? campaignIds,
    List<String>? agentIds,
    List<String>? sources,
    String? openColumnId,
    int transferListLimit = 400,
  }) async {
    try {
      final qp = <String, String>{};
      // Backend aceita `teamId` repetido ou valor com vírgulas (`parseSdrQueryList`).
      if (teamIds != null && teamIds.isNotEmpty) {
        final joined =
            teamIds.map((e) => e.trim()).where((e) => e.isNotEmpty).join(',');
        if (joined.isNotEmpty) qp['teamId'] = joined;
      }
      if (startDate != null && startDate.isNotEmpty) {
        qp['startDate'] = startDate;
      }
      if (endDate != null && endDate.isNotEmpty) {
        qp['endDate'] = endDate;
      }
      if (campaignIds != null && campaignIds.isNotEmpty) {
        final joined =
            campaignIds.map((e) => e.trim()).where((e) => e.isNotEmpty).join(',');
        if (joined.isNotEmpty) qp['campaignId'] = joined;
      }
      if (agentIds != null && agentIds.isNotEmpty) {
        final joined =
            agentIds.map((e) => e.trim()).where((e) => e.isNotEmpty).join(',');
        if (joined.isNotEmpty) qp['agentId'] = joined;
      }
      if (sources != null && sources.isNotEmpty) {
        final joined =
            sources.map((e) => e.trim()).where((e) => e.isNotEmpty).join(',');
        if (joined.isNotEmpty) qp['source'] = joined;
      }
      if (openColumnId != null && openColumnId.trim().isNotEmpty) {
        qp['openColumnId'] = openColumnId.trim();
      }
      qp['transferListLimit'] = '${transferListLimit.clamp(0, 5000)}';

      final response = await _api.get<Map<String, dynamic>>(
        ApiConstants.kanbanAnalyticsSdrMetrics,
        queryParameters: qp,
      );

      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: SdrMetricsPayload.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar métricas SDR',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_ANALYTICS] getSdrMetrics: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// `GET /kanban/analytics/tasks/:id/metrics`
  Future<ApiResponse<Map<String, dynamic>>> getTaskMetrics(
    String taskId, {
    String? startDate,
    String? endDate,
  }) async {
    try {
      final qp = <String, String>{};
      if (startDate != null && startDate.isNotEmpty) qp['startDate'] = startDate;
      if (endDate != null && endDate.isNotEmpty) qp['endDate'] = endDate;

      final response = await _api.get<Map<String, dynamic>>(
        ApiConstants.kanbanAnalyticsTaskMetrics(taskId),
        queryParameters: qp.isEmpty ? null : qp,
      );

      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: response.data!,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar métricas da tarefa',
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }
}
