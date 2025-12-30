import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../models/chat_models.dart';

/// Serviço para gerenciar chat via API REST
class ChatApiService {
  ChatApiService._();

  static final ChatApiService instance = ChatApiService._();
  final ApiService _apiService = ApiService.instance;

  /// Criar ou obter uma sala
  Future<ApiResponse<ChatRoom>> createOrGetRoom({
    required ChatRoomType type,
    String? userId, // Para conversas diretas
    String? name, // Para grupos
    List<String>? userIds, // Para grupos
    List<String>? adminIds, // Para grupos
    String? imageUrl, // Para grupos
  }) async {
    try {
      debugPrint('💬 [CHAT_API] Criando/obtendo sala...');
      
      final body = <String, dynamic>{
        'type': type.value,
      };
      
      if (type == ChatRoomType.direct && userId != null) {
        body['userId'] = userId;
      } else if (type == ChatRoomType.group) {
        if (name != null && name.isNotEmpty) {
          body['name'] = name;
        }
        if (userIds != null && userIds.isNotEmpty) {
          body['userIds'] = userIds;
        }
        if (adminIds != null && adminIds.isNotEmpty) {
          body['adminIds'] = adminIds;
        }
        if (imageUrl != null && imageUrl.isNotEmpty) {
          body['imageUrl'] = imageUrl;
        }
      }
      
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.chatRooms,
        body: body,
      );

      if (response.success && response.data != null) {
        try {
          final room = ChatRoom.fromJson(response.data!);
          debugPrint('✅ [CHAT_API] Sala criada/obtida: ${room.id}');
          
          return ApiResponse.success(
            data: room,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CHAT_API] Erro ao parsear sala: $e');
          debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados da sala: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar/obter sala',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_API] Erro ao criar/obter sala: $e');
      debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Listar todas as salas do usuário
  Future<ApiResponse<List<ChatRoom>>> getRooms() async {
    try {
      debugPrint('💬 [CHAT_API] Listando salas...');
      
      final response = await _apiService.get<dynamic>(
        ApiConstants.chatRooms,
      );

      if (response.success && response.data != null) {
        try {
          List<ChatRoom> rooms;
          
          if (response.data is List) {
            final dataList = response.data as List<dynamic>;
            rooms = dataList
                .map((e) {
                  try {
                    return ChatRoom.fromJson(e as Map<String, dynamic>);
                  } catch (e) {
                    debugPrint('❌ [CHAT_API] Erro ao parsear sala: $e');
                    return null;
                  }
                })
                .whereType<ChatRoom>()
                .toList();
          } else {
            throw Exception('Formato de resposta inesperado: ${response.data.runtimeType}');
          }
          
          debugPrint('✅ [CHAT_API] ${rooms.length} salas carregadas');
          
          return ApiResponse.success(
            data: rooms,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CHAT_API] Erro ao parsear lista de salas: $e');
          debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados das salas: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar salas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_API] Erro ao listar salas: $e');
      debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Obter detalhes de uma sala específica
  Future<ApiResponse<ChatRoom>> getRoomById(String roomId) async {
    try {
      debugPrint('💬 [CHAT_API] Buscando sala: $roomId');
      
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.chatRoomById(roomId),
      );

      if (response.success && response.data != null) {
        try {
          final room = ChatRoom.fromJson(response.data!);
          debugPrint('✅ [CHAT_API] Sala carregada: ${room.id}');
          
          return ApiResponse.success(
            data: room,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CHAT_API] Erro ao parsear sala: $e');
          debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados da sala: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar sala',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_API] Erro ao buscar sala: $e');
      debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Atualizar informações da sala
  Future<ApiResponse<ChatRoom>> updateRoom({
    required String roomId,
    String? name,
    String? imageUrl,
  }) async {
    try {
      debugPrint('💬 [CHAT_API] Atualizando sala: $roomId');
      
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (imageUrl != null) body['imageUrl'] = imageUrl;
      
      final response = await _apiService.put<Map<String, dynamic>>(
        ApiConstants.chatRoomById(roomId),
        body: body,
      );

      if (response.success && response.data != null) {
        try {
          final room = ChatRoom.fromJson(response.data!);
          debugPrint('✅ [CHAT_API] Sala atualizada: ${room.id}');
          
          return ApiResponse.success(
            data: room,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CHAT_API] Erro ao parsear sala: $e');
          debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados da sala: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar sala',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_API] Erro ao atualizar sala: $e');
      debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Upload de imagem do grupo
  Future<ApiResponse<ChatRoom>> uploadRoomImage({
    required String roomId,
    required File imageFile,
  }) async {
    try {
      debugPrint('💬 [CHAT_API] Fazendo upload de imagem do grupo: $roomId');
      
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.baseApiUrl}${ApiConstants.chatRoomUploadImage(roomId)}'),
      );

      // Adicionar token de autorização
      final token = await SecureStorageService.instance.getAccessToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      // Adicionar Company ID
      final companyId = await SecureStorageService.instance.getCompanyId();
      if (companyId != null) {
        request.headers['X-Company-ID'] = companyId;
      }

      // Adicionar arquivo
      final fileStream = http.ByteStream(imageFile.openRead());
      final fileLength = await imageFile.length();
      final multipartFile = http.MultipartFile(
        'image',
        fileStream,
        fileLength,
        filename: imageFile.path.split('/').last,
        contentType: MediaType('image', 'jpeg'),
      );
      request.files.add(multipartFile);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final responseData = jsonDecode(response.body) as Map<String, dynamic>;
          if (responseData['success'] == true && responseData['data'] != null) {
            final room = ChatRoom.fromJson(responseData['data'] as Map<String, dynamic>);
            debugPrint('✅ [CHAT_API] Imagem do grupo enviada: ${room.id}');
            
            return ApiResponse.success(
              data: room,
              statusCode: response.statusCode,
            );
          }
        } catch (e, stackTrace) {
          debugPrint('❌ [CHAT_API] Erro ao parsear resposta: $e');
          debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: 'Erro ao fazer upload da imagem',
        statusCode: response.statusCode,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_API] Erro ao fazer upload da imagem: $e');
      debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Adicionar participantes a um grupo
  Future<ApiResponse<ChatRoom>> addParticipants({
    required String roomId,
    required List<String> userIds,
  }) async {
    try {
      debugPrint('💬 [CHAT_API] Adicionando participantes ao grupo: $roomId');
      
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.chatRoomParticipants(roomId),
        body: {'userIds': userIds},
      );

      if (response.success && response.data != null) {
        try {
          final room = ChatRoom.fromJson(response.data!);
          debugPrint('✅ [CHAT_API] Participantes adicionados');
          
          return ApiResponse.success(
            data: room,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CHAT_API] Erro ao parsear sala: $e');
          debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados da sala: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao adicionar participantes',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_API] Erro ao adicionar participantes: $e');
      debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Remover participante de um grupo
  Future<ApiResponse<void>> removeParticipant({
    required String roomId,
    required String userId,
  }) async {
    try {
      debugPrint('💬 [CHAT_API] Removendo participante do grupo: $roomId');
      
      final response = await _apiService.post<dynamic>(
        ApiConstants.chatRoomParticipantsRemove(roomId),
        body: {'userId': userId},
      );

      if (response.success) {
        debugPrint('✅ [CHAT_API] Participante removido');
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao remover participante',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_API] Erro ao remover participante: $e');
      debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Promover usuários a administrador
  Future<ApiResponse<ChatRoom>> promoteAdmin({
    required String roomId,
    required List<String> userIds,
  }) async {
    try {
      debugPrint('💬 [CHAT_API] Promovendo administradores: $roomId');
      
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.chatRoomPromoteAdmin(roomId),
        body: {'userIds': userIds},
      );

      if (response.success && response.data != null) {
        try {
          final room = ChatRoom.fromJson(response.data!);
          debugPrint('✅ [CHAT_API] Administradores promovidos');
          
          return ApiResponse.success(
            data: room,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CHAT_API] Erro ao parsear sala: $e');
          debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados da sala: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao promover administradores',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_API] Erro ao promover administradores: $e');
      debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Remover status de administrador
  Future<ApiResponse<ChatRoom>> removeAdmin({
    required String roomId,
    required List<String> userIds,
  }) async {
    try {
      debugPrint('💬 [CHAT_API] Removendo status de administrador: $roomId');
      
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.chatRoomRemoveAdmin(roomId),
        body: {'userIds': userIds},
      );

      if (response.success && response.data != null) {
        try {
          final room = ChatRoom.fromJson(response.data!);
          debugPrint('✅ [CHAT_API] Status de administrador removido');
          
          return ApiResponse.success(
            data: room,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CHAT_API] Erro ao parsear sala: $e');
          debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados da sala: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao remover status de administrador',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_API] Erro ao remover status de administrador: $e');
      debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Arquivar conversa
  Future<ApiResponse<void>> archiveRoom(String roomId) async {
    try {
      debugPrint('💬 [CHAT_API] Arquivando conversa: $roomId');
      
      final response = await _apiService.post<dynamic>(
        ApiConstants.chatRoomArchive(roomId),
      );

      if (response.success) {
        debugPrint('✅ [CHAT_API] Conversa arquivada');
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao arquivar conversa',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_API] Erro ao arquivar conversa: $e');
      debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Desarquivar conversa
  Future<ApiResponse<void>> unarchiveRoom(String roomId) async {
    try {
      debugPrint('💬 [CHAT_API] Desarquivando conversa: $roomId');
      
      final response = await _apiService.post<dynamic>(
        ApiConstants.chatRoomUnarchive(roomId),
      );

      if (response.success) {
        debugPrint('✅ [CHAT_API] Conversa desarquivada');
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao desarquivar conversa',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_API] Erro ao desarquivar conversa: $e');
      debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Sair de um grupo
  Future<ApiResponse<void>> leaveRoom(String roomId) async {
    try {
      debugPrint('💬 [CHAT_API] Saindo do grupo: $roomId');
      
      final response = await _apiService.post<dynamic>(
        ApiConstants.chatRoomLeave(roomId),
      );

      if (response.success) {
        debugPrint('✅ [CHAT_API] Saída do grupo confirmada');
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao sair do grupo',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_API] Erro ao sair do grupo: $e');
      debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Marcar mensagens como lidas
  Future<ApiResponse<void>> markAsRead(String roomId) async {
    try {
      debugPrint('💬 [CHAT_API] Marcando mensagens como lidas: $roomId');
      
      final response = await _apiService.post<dynamic>(
        ApiConstants.chatRoomRead(roomId),
      );

      if (response.success) {
        debugPrint('✅ [CHAT_API] Mensagens marcadas como lidas');
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao marcar mensagens como lidas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_API] Erro ao marcar mensagens como lidas: $e');
      debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Listar mensagens de uma sala
  Future<ApiResponse<List<ChatMessage>>> getMessages({
    required String roomId,
    int? limit,
    int? offset,
  }) async {
    try {
      debugPrint('💬 [CHAT_API] Listando mensagens: $roomId');
      
      final response = await _apiService.get<dynamic>(
        ApiConstants.chatRoomMessages(roomId, limit: limit, offset: offset),
      );

      if (response.success && response.data != null) {
        try {
          List<ChatMessage> messages;
          
          if (response.data is List) {
            final dataList = response.data as List<dynamic>;
            messages = dataList
                .map((e) {
                  try {
                    return ChatMessage.fromJson(e as Map<String, dynamic>);
                  } catch (e) {
                    debugPrint('❌ [CHAT_API] Erro ao parsear mensagem: $e');
                    return null;
                  }
                })
                .whereType<ChatMessage>()
                .toList();
          } else {
            throw Exception('Formato de resposta inesperado: ${response.data.runtimeType}');
          }
          
          debugPrint('✅ [CHAT_API] ${messages.length} mensagens carregadas');
          
          return ApiResponse.success(
            data: messages,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CHAT_API] Erro ao parsear lista de mensagens: $e');
          debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados das mensagens: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar mensagens',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_API] Erro ao listar mensagens: $e');
      debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Obter histórico de atividades do grupo
  Future<ApiResponse<ChatRoomHistory>> getRoomHistory(String roomId) async {
    try {
      debugPrint('💬 [CHAT_API] Buscando histórico: $roomId');
      
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.chatRoomHistory(roomId),
      );

      if (response.success && response.data != null) {
        try {
          final history = ChatRoomHistory.fromJson(response.data!);
          debugPrint('✅ [CHAT_API] Histórico carregado');
          
          return ApiResponse.success(
            data: history,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CHAT_API] Erro ao parsear histórico: $e');
          debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados do histórico: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar histórico',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_API] Erro ao buscar histórico: $e');
      debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Enviar mensagem (com suporte a arquivos)
  Future<ApiResponse<ChatMessage>> sendMessage({
    required String roomId,
    required String content,
    File? file,
  }) async {
    try {
      debugPrint('💬 [CHAT_API] Enviando mensagem: $roomId');
      
      ApiResponse<ChatMessage> response;
      
      if (file != null) {
        // Enviar com arquivo usando FormData
        response = await _sendMessageWithFile(
          roomId: roomId,
          content: content,
          file: file,
        );
      } else {
        // Enviar apenas texto
        final apiResponse = await _apiService.post<Map<String, dynamic>>(
          ApiConstants.chatMessages,
          body: {
            'roomId': roomId,
            'content': content,
          },
        );

        if (apiResponse.success && apiResponse.data != null) {
          try {
            final message = ChatMessage.fromJson(apiResponse.data!);
            debugPrint('✅ [CHAT_API] Mensagem enviada: ${message.id}');
            
            response = ApiResponse.success(
              data: message,
              statusCode: apiResponse.statusCode,
            );
          } catch (e, stackTrace) {
            debugPrint('❌ [CHAT_API] Erro ao parsear mensagem: $e');
            debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
            response = ApiResponse.error(
              message: 'Erro ao processar dados da mensagem: ${e.toString()}',
              statusCode: apiResponse.statusCode,
            );
          }
        } else {
          response = ApiResponse.error(
            message: apiResponse.message ?? 'Erro ao enviar mensagem',
            statusCode: apiResponse.statusCode,
            data: apiResponse.error,
          );
        }
      }

      return response;
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_API] Erro ao enviar mensagem: $e');
      debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Enviar mensagem com arquivo
  Future<ApiResponse<ChatMessage>> _sendMessageWithFile({
    required String roomId,
    required String content,
    required File file,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.baseApiUrl}${ApiConstants.chatMessages}'),
      );

      // Adicionar token de autorização
      final token = await SecureStorageService.instance.getAccessToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      // Adicionar Company ID
      final companyId = await SecureStorageService.instance.getCompanyId();
      if (companyId != null) {
        request.headers['X-Company-ID'] = companyId;
      }

      // Adicionar campos
      request.fields['roomId'] = roomId;
      if (content.isNotEmpty) {
        request.fields['content'] = content;
      }

      // Adicionar arquivo
      final fileStream = http.ByteStream(file.openRead());
      final fileLength = await file.length();
      
      // Detectar tipo MIME
      final extension = file.path.split('.').last.toLowerCase();
      MediaType? contentType;
      String fieldName = 'files';
      
      if (['jpg', 'jpeg', 'png'].contains(extension)) {
        contentType = MediaType('image', extension == 'png' ? 'png' : 'jpeg');
        fieldName = 'files';
      } else if (extension == 'pdf') {
        contentType = MediaType('application', 'pdf');
        fieldName = 'files';
      } else {
        contentType = MediaType('application', 'octet-stream');
        fieldName = 'files';
      }
      
      final multipartFile = http.MultipartFile(
        fieldName,
        fileStream,
        fileLength,
        filename: file.path.split('/').last,
        contentType: contentType,
      );
      request.files.add(multipartFile);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final responseData = jsonDecode(response.body) as Map<String, dynamic>;
          if (responseData['success'] == true && responseData['data'] != null) {
            final message = ChatMessage.fromJson(responseData['data'] as Map<String, dynamic>);
            debugPrint('✅ [CHAT_API] Mensagem com arquivo enviada: ${message.id}');
            
            return ApiResponse.success(
              data: message,
              statusCode: response.statusCode,
            );
          }
        } catch (e, stackTrace) {
          debugPrint('❌ [CHAT_API] Erro ao parsear resposta: $e');
          debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: 'Erro ao enviar mensagem com arquivo',
        statusCode: response.statusCode,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_API] Erro ao enviar mensagem com arquivo: $e');
      debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Editar mensagem
  Future<ApiResponse<ChatMessage>> editMessage({
    required String messageId,
    required String content,
  }) async {
    try {
      debugPrint('💬 [CHAT_API] Editando mensagem: $messageId');
      
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.chatMessagesEdit,
        body: {
          'messageId': messageId,
          'content': content,
        },
      );

      if (response.success && response.data != null) {
        try {
          final message = ChatMessage.fromJson(response.data!);
          debugPrint('✅ [CHAT_API] Mensagem editada: ${message.id}');
          
          return ApiResponse.success(
            data: message,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CHAT_API] Erro ao parsear mensagem: $e');
          debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados da mensagem: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao editar mensagem',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_API] Erro ao editar mensagem: $e');
      debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Deletar mensagem
  Future<ApiResponse<void>> deleteMessage(String messageId) async {
    try {
      debugPrint('💬 [CHAT_API] Deletando mensagem: $messageId');
      
      final response = await _apiService.post<dynamic>(
        ApiConstants.chatMessagesDelete,
        body: {'messageId': messageId},
      );

      if (response.success) {
        debugPrint('✅ [CHAT_API] Mensagem deletada');
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao deletar mensagem',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_API] Erro ao deletar mensagem: $e');
      debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Listar usuários da empresa
  Future<ApiResponse<List<CompanyUser>>> getCompanyUsers() async {
    try {
      debugPrint('💬 [CHAT_API] Listando usuários da empresa...');
      
      final response = await _apiService.get<dynamic>(
        ApiConstants.chatCompanyUsers,
      );

      if (response.success && response.data != null) {
        try {
          List<CompanyUser> users;
          
          if (response.data is List) {
            final dataList = response.data as List<dynamic>;
            users = dataList
                .map((e) {
                  try {
                    return CompanyUser.fromJson(e as Map<String, dynamic>);
                  } catch (e) {
                    debugPrint('❌ [CHAT_API] Erro ao parsear usuário: $e');
                    return null;
                  }
                })
                .whereType<CompanyUser>()
                .toList();
          } else {
            throw Exception('Formato de resposta inesperado: ${response.data.runtimeType}');
          }
          
          debugPrint('✅ [CHAT_API] ${users.length} usuários carregados');
          
          return ApiResponse.success(
            data: users,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CHAT_API] Erro ao parsear lista de usuários: $e');
          debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados dos usuários: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar usuários',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CHAT_API] Erro ao listar usuários: $e');
      debugPrint('📚 [CHAT_API] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}

