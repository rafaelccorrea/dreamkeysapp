import '../../core/constants/api_constants.dart';
import 'api_service.dart';

/// Métricas analíticas do Kanban (`/kanban/analytics/*`) — mesmas rotas do `imobx-front`.
class KanbanAnalyticsService {
  KanbanAnalyticsService._();

  static final KanbanAnalyticsService instance = KanbanAnalyticsService._();

  final ApiService _api = ApiService.instance;

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
