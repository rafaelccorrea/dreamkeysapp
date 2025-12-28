import 'package:flutter/foundation.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../models/kanban_models.dart';

/// Serviço para gerenciar Kanban
class KanbanService {
  KanbanService._();

  static final KanbanService instance = KanbanService._();
  final ApiService _apiService = ApiService.instance;

  /// Busca quadro Kanban completo
  Future<ApiResponse<KanbanBoard>> getBoard(
    String teamId, {
    String? projectId,
  }) async {
    try {
      final params = <String, String>{};
      if (projectId != null && projectId.isNotEmpty) {
        params['projectId'] = projectId;
      }

      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.kanbanBoard(teamId),
        queryParameters: params.isEmpty ? null : params,
      );

      if (response.success && response.data != null) {
        try {
          final board = KanbanBoard.fromJson(response.data!);
          return ApiResponse.success(
            data: board,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [KANBAN_SERVICE] Erro ao fazer parse: $e');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar quadro Kanban',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao buscar quadro: $e');
      debugPrint('📚 [KANBAN_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao buscar quadro Kanban: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista colunas
  Future<ApiResponse<List<KanbanColumn>>> listColumns() async {
    try {
      final response = await _apiService.get<List<dynamic>>(
        ApiConstants.kanbanColumns,
      );

      if (response.success && response.data != null) {
        try {
          final columns = (response.data as List)
              .map((e) => KanbanColumn.fromJson(e as Map<String, dynamic>))
              .toList();
          return ApiResponse.success(
            data: columns,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [KANBAN_SERVICE] Erro ao fazer parse: $e');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar colunas',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao listar colunas: $e');
      return ApiResponse.error(
        message: 'Erro ao listar colunas: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Cria coluna
  Future<ApiResponse<KanbanColumn>> createColumn(
    CreateColumnDto dto,
  ) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.kanbanColumns,
        body: dto.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          final column = KanbanColumn.fromJson(response.data!);
          return ApiResponse.success(
            data: column,
            statusCode: response.statusCode,
          );
        } catch (e) {
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar coluna',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao criar coluna: $e');
      return ApiResponse.error(
        message: 'Erro ao criar coluna: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Atualiza coluna
  Future<ApiResponse<KanbanColumn>> updateColumn(
    String id,
    UpdateColumnDto dto,
  ) async {
    try {
      final response = await _apiService.put<Map<String, dynamic>>(
        ApiConstants.kanbanColumnById(id),
        body: dto.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          final column = KanbanColumn.fromJson(response.data!);
          return ApiResponse.success(
            data: column,
            statusCode: response.statusCode,
          );
        } catch (e) {
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar coluna',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao atualizar coluna: $e');
      return ApiResponse.error(
        message: 'Erro ao atualizar coluna: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Deleta coluna
  Future<ApiResponse<void>> deleteColumn(String id) async {
    try {
      final response = await _apiService.delete(
        ApiConstants.kanbanColumnById(id),
      );

      if (response.success) {
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao deletar coluna',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao deletar coluna: $e');
      return ApiResponse.error(
        message: 'Erro ao deletar coluna: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Reordena colunas
  Future<ApiResponse<void>> reorderColumns(
    String teamId,
    List<String> columnIds, {
    String? projectId,
  }) async {
    try {
      final body = <String, dynamic>{
        'columnIds': columnIds,
      };
      if (projectId != null) {
        body['projectId'] = projectId;
      }

      final response = await _apiService.post(
        ApiConstants.kanbanColumnsReorder(teamId),
        body: body,
      );

      if (response.success) {
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao reordenar colunas',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao reordenar colunas: $e');
      return ApiResponse.error(
        message: 'Erro ao reordenar colunas: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Cria tarefa
  Future<ApiResponse<KanbanTask>> createTask(CreateTaskDto dto) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.kanbanTasks,
        body: dto.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          final task = KanbanTask.fromJson(response.data!);
          return ApiResponse.success(
            data: task,
            statusCode: response.statusCode,
          );
        } catch (e) {
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar tarefa',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao criar tarefa: $e');
      return ApiResponse.error(
        message: 'Erro ao criar tarefa: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Atualiza tarefa
  Future<ApiResponse<KanbanTask>> updateTask(
    String id,
    UpdateTaskDto dto,
  ) async {
    try {
      final response = await _apiService.put<Map<String, dynamic>>(
        ApiConstants.kanbanTaskById(id),
        body: dto.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          final task = KanbanTask.fromJson(response.data!);
          return ApiResponse.success(
            data: task,
            statusCode: response.statusCode,
          );
        } catch (e) {
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar tarefa',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao atualizar tarefa: $e');
      return ApiResponse.error(
        message: 'Erro ao atualizar tarefa: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Deleta tarefa
  Future<ApiResponse<void>> deleteTask(String id) async {
    try {
      final response = await _apiService.delete(
        ApiConstants.kanbanTaskById(id),
      );

      if (response.success) {
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao deletar tarefa',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao deletar tarefa: $e');
      return ApiResponse.error(
        message: 'Erro ao deletar tarefa: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Move tarefa
  Future<ApiResponse<void>> moveTask(MoveTaskDto dto) async {
    try {
      final response = await _apiService.post(
        ApiConstants.kanbanTasksMove,
        body: dto.toJson(),
      );

      if (response.success) {
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao mover tarefa',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao mover tarefa: $e');
      return ApiResponse.error(
        message: 'Erro ao mover tarefa: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista tags disponíveis
  Future<ApiResponse<List<String>>> listTags(String teamId) async {
    try {
      final response = await _apiService.get<List<dynamic>>(
        ApiConstants.kanbanTags(teamId),
      );

      if (response.success && response.data != null) {
        try {
          final tags = (response.data as List)
              .map((e) => e.toString())
              .toList();
          return ApiResponse.success(
            data: tags,
            statusCode: response.statusCode,
          );
        } catch (e) {
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar tags',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao listar tags: $e');
      return ApiResponse.error(
        message: 'Erro ao listar tags: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista comentários de uma tarefa
  Future<ApiResponse<List<KanbanTaskComment>>> listComments(String taskId) async {
    try {
      final response = await _apiService.get<List<dynamic>>(
        ApiConstants.kanbanTaskComments(taskId),
      );

      if (response.success && response.data != null) {
        try {
          final comments = (response.data as List)
              .map((e) => KanbanTaskComment.fromJson(e as Map<String, dynamic>))
              .toList();
          return ApiResponse.success(
            data: comments,
            statusCode: response.statusCode,
          );
        } catch (e) {
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar comentários',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao listar comentários: $e');
      return ApiResponse.error(
        message: 'Erro ao listar comentários: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Cria comentário em uma tarefa
  Future<ApiResponse<KanbanTaskComment>> createComment(
    String taskId,
    CreateCommentDto dto,
  ) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.kanbanTaskComments(taskId),
        body: dto.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          final comment = KanbanTaskComment.fromJson(response.data!);
          return ApiResponse.success(
            data: comment,
            statusCode: response.statusCode,
          );
        } catch (e) {
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar comentário',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao criar comentário: $e');
      return ApiResponse.error(
        message: 'Erro ao criar comentário: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Deleta comentário
  Future<ApiResponse<void>> deleteComment(String taskId, String commentId) async {
    try {
      final response = await _apiService.delete(
        ApiConstants.kanbanTaskComment(taskId, commentId),
      );

      if (response.success) {
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao deletar comentário',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao deletar comentário: $e');
      return ApiResponse.error(
        message: 'Erro ao deletar comentário: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}

