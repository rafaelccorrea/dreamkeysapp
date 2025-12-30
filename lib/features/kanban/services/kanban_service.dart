import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/secure_storage_service.dart';
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
      debugPrint('🔍 [KANBAN_SERVICE] Iniciando busca do quadro Kanban');
      debugPrint('🔍 [KANBAN_SERVICE] Parâmetros recebidos:');
      debugPrint('🔍 [KANBAN_SERVICE] - teamId: $teamId');
      debugPrint('🔍 [KANBAN_SERVICE] - projectId: $projectId');
      debugPrint('🔍 [KANBAN_SERVICE] - projectId é null? ${projectId == null}');
      debugPrint('🔍 [KANBAN_SERVICE] - projectId está vazio? ${projectId?.isEmpty ?? true}');

      final params = <String, String>{};
      if (projectId != null && projectId.isNotEmpty) {
        params['projectId'] = projectId;
        debugPrint('🔍 [KANBAN_SERVICE] ✅ projectId adicionado aos query parameters: $projectId');
      } else {
        debugPrint('🔍 [KANBAN_SERVICE] ⚠️ projectId NÃO será enviado (null ou vazio)');
      }

      final url = ApiConstants.kanbanBoard(teamId);
      final fullUrl = params.isEmpty 
          ? '${ApiConstants.baseApiUrl}$url'
          : '${ApiConstants.baseApiUrl}$url?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
      
      debugPrint('🔍 [KANBAN_SERVICE] URL da requisição: $url');
      debugPrint('🔍 [KANBAN_SERVICE] URL completa: $fullUrl');
      debugPrint('🔍 [KANBAN_SERVICE] Query parameters: ${params.isEmpty ? "nenhum" : params}');
      debugPrint('🔍 [KANBAN_SERVICE] Query parameters (formato string): ${params.isEmpty ? "nenhum" : params.entries.map((e) => '${e.key}=${e.value}').join('&')}');
      debugPrint('🔍 [KANBAN_SERVICE] Fazendo requisição GET...');

      final response = await _apiService.get<Map<String, dynamic>>(
        url,
        queryParameters: params.isEmpty ? null : params,
      );

      debugPrint('🔍 [KANBAN_SERVICE] Resposta recebida:');
      debugPrint('🔍 [KANBAN_SERVICE] - Success: ${response.success}');
      debugPrint('🔍 [KANBAN_SERVICE] - Status Code: ${response.statusCode}');
      debugPrint('🔍 [KANBAN_SERVICE] - Message: ${response.message}');
      debugPrint('🔍 [KANBAN_SERVICE] - Data é null? ${response.data == null}');

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
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao buscar quadro: $e');
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
      debugPrint('🔍 [KANBAN_SERVICE] ========== createTask ==========');
      debugPrint('🔍 [KANBAN_SERVICE] Endpoint: ${ApiConstants.kanbanTasks}');
      debugPrint('🔍 [KANBAN_SERVICE] URL completa: ${ApiConstants.baseApiUrl}${ApiConstants.kanbanTasks}');
      debugPrint('🔍 [KANBAN_SERVICE] DTO recebido:');
      debugPrint('🔍 [KANBAN_SERVICE]   - title: ${dto.title}');
      debugPrint('🔍 [KANBAN_SERVICE]   - description: ${dto.description ?? "null"}');
      debugPrint('🔍 [KANBAN_SERVICE]   - columnId: ${dto.columnId}');
      debugPrint('🔍 [KANBAN_SERVICE]   - priority: ${dto.priority?.name ?? "null"}');
      debugPrint('🔍 [KANBAN_SERVICE]   - assignedToId: ${dto.assignedToId ?? "null"}');
      debugPrint('🔍 [KANBAN_SERVICE]   - dueDate: ${dto.dueDate?.toIso8601String() ?? "null"}');
      debugPrint('🔍 [KANBAN_SERVICE]   - projectId: ${dto.projectId ?? "null"}');
      debugPrint('🔍 [KANBAN_SERVICE]   - tags: ${dto.tags ?? "null"}');
      
      final jsonBody = dto.toJson();
      debugPrint('🔍 [KANBAN_SERVICE] Body JSON: $jsonBody');
      
      // Verificar se projectId está presente no JSON
      if (jsonBody.containsKey('projectId')) {
        debugPrint('🔍 [KANBAN_SERVICE] ⚠️ projectId está presente no JSON: ${jsonBody['projectId']}');
        debugPrint('🔍 [KANBAN_SERVICE] ⚠️ Tipo do projectId: ${jsonBody['projectId'].runtimeType}');
        debugPrint('🔍 [KANBAN_SERVICE] ⚠️ projectId é null? ${jsonBody['projectId'] == null}');
        debugPrint('🔍 [KANBAN_SERVICE] ⚠️ projectId é string vazia? ${jsonBody['projectId'] == ""}');
      } else {
        debugPrint('🔍 [KANBAN_SERVICE] ✅ projectId NÃO está presente no JSON (correto quando null)');
      }
      
      // Serializar para ver o JSON final
      final jsonString = jsonEncode(jsonBody);
      debugPrint('🔍 [KANBAN_SERVICE] JSON serializado: $jsonString');
      debugPrint('🔍 [KANBAN_SERVICE] JSON contém "projectId"? ${jsonString.contains('projectId')}');
      
      debugPrint('🔍 [KANBAN_SERVICE] Fazendo requisição POST...');
      
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.kanbanTasks,
        body: jsonBody,
      );

      debugPrint('🔍 [KANBAN_SERVICE] Resposta recebida:');
      debugPrint('🔍 [KANBAN_SERVICE]   - success: ${response.success}');
      debugPrint('🔍 [KANBAN_SERVICE]   - statusCode: ${response.statusCode}');
      debugPrint('🔍 [KANBAN_SERVICE]   - message: ${response.message}');
      debugPrint('🔍 [KANBAN_SERVICE]   - data é null? ${response.data == null}');
      debugPrint('🔍 [KANBAN_SERVICE]   - error: ${response.error}');
      if (response.data != null) {
        debugPrint('🔍 [KANBAN_SERVICE]   - data completo: ${response.data}');
      }

      if (response.success && response.data != null) {
        try {
          debugPrint('🔍 [KANBAN_SERVICE] Parseando resposta...');
          debugPrint('🔍 [KANBAN_SERVICE] Data recebida: ${response.data}');
          
          final task = KanbanTask.fromJson(response.data!);
          
          debugPrint('🔍 [KANBAN_SERVICE] ✅ Tarefa parseada com sucesso!');
          debugPrint('🔍 [KANBAN_SERVICE]   - ID: ${task.id}');
          debugPrint('🔍 [KANBAN_SERVICE]   - Título: ${task.title}');
          debugPrint('🔍 [KANBAN_SERVICE]   - Coluna: ${task.columnId}');
          debugPrint('🔍 [KANBAN_SERVICE]   - Posição: ${task.position}');
          debugPrint('🔍 [KANBAN_SERVICE]   - Prioridade: ${task.priority?.name ?? "null"}');
          debugPrint('🔍 [KANBAN_SERVICE]   - Responsável: ${task.assignedToId ?? "null"}');
          debugPrint('🔍 [KANBAN_SERVICE]   - Projeto: ${task.projectId ?? "null"}');
          debugPrint('🔍 [KANBAN_SERVICE]   - Tags: ${task.tags ?? "null"}');
          debugPrint('🔍 [KANBAN_SERVICE]   - Prazo: ${task.dueDate?.toIso8601String() ?? "null"}');
          
          return ApiResponse.success(
            data: task,
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

      debugPrint('🔍 [KANBAN_SERVICE] ❌ Erro na resposta: ${response.message}');
      debugPrint('🔍 [KANBAN_SERVICE] Detalhes do erro (response.error): ${response.error}');
      debugPrint('🔍 [KANBAN_SERVICE] Tipo do erro: ${response.error.runtimeType}');
      
      // Tentar extrair mensagens de validação do erro
      if (response.error != null) {
        try {
          if (response.error is Map<String, dynamic>) {
            final errorMap = response.error as Map<String, dynamic>;
            debugPrint('🔍 [KANBAN_SERVICE] ========== ERRO DETALHADO ==========');
            errorMap.forEach((key, value) {
              debugPrint('🔍 [KANBAN_SERVICE]   - $key: $value');
              if (value is List) {
                debugPrint('🔍 [KANBAN_SERVICE]     (Lista com ${value.length} itens)');
                for (var i = 0; i < value.length; i++) {
                  debugPrint('🔍 [KANBAN_SERVICE]       [$i]: ${value[i]}');
                }
              } else if (value is Map) {
                debugPrint('🔍 [KANBAN_SERVICE]     (Map com ${(value as Map).length} chaves)');
                (value as Map).forEach((k, v) {
                  debugPrint('🔍 [KANBAN_SERVICE]       $k: $v');
                });
              }
            });
            
            // Verificar se há mensagens de validação
            if (errorMap.containsKey('errors')) {
              final errors = errorMap['errors'];
              debugPrint('🔍 [KANBAN_SERVICE] Campo "errors" encontrado: $errors');
            }
            if (errorMap.containsKey('message')) {
              final errorMsg = errorMap['message'];
              debugPrint('🔍 [KANBAN_SERVICE] Mensagem de erro: $errorMsg');
            }
            debugPrint('🔍 [KANBAN_SERVICE] ========== FIM ERRO DETALHADO ==========');
          } else if (response.error is String) {
            debugPrint('🔍 [KANBAN_SERVICE] Erro como string: ${response.error}');
          } else {
            debugPrint('🔍 [KANBAN_SERVICE] Erro em formato desconhecido: ${response.error}');
          }
        } catch (e) {
          debugPrint('🔍 [KANBAN_SERVICE] Erro ao processar detalhes: $e');
        }
      }
      
      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar tarefa',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] ========== EXCEÇÃO em createTask ==========');
      debugPrint('❌ [KANBAN_SERVICE] Erro: $e');
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

  /// Cria comentário em uma tarefa com suporte a anexos
  Future<ApiResponse<KanbanTaskComment>> createComment(
    String taskId,
    String message,
    List<File>? files,
  ) async {
    try {
      debugPrint('💬 [KANBAN_SERVICE] Criando comentário na tarefa: $taskId');
      debugPrint('💬 [KANBAN_SERVICE] Mensagem: $message');
      debugPrint('💬 [KANBAN_SERVICE] Anexos: ${files?.length ?? 0}');

      final token = await SecureStorageService.instance.getAccessToken();
      if (token == null || token.isEmpty) {
        return ApiResponse.error(
          message: 'Token de autenticação não encontrado',
          statusCode: 401,
        );
      }

      // Validar mensagem
      if (message.trim().isEmpty) {
        return ApiResponse.error(
          message: 'Mensagem não pode estar vazia',
          statusCode: 400,
        );
      }

      if (message.length > 2000) {
        return ApiResponse.error(
          message: 'Mensagem não pode exceder 2000 caracteres',
          statusCode: 400,
        );
      }

      // Validar anexos (máx. 10)
      if (files != null && files.length > 10) {
        return ApiResponse.error(
          message: 'Máximo de 10 arquivos por comentário',
          statusCode: 400,
        );
      }

      final uri = Uri.parse('${ApiConstants.baseApiUrl}${ApiConstants.kanbanTaskComments(taskId)}');
      final request = http.MultipartRequest('POST', uri);

      // Headers
      request.headers['Authorization'] = 'Bearer $token';

      // Adicionar mensagem
      request.fields['message'] = message;

      // Adicionar arquivos
      if (files != null && files.isNotEmpty) {
        for (var file in files) {
          final fileStream = http.ByteStream(file.openRead());
          final fileLength = await file.length();
          final multipartFile = http.MultipartFile(
            'files',
            fileStream,
            fileLength,
            filename: file.path.split('/').last.split('\\').last,
          );
          request.files.add(multipartFile);
        }
      }

      debugPrint('💬 [KANBAN_SERVICE] Enviando requisição multipart...');
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('💬 [KANBAN_SERVICE] Status: ${response.statusCode}');
      debugPrint('💬 [KANBAN_SERVICE] Body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
          final comment = KanbanTaskComment.fromJson(jsonData);
          debugPrint('💬 [KANBAN_SERVICE] ✅ Comentário criado com sucesso: ${comment.id}');
          return ApiResponse.success(
            data: comment,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [KANBAN_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
          );
        }
      }

      // Tentar parsear erro
      String errorMessage = 'Erro ao criar comentário';
      try {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        errorMessage = errorData['message']?.toString() ?? errorMessage;
      } catch (_) {
        errorMessage = response.body.isNotEmpty ? response.body : errorMessage;
      }

      return ApiResponse.error(
        message: errorMessage,
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

  /// Lista tarefas com filtros
  Future<ApiResponse<List<KanbanTask>>> listTasks({
    String? projectId,
    String? columnId,
    String? assignedToId,
  }) async {
    try {
      final params = <String, String>{};
      if (projectId != null && projectId.isNotEmpty) {
        params['projectId'] = projectId;
      }
      if (columnId != null && columnId.isNotEmpty) {
        params['columnId'] = columnId;
      }
      if (assignedToId != null && assignedToId.isNotEmpty) {
        params['assignedToId'] = assignedToId;
      }

      debugPrint('🔍 [KANBAN_SERVICE] Listando tarefas com filtros: $params');

      final response = await _apiService.get<List<dynamic>>(
        ApiConstants.kanbanTasks,
        queryParameters: params.isEmpty ? null : params,
      );

      if (response.success && response.data != null) {
        try {
          final tasks = (response.data as List)
              .map((e) => KanbanTask.fromJson(e as Map<String, dynamic>))
              .toList();
          return ApiResponse.success(
            data: tasks,
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
        message: response.message ?? 'Erro ao listar tarefas',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao listar tarefas: $e');
      return ApiResponse.error(
        message: 'Erro ao listar tarefas: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Obtém histórico de uma tarefa
  Future<ApiResponse<List<HistoryEntry>>> getTaskHistory(String taskId) async {
    try {
      debugPrint('📜 [KANBAN_SERVICE] Buscando histórico da tarefa: $taskId');
      final response = await _apiService.get<List<dynamic>>(
        ApiConstants.kanbanTaskHistory(taskId),
      );

      if (response.success && response.data != null) {
        try {
          final history = (response.data as List)
              .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
              .toList();
          debugPrint('📜 [KANBAN_SERVICE] ✅ ${history.length} entradas de histórico encontradas');
          return ApiResponse.success(
            data: history,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [KANBAN_SERVICE] Erro ao parsear histórico: $e');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar histórico',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao buscar histórico: $e');
      return ApiResponse.error(
        message: 'Erro ao buscar histórico: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Cria projeto
  Future<ApiResponse<KanbanProject>> createProject(CreateKanbanProjectDto dto) async {
    try {
      debugPrint('🔍 [KANBAN_SERVICE] Criando projeto: ${dto.toJson()}');
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.kanbanProjects,
        body: dto.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          final project = KanbanProject.fromJson(response.data!);
          return ApiResponse.success(
            data: project,
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
        message: response.message ?? 'Erro ao criar projeto',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao criar projeto: $e');
      return ApiResponse.error(
        message: 'Erro ao criar projeto: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista projetos por equipe
  Future<ApiResponse<List<KanbanProject>>> getProjectsByTeam(String teamId) async {
    try {
      debugPrint('🔍 [KANBAN_SERVICE] Listando projetos da equipe: $teamId');
      final response = await _apiService.get<List<dynamic>>(
        ApiConstants.kanbanProjectsByTeam(teamId),
      );

      if (response.success && response.data != null) {
        try {
          final projects = (response.data as List)
              .map((e) => KanbanProject.fromJson(e as Map<String, dynamic>))
              .toList();
          
          debugPrint('🔍 [KANBAN_SERVICE] ✅ ${projects.length} projetos parseados da equipe');
          for (var i = 0; i < projects.length; i++) {
            final p = projects[i];
            debugPrint('🔍 [KANBAN_SERVICE]   [$i] ${p.name} (ID: ${p.id}) - Status: ${p.status.name} - Tarefas: ${p.taskCount}');
          }
          
          return ApiResponse.success(
            data: projects,
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
        message: response.message ?? 'Erro ao listar projetos',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao listar projetos: $e');
      return ApiResponse.error(
        message: 'Erro ao listar projetos: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Obtém workspace pessoal
  Future<ApiResponse<List<KanbanProject>>> getPersonalWorkspace() async {
    try {
      debugPrint('🔍 [KANBAN_SERVICE] ========== getPersonalWorkspace ==========');
      debugPrint('🔍 [KANBAN_SERVICE] Endpoint: ${ApiConstants.kanbanProjectsPersonal}');
      debugPrint('🔍 [KANBAN_SERVICE] URL completa: ${ApiConstants.baseApiUrl}${ApiConstants.kanbanProjectsPersonal}');
      
      final response = await _apiService.get<List<dynamic>>(
        ApiConstants.kanbanProjectsPersonal,
      );
      
      debugPrint('🔍 [KANBAN_SERVICE] Resposta getPersonalWorkspace:');
      debugPrint('🔍 [KANBAN_SERVICE]   - success: ${response.success}');
      debugPrint('🔍 [KANBAN_SERVICE]   - statusCode: ${response.statusCode}');
      debugPrint('🔍 [KANBAN_SERVICE]   - message: ${response.message}');
      debugPrint('🔍 [KANBAN_SERVICE]   - data: ${response.data?.length ?? 0} itens');

      if (response.success && response.data != null) {
        try {
          final projects = (response.data as List)
              .map((e) => KanbanProject.fromJson(e as Map<String, dynamic>))
              .toList();
          
          debugPrint('🔍 [KANBAN_SERVICE] ✅ ${projects.length} projetos parseados');
          for (var i = 0; i < projects.length; i++) {
            final p = projects[i];
            debugPrint('🔍 [KANBAN_SERVICE]   [$i] ${p.name} (${p.id}) - teamId: ${p.teamId} - Status: ${p.status.name}');
          }
          
          return ApiResponse.success(
            data: projects,
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

      debugPrint('🔍 [KANBAN_SERVICE] ❌ Erro na resposta: ${response.message}');
      return ApiResponse.error(
        message: response.message ?? 'Erro ao obter workspace pessoal',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] ========== EXCEÇÃO em getPersonalWorkspace ==========');
      debugPrint('❌ [KANBAN_SERVICE] Erro: $e');
      return ApiResponse.error(
        message: 'Erro ao obter workspace pessoal: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista projetos com filtros
  Future<ApiResponse<Map<String, dynamic>>> getFilteredProjects({
    String? page,
    String? limit,
    String? status,
    String? teamId,
    String? createdById,
    String? startDateFrom,
    String? startDateTo,
    String? dueDateFrom,
    String? dueDateTo,
  }) async {
    try {
      final params = <String, String>{};
      if (page != null) params['page'] = page;
      if (limit != null) params['limit'] = limit;
      if (status != null) params['status'] = status;
      if (teamId != null) params['teamId'] = teamId;
      if (createdById != null) params['createdById'] = createdById;
      if (startDateFrom != null) params['startDateFrom'] = startDateFrom;
      if (startDateTo != null) params['startDateTo'] = startDateTo;
      if (dueDateFrom != null) params['dueDateFrom'] = dueDateFrom;
      if (dueDateTo != null) params['dueDateTo'] = dueDateTo;

      debugPrint('🔍 [KANBAN_SERVICE] Listando projetos filtrados: $params');

      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.kanbanProjectsFiltered,
        queryParameters: params.isEmpty ? null : params,
      );

      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: response.data!,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar projetos filtrados',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao listar projetos filtrados: $e');
      return ApiResponse.error(
        message: 'Erro ao listar projetos filtrados: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Obtém projeto por ID
  Future<ApiResponse<KanbanProject>> getProjectById(String id) async {
    try {
      debugPrint('🔍 [KANBAN_SERVICE] Obtendo projeto: $id');
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.kanbanProjectById(id),
      );

      if (response.success && response.data != null) {
        try {
          final project = KanbanProject.fromJson(response.data!);
          return ApiResponse.success(
            data: project,
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
        message: response.message ?? 'Erro ao obter projeto',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao obter projeto: $e');
      return ApiResponse.error(
        message: 'Erro ao obter projeto: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Atualiza projeto
  Future<ApiResponse<KanbanProject>> updateProject(
    String id,
    UpdateKanbanProjectDto dto,
  ) async {
    try {
      debugPrint('🔍 [KANBAN_SERVICE] Atualizando projeto $id: ${dto.toJson()}');
      final response = await _apiService.put<Map<String, dynamic>>(
        ApiConstants.kanbanProjectById(id),
        body: dto.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          final project = KanbanProject.fromJson(response.data!);
          return ApiResponse.success(
            data: project,
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
        message: response.message ?? 'Erro ao atualizar projeto',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao atualizar projeto: $e');
      return ApiResponse.error(
        message: 'Erro ao atualizar projeto: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Deleta projeto
  Future<ApiResponse<void>> deleteProject(String id) async {
    try {
      debugPrint('🔍 [KANBAN_SERVICE] Deletando projeto: $id');
      final response = await _apiService.delete(
        ApiConstants.kanbanProjectById(id),
      );

      if (response.success) {
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao deletar projeto',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao deletar projeto: $e');
      return ApiResponse.error(
        message: 'Erro ao deletar projeto: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Finaliza projeto
  Future<ApiResponse<KanbanProject>> finalizeProject(String id) async {
    try {
      debugPrint('🔍 [KANBAN_SERVICE] Finalizando projeto: $id');
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.kanbanProjectFinalize(id),
      );

      if (response.success && response.data != null) {
        try {
          final project = KanbanProject.fromJson(response.data!);
          return ApiResponse.success(
            data: project,
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
        message: response.message ?? 'Erro ao finalizar projeto',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao finalizar projeto: $e');
      return ApiResponse.error(
        message: 'Erro ao finalizar projeto: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Obtém histórico de projetos da equipe
  Future<ApiResponse<List<KanbanProject>>> getTeamProjectHistory(String teamId) async {
    try {
      debugPrint('🔍 [KANBAN_SERVICE] Obtendo histórico de projetos da equipe: $teamId');
      final response = await _apiService.get<List<dynamic>>(
        ApiConstants.kanbanProjectsTeamHistory(teamId),
      );

      if (response.success && response.data != null) {
        try {
          final projects = (response.data as List)
              .map((e) => KanbanProject.fromJson(e as Map<String, dynamic>))
              .toList();
          return ApiResponse.success(
            data: projects,
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
        message: response.message ?? 'Erro ao obter histórico de projetos',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao obter histórico de projetos: $e');
      return ApiResponse.error(
        message: 'Erro ao obter histórico de projetos: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Obtém histórico de um projeto
  Future<ApiResponse<List<Map<String, dynamic>>>> getProjectHistory(String id) async {
    try {
      debugPrint('🔍 [KANBAN_SERVICE] Obtendo histórico do projeto: $id');
      final response = await _apiService.get<List<dynamic>>(
        ApiConstants.kanbanProjectHistory(id),
      );

      if (response.success && response.data != null) {
        try {
          final history = (response.data as List)
              .map((e) => e as Map<String, dynamic>)
              .toList();
          return ApiResponse.success(
            data: history,
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
        message: response.message ?? 'Erro ao obter histórico do projeto',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao obter histórico do projeto: $e');
      return ApiResponse.error(
        message: 'Erro ao obter histórico do projeto: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista membros de um projeto
  Future<ApiResponse<List<ProjectMember>>> getProjectMembers(String projectId) async {
    try {
      debugPrint('👥 [KANBAN_SERVICE] ════════════════════════════════════');
      debugPrint('👥 [KANBAN_SERVICE] getProjectMembers - Iniciando');
      debugPrint('👥 [KANBAN_SERVICE] ════════════════════════════════════');
      debugPrint('👥 [KANBAN_SERVICE] Parâmetros:');
      debugPrint('   - projectId: $projectId');
      debugPrint('   - projectId length: ${projectId.length}');
      debugPrint('   - projectId isEmpty: ${projectId.isEmpty}');
      
      final endpoint = ApiConstants.kanbanProjectMembers(projectId);
      debugPrint('👥 [KANBAN_SERVICE] Endpoint: $endpoint');
      debugPrint('👥 [KANBAN_SERVICE] URL completa: ${ApiConstants.baseApiUrl}$endpoint');
      debugPrint('👥 [KANBAN_SERVICE] Fazendo requisição GET...');

      final response = await _apiService.get<List<dynamic>>(
        endpoint,
      );

      debugPrint('👥 [KANBAN_SERVICE] ════════════════════════════════════');
      debugPrint('👥 [KANBAN_SERVICE] Resposta recebida:');
      debugPrint('   - success: ${response.success}');
      debugPrint('   - statusCode: ${response.statusCode}');
      debugPrint('   - message: ${response.message}');
      debugPrint('   - data: ${response.data != null ? "existe (${response.data!.length} itens)" : "null"}');
      debugPrint('👥 [KANBAN_SERVICE] ════════════════════════════════════');

      if (response.success && response.data != null) {
        try {
          debugPrint('👥 [KANBAN_SERVICE] Parseando membros...');
          final members = response.data!
              .map((e) {
                try {
                  return ProjectMember.fromJson(e as Map<String, dynamic>);
                } catch (parseError) {
                  debugPrint('❌ [KANBAN_SERVICE] Erro ao parsear membro: $parseError');
                  debugPrint('   - Dados: $e');
                  rethrow;
                }
              })
              .toList();

          debugPrint('✅ [KANBAN_SERVICE] ${members.length} membros parseados com sucesso');
          for (var i = 0; i < members.length; i++) {
            final member = members[i];
            debugPrint('   [$i] ${member.user.name} (${member.user.id}) - Role: ${member.role}');
          }
          
          return ApiResponse.success(
            data: members,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [KANBAN_SERVICE] Erro ao parsear membros: $e');
          debugPrint('❌ [KANBAN_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta do servidor: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      debugPrint('❌ [KANBAN_SERVICE] Resposta não foi bem-sucedida');
      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar membros do projeto',
        statusCode: response.statusCode,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [KANBAN_SERVICE] ════════════════════════════════════');
      debugPrint('❌ [KANBAN_SERVICE] Exceção ao buscar membros: $e');
      debugPrint('❌ [KANBAN_SERVICE] StackTrace: $stackTrace');
      debugPrint('❌ [KANBAN_SERVICE] ════════════════════════════════════');
      return ApiResponse.error(
        message: 'Erro ao buscar membros do projeto: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}

