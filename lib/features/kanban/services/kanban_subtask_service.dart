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
  final Map<String, _LegacySubTasksCache> _legacyListCache = {};

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
    bool useCache = true,
  }) async {
    final cacheKey = _legacyCacheKey(filters);
    if (useCache) {
      final cached = _legacyListCache[cacheKey];
      if (cached != null) {
        return ApiResponse.success(
          data: _legacyPageFromCache(cached, filters.page, filters.limit),
          statusCode: 200,
        );
      }
    }

    try {
      final response = await _api.get<dynamic>(
        '/kanban/subtasks/list',
        queryParameters: filters.toQueryParams(),
      );
      if (response.success) {
        if (response.data is List) {
          final rawList = response.data as List;
          final cached = _LegacySubTasksCache(
            raw: List<dynamic>.from(rawList),
            stats: _computeStatsFromRawList(rawList),
          );
          _legacyListCache[cacheKey] = cached;
          // Evita crescer indefinidamente.
          if (_legacyListCache.length > 8) {
            _legacyListCache.remove(_legacyListCache.keys.first);
          }
          return ApiResponse.success(
            data: _legacyPageFromCache(cached, filters.page, filters.limit),
            statusCode: response.statusCode,
          );
        }
        return ApiResponse.success(
          data: _parseSubTasksListResponse(response.data),
          statusCode: response.statusCode,
        );
      }

      // Fallback automático para timeout com payload menor.
      final isTimeout = response.statusCode == 0 &&
          (response.message?.toLowerCase().contains('timeout') ?? false);
      if (isTimeout && filters.limit > 10) {
        final fallbackLimit = filters.limit > 20 ? 20 : 10;
        debugPrint(
          '⚠️ [SUBTASK] timeout em /subtasks/list (limit=${filters.limit}), retry com limit=$fallbackLimit',
        );
        final retryResponse = await _api.get<dynamic>(
          '/kanban/subtasks/list',
          queryParameters: filters.copyWith(limit: fallbackLimit).toQueryParams(),
        );
        if (retryResponse.success) {
          if (retryResponse.data is List) {
            final rawList = retryResponse.data as List;
            final cached = _LegacySubTasksCache(
              raw: List<dynamic>.from(rawList),
              stats: _computeStatsFromRawList(rawList),
            );
            _legacyListCache[cacheKey] = cached;
            if (_legacyListCache.length > 8) {
              _legacyListCache.remove(_legacyListCache.keys.first);
            }
            return ApiResponse.success(
              data: _legacyPageFromCache(cached, filters.page, filters.limit),
              statusCode: retryResponse.statusCode,
            );
          }
          return ApiResponse.success(
            data: _parseSubTasksListResponse(retryResponse.data),
            statusCode: retryResponse.statusCode,
          );
        }
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

  String _legacyCacheKey(SubTasksListFilters filters) {
    final qp = Map<String, String>.from(filters.toQueryParams())
      ..remove('page')
      ..remove('limit');
    final keys = qp.keys.toList()..sort();
    return keys.map((k) => '$k=${qp[k]}').join('&');
  }

  SubTasksListResponse _legacyPageFromCache(
    _LegacySubTasksCache cache,
    int page,
    int limit,
  ) {
    final safeLimit = limit <= 0 ? 30 : limit;
    final safePage = page <= 0 ? 1 : page;
    final total = cache.raw.length;
    final totalPages = total == 0 ? 1 : ((total + safeLimit - 1) ~/ safeLimit);
    final clampedPage = safePage > totalPages ? totalPages : safePage;
    final start = (clampedPage - 1) * safeLimit;
    final endExclusive = (start + safeLimit) > total ? total : (start + safeLimit);
    final slice = start >= total ? const <dynamic>[] : cache.raw.sublist(start, endExclusive);
    final data = slice
        .whereType<Map>()
        .map((e) => KanbanSubTask.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return SubTasksListResponse(
      data: data,
      total: total,
      page: clampedPage,
      limit: safeLimit,
      totalPages: totalPages,
      stats: cache.stats,
    );
  }

  SubTasksListStats _computeStatsFromRawList(List rawList) {
    var total = 0;
    var completed = 0;
    var pending = 0;
    var overdue = 0;
    var byKindLigar = 0;
    var byKindTarefa = 0;
    var byKindOther = 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    DateTime? parseDate(dynamic raw) {
      if (raw == null) return null;
      try {
        return DateTime.parse(raw.toString());
      } catch (_) {
        return null;
      }
    }

    for (final item in rawList) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      total++;

      final isCompleted = map['isCompleted'] == true;
      if (isCompleted) {
        completed++;
      } else {
        pending++;
      }

      final taskType = map['taskType']?.toString().toLowerCase().trim() ?? '';
      if (taskType == 'ligar') {
        byKindLigar++;
      } else if (taskType == 'tarefa') {
        byKindTarefa++;
      } else {
        byKindOther++;
      }

      if (!isCompleted) {
        final dueDate = parseDate(map['dueDate']);
        if (dueDate != null) {
          final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
          if (dueDay.isBefore(today)) {
            overdue++;
          } else if (dueDay.isAtSameMomentAs(today)) {
            final dueTime = map['dueTime']?.toString() ?? '';
            if (dueTime.isNotEmpty) {
              final parts = dueTime.split(':');
              if (parts.length == 2) {
                final h = int.tryParse(parts[0]);
                final m = int.tryParse(parts[1]);
                if (h != null && m != null) {
                  final dueDt = DateTime(now.year, now.month, now.day, h, m);
                  if (dueDt.isBefore(now)) overdue++;
                }
              }
            }
          }
        }
      }
    }

    return SubTasksListStats(
      total: total,
      completed: completed,
      pending: pending,
      overdue: overdue,
      byKindLigar: byKindLigar,
      byKindTarefa: byKindTarefa,
      byKindOther: byKindOther,
    );
  }

  SubTasksListResponse _parseSubTasksListResponse(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return SubTasksListResponse.fromJson(raw);
    }
    if (raw is Map) {
      return SubTasksListResponse.fromJson(Map<String, dynamic>.from(raw));
    }
    // Quando o backend devolve só array (variante legacy), embrulha.
    if (raw is List) {
      return SubTasksListResponse(
        data: raw
            .whereType<Map>()
            .map((e) => KanbanSubTask.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        total: raw.length,
        page: 1,
        limit: raw.length,
        totalPages: 1,
        stats: SubTasksListStats.zero,
      );
    }
    return SubTasksListResponse.empty;
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

class _LegacySubTasksCache {
  final List<dynamic> raw;
  final SubTasksListStats stats;
  _LegacySubTasksCache({required this.raw, required this.stats});
}
