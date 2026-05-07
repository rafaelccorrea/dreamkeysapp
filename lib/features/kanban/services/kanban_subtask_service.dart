import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/kanban_subtask_models.dart';

/// Cliente REST das **subtarefas (checklist) do Kanban** — paridade direta
/// com `imobx-front/src/services/kanbanSubtasksApi.ts`.
///
/// Todas as rotas vivem sob `/kanban/...` e exigem `Authorization` (Bearer)
/// + `X-Company-ID`, ambos injetados automaticamente pelo `ApiService`.
class KanbanSubtaskService {
  KanbanSubtaskService._();

  static final KanbanSubtaskService instance = KanbanSubtaskService._();
  final ApiService _api = ApiService.instance;

  // ─── Sob o cartão (taskId = id da KanbanTask pai) ─────────────────────

  /// `POST /kanban/tasks/:taskId/subtasks` — cria subtarefa no card.
  ///
  /// Backend exige só `title`. Se `assignedToId` não for enviado, o
  /// responsável é herdado do criador / responsável do cartão pai.
  Future<ApiResponse<KanbanSubTask>> createSubTask(
    String taskId,
    CreateSubTaskDto dto,
  ) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/kanban/tasks/$taskId/subtasks',
        body: dto.toJson(),
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: KanbanSubTask.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar tarefa',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SUBTASK] create $taskId: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /kanban/tasks/:taskId/subtasks` — lista subtarefas do card.
  Future<ApiResponse<List<KanbanSubTask>>> getSubTasks(String taskId) async {
    try {
      final response = await _api.get<dynamic>(
        '/kanban/tasks/$taskId/subtasks',
      );
      if (response.success) {
        final raw = response.data;
        final list = _extractList(raw);
        return ApiResponse.success(
          data: list,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar tarefas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SUBTASK] list $taskId: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PUT /kanban/tasks/:taskId/subtasks/:subTaskId/reorder`.
  Future<ApiResponse<void>> reorderSubTasks(
    String taskId,
    String subTaskId,
    List<String> subTaskIds,
  ) async {
    try {
      final response = await _api.put<dynamic>(
        '/kanban/tasks/$taskId/subtasks/$subTaskId/reorder',
        body: {'subTaskIds': subTaskIds},
      );
      if (response.success) {
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao reordenar tarefas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SUBTASK] reorder: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  // ─── Por subTaskId (rotas globais) ────────────────────────────────────

  /// `GET /kanban/subtasks/list` — listagem global ("minhas tarefas" do CRM).
  Future<ApiResponse<SubTasksListResponse>> getMySubTasks({
    SubTasksListFilters filters = SubTasksListFilters.empty,
  }) async {
    try {
      final response = await _api.get<dynamic>(
        '/kanban/subtasks/list',
        queryParameters: filters.toQueryParams(),
      );
      if (response.success) {
        final raw = response.data;
        if (raw is Map<String, dynamic>) {
          return ApiResponse.success(
            data: SubTasksListResponse.fromJson(raw),
            statusCode: response.statusCode,
          );
        }
        if (raw is Map) {
          return ApiResponse.success(
            data:
                SubTasksListResponse.fromJson(Map<String, dynamic>.from(raw)),
            statusCode: response.statusCode,
          );
        }
        // Quando o backend devolve só array (variante legacy), embrulha.
        if (raw is List) {
          return ApiResponse.success(
            data: SubTasksListResponse(
              data: raw
                  .whereType<Map>()
                  .map((e) =>
                      KanbanSubTask.fromJson(Map<String, dynamic>.from(e)))
                  .toList(),
              total: raw.length,
              page: 1,
              limit: raw.length,
              totalPages: 1,
              stats: SubTasksListStats.zero,
            ),
            statusCode: response.statusCode,
          );
        }
        return ApiResponse.success(
          data: SubTasksListResponse.empty,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar tarefas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SUBTASK] mySubtasks: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /kanban/subtasks/:subTaskId`.
  Future<ApiResponse<KanbanSubTask>> getSubTask(String subTaskId) async {
    return _getOne('/kanban/subtasks/$subTaskId', 'detail');
  }

  /// `PUT /kanban/subtasks/:subTaskId`.
  Future<ApiResponse<KanbanSubTask>> updateSubTask(
    String subTaskId,
    UpdateSubTaskDto dto,
  ) async {
    try {
      final response = await _api.put<Map<String, dynamic>>(
        '/kanban/subtasks/$subTaskId',
        body: dto.toJson(),
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: KanbanSubTask.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar tarefa',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SUBTASK] update $subTaskId: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PATCH /kanban/subtasks/:subTaskId/toggle`.
  Future<ApiResponse<KanbanSubTask>> toggleSubTask(String subTaskId) async {
    try {
      final response = await _api.patch<Map<String, dynamic>>(
        '/kanban/subtasks/$subTaskId/toggle',
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: KanbanSubTask.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao alternar tarefa',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SUBTASK] toggle $subTaskId: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `DELETE /kanban/subtasks/:subTaskId`.
  Future<ApiResponse<void>> deleteSubTask(String subTaskId) async {
    try {
      final response = await _api.delete('/kanban/subtasks/$subTaskId');
      if (response.success) {
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao excluir tarefa',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SUBTASK] delete $subTaskId: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PATCH /kanban/subtasks/:subTaskId/assign` — body `{ userId }`.
  Future<ApiResponse<KanbanSubTask>> assignSubTask(
    String subTaskId,
    String userId,
  ) async {
    try {
      final response = await _api.patch<Map<String, dynamic>>(
        '/kanban/subtasks/$subTaskId/assign',
        body: {'userId': userId},
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: KanbanSubTask.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao atribuir tarefa',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SUBTASK] assign $subTaskId: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PATCH /kanban/subtasks/:subTaskId/unassign`.
  Future<ApiResponse<KanbanSubTask>> unassignSubTask(String subTaskId) async {
    try {
      final response = await _api.patch<Map<String, dynamic>>(
        '/kanban/subtasks/$subTaskId/unassign',
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: KanbanSubTask.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao remover responsável',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SUBTASK] unassign $subTaskId: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────

  Future<ApiResponse<KanbanSubTask>> _getOne(
    String endpoint,
    String tag,
  ) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(endpoint);
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: KanbanSubTask.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar tarefa',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [SUBTASK] $tag: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  List<KanbanSubTask> _extractList(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => KanbanSubTask.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (raw is Map && raw['data'] is List) {
      return (raw['data'] as List)
          .whereType<Map>()
          .map((e) => KanbanSubTask.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }
}
