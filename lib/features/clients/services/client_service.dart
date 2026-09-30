import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/profile_service.dart';
import '../models/client_model.dart';

// Re-export UserInfo para uso no serviço
export '../models/client_model.dart' show UserInfo;

/// Serviço para gerenciar clientes
class ClientService {
  ClientService._();

  static final ClientService instance = ClientService._();
  final ApiService _apiService = ApiService.instance;

  // Endpoints que ainda não estão no ApiConstants (paridade imobx-front).
  static const String _spousesBase = '/spouses';
  static String _spouseForClient(String clientId) =>
      '/spouses/client/$clientId';
  static const String _companyUsers = '/users';

  /// Lista clientes com filtros
  Future<ApiResponse<ClientListResponse>> getClients({
    ClientSearchFilters? filters,
  }) async {
    try {
      debugPrint('👥 [CLIENT_SERVICE] Buscando clientes...');
      
      final queryParams = filters?.toQueryParams() ?? <String, String>{};
      
      debugPrint('👥 [CLIENT_SERVICE] Filtros: $queryParams');
      
      final response = await _apiService.get<dynamic>(
        ApiConstants.clients,
        queryParameters: queryParams,
      );

      debugPrint('👥 [CLIENT_SERVICE] Resposta recebida:');
      debugPrint('   - Success: ${response.success}');
      debugPrint('   - Status Code: ${response.statusCode}');
      debugPrint('   - Data type: ${response.data?.runtimeType}');

      if (response.success && response.data != null) {
        try {
          ClientListResponse clientList;
          
          // Verificar se a resposta é uma lista direta ou um objeto com 'data'
          if (response.data is List) {
            debugPrint('👥 [CLIENT_SERVICE] Resposta é uma lista direta');
            final dataList = response.data as List<dynamic>;
            clientList = ClientListResponse(
              data: dataList
                  .map((e) {
                    try {
                      return Client.fromJson(e as Map<String, dynamic>);
                    } catch (e) {
                      debugPrint('❌ [CLIENT_SERVICE] Erro ao parsear item da lista: $e');
                      return null;
                    }
                  })
                  .whereType<Client>()
                  .toList(),
              pagination: null,
            );
          } else if (response.data is Map<String, dynamic>) {
            debugPrint('👥 [CLIENT_SERVICE] Resposta é um objeto com estrutura');
            clientList = ClientListResponse.fromJson(response.data as Map<String, dynamic>);
          } else {
            throw Exception('Formato de resposta inesperado: ${response.data.runtimeType}');
          }
          
          debugPrint('✅ [CLIENT_SERVICE] ${clientList.data.length} clientes carregados');
          
          return ApiResponse.success(
            data: clientList,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CLIENT_SERVICE] Erro ao parsear lista de clientes: $e');
          debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
          debugPrint('📚 [CLIENT_SERVICE] Data recebida: ${response.data}');
          return ApiResponse.error(
            message: 'Erro ao processar dados dos clientes: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar clientes',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CLIENT_SERVICE] Erro ao buscar clientes: $e');
      debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca cliente por ID
  Future<ApiResponse<Client>> getClientById(String id) async {
    try {
      debugPrint('👥 [CLIENT_SERVICE] Buscando cliente: $id');
      
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.clientById(id),
      );

      if (response.success && response.data != null) {
        try {
          final client = Client.fromJson(response.data!);
          debugPrint('✅ [CLIENT_SERVICE] Cliente carregado: ${client.name}');
          
          return ApiResponse.success(
            data: client,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CLIENT_SERVICE] Erro ao parsear cliente: $e');
          debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados do cliente: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar cliente',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CLIENT_SERVICE] Erro ao buscar cliente: $e');
      debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Cria um novo cliente
  Future<ApiResponse<Client>> createClient(CreateClientDto data) async {
    try {
      debugPrint('👥 [CLIENT_SERVICE] Criando cliente: ${data.name}');
      
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.clients,
        body: data.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          final client = Client.fromJson(response.data!);
          debugPrint('✅ [CLIENT_SERVICE] Cliente criado: ${client.id}');
          
          return ApiResponse.success(
            data: client,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CLIENT_SERVICE] Erro ao parsear cliente criado: $e');
          debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar cliente',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CLIENT_SERVICE] Erro ao criar cliente: $e');
      debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Cadastro rápido de cliente — `POST /clients` com o payload mínimo
  /// (`{ name, phone, type, capturedById }`), usado no vínculo direto pelo card
  /// do CRM.
  ///
  /// Não usa o [CreateClientDto] de propósito: aquele DTO exige endereço,
  /// e-mail e CPF, enquanto no backend só `name`, `phone`, `type` e
  /// **`capturedById`** são obrigatórios (os demais são `@IsOptional`, e mandar
  /// e-mail vazio dispararia o `@IsEmail`).
  ///
  /// [capturedById] é obrigatório no backend; quando não vier, resolvemos o
  /// usuário logado via perfil — mesmo fallback do web
  /// (`capturedById || currentUser.id`).
  ///
  /// Devolve o **id** do cliente criado.
  Future<ApiResponse<String>> createQuickClient({
    required String name,
    required String phone,
    ClientType type = ClientType.general,
    String? capturedById,
  }) async {
    try {
      final trimmedName = name.trim();
      // O backend valida `name` entre 3 e 255 caracteres.
      if (trimmedName.length < 3) {
        return ApiResponse.error(
          message: 'Informe o nome completo do cliente (mínimo 3 letras)',
          statusCode: 400,
        );
      }

      // O backend normaliza para dígitos e exige de 10 a 13.
      final digits = phone.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 10 || digits.length > 13) {
        return ApiResponse.error(
          message: 'Telefone inválido — informe DDD e número',
          statusCode: 400,
        );
      }

      var ownerId = capturedById?.trim();
      if (ownerId == null || ownerId.isEmpty) {
        final profile = await ProfileService.instance.getProfile();
        ownerId = profile.data?.id;
      }
      if (ownerId == null || ownerId.isEmpty) {
        return ApiResponse.error(
          message: 'Não foi possível identificar o usuário responsável',
          statusCode: 400,
        );
      }

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.clients,
        body: {
          'name': trimmedName,
          'phone': digits,
          'type': type.value,
          'capturedById': ownerId,
        },
      );

      if (response.success) {
        final id = response.data?['id']?.toString();
        if (id != null && id.isNotEmpty) {
          return ApiResponse.success(data: id, statusCode: response.statusCode);
        }
        debugPrint('❌ [CLIENT_SERVICE] createQuickClient sem id na resposta');
        return ApiResponse.error(
          message: 'Cliente criado, mas o id não veio na resposta',
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao cadastrar cliente',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [CLIENT_SERVICE] createQuickClient: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Atualiza um cliente
  Future<ApiResponse<Client>> updateClient(String id, UpdateClientDto data) async {
    try {
      debugPrint('👥 [CLIENT_SERVICE] Atualizando cliente: $id');
      
      final response = await _apiService.put<Map<String, dynamic>>(
        ApiConstants.clientUpdate(id),
        body: data.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          final client = Client.fromJson(response.data!);
          debugPrint('✅ [CLIENT_SERVICE] Cliente atualizado: ${client.name}');
          
          return ApiResponse.success(
            data: client,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CLIENT_SERVICE] Erro ao parsear cliente atualizado: $e');
          debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar cliente',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CLIENT_SERVICE] Erro ao atualizar cliente: $e');
      debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Exclui um cliente (soft delete)
  Future<ApiResponse<void>> deleteClient(String id, {bool permanent = false}) async {
    try {
      debugPrint('👥 [CLIENT_SERVICE] Excluindo cliente: $id (permanent: $permanent)');
      
      final endpoint = permanent 
          ? ApiConstants.clientDeletePermanent(id)
          : ApiConstants.clientDelete(id);
      
      final response = await _apiService.delete<void>(
        endpoint,
      );

      if (response.success) {
        debugPrint('✅ [CLIENT_SERVICE] Cliente excluído com sucesso');
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao excluir cliente',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CLIENT_SERVICE] Erro ao excluir cliente: $e');
      debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Obtém estatísticas de clientes
  Future<ApiResponse<ClientStatistics>> getStatistics({
    ClientSearchFilters? filters,
  }) async {
    try {
      debugPrint('👥 [CLIENT_SERVICE] Buscando estatísticas...');
      
      final queryParams = filters?.toQueryParams() ?? <String, String>{};
      
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.clientsStatistics,
        queryParameters: queryParams,
      );

      if (response.success && response.data != null) {
        try {
          final statistics = ClientStatistics.fromJson(response.data!);
          debugPrint('✅ [CLIENT_SERVICE] Estatísticas carregadas');
          
          return ApiResponse.success(
            data: statistics,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CLIENT_SERVICE] Erro ao parsear estatísticas: $e');
          debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar estatísticas: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar estatísticas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CLIENT_SERVICE] Erro ao buscar estatísticas: $e');
      debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Transfere cliente para outro responsável
  Future<ApiResponse<Client>> transferClient(
    String clientId,
    String newResponsibleUserId,
  ) async {
    try {
      debugPrint('👥 [CLIENT_SERVICE] Transferindo cliente $clientId para $newResponsibleUserId');
      
      final response = await _apiService.put<Map<String, dynamic>>(
        ApiConstants.clientTransfer(clientId),
        body: {
          'newResponsibleUserId': newResponsibleUserId,
        },
      );

      if (response.success && response.data != null) {
        try {
          final client = Client.fromJson(response.data!);
          debugPrint('✅ [CLIENT_SERVICE] Cliente transferido com sucesso');
          
          return ApiResponse.success(
            data: client,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CLIENT_SERVICE] Erro ao parsear cliente transferido: $e');
          debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao transferir cliente',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CLIENT_SERVICE] Erro ao transferir cliente: $e');
      debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista usuários disponíveis para transferência
  Future<ApiResponse<List<UserInfo>>> getUsersForTransfer() async {
    try {
      debugPrint('👥 [CLIENT_SERVICE] Buscando usuários para transferência...');
      
      final response = await _apiService.get<dynamic>(
        ApiConstants.clientsUsersForTransfer,
      );

      if (response.success && response.data != null) {
        try {
          List<UserInfo> users = [];
          
          if (response.data is List) {
            final dataList = response.data as List<dynamic>;
            users = dataList
                .map((e) {
                  try {
                    return UserInfo.fromJson(e as Map<String, dynamic>);
                  } catch (e) {
                    debugPrint('❌ [CLIENT_SERVICE] Erro ao parsear usuário: $e');
                    return null;
                  }
                })
                .whereType<UserInfo>()
                .toList();
          } else if (response.data is Map<String, dynamic>) {
            final dataMap = response.data as Map<String, dynamic>;
            if (dataMap['data'] is List) {
              final dataList = dataMap['data'] as List<dynamic>;
              users = dataList
                  .map((e) {
                    try {
                      return UserInfo.fromJson(e as Map<String, dynamic>);
                    } catch (e) {
                      return null;
                    }
                  })
                  .whereType<UserInfo>()
                  .toList();
            }
          }
          
          debugPrint('✅ [CLIENT_SERVICE] ${users.length} usuários carregados para transferência');
          
          return ApiResponse.success(
            data: users,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CLIENT_SERVICE] Erro ao parsear usuários: $e');
          debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados dos usuários: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar usuários',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CLIENT_SERVICE] Erro ao buscar usuários: $e');
      debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista interações de um cliente
  Future<ApiResponse<List<ClientInteraction>>> getClientInteractions(String clientId) async {
    try {
      debugPrint('📝 [CLIENT_SERVICE] Buscando interações do cliente $clientId...');
      
      final response = await _apiService.get<dynamic>(
        ApiConstants.clientInteractions(clientId),
      );

      if (response.success && response.data != null) {
        try {
          List<ClientInteraction> interactions = [];
          
          if (response.data is List) {
            final dataList = response.data as List<dynamic>;
            interactions = dataList
                .map((e) {
                  try {
                    return ClientInteraction.fromJson(e as Map<String, dynamic>);
                  } catch (e) {
                    debugPrint('❌ [CLIENT_SERVICE] Erro ao parsear interação: $e');
                    return null;
                  }
                })
                .whereType<ClientInteraction>()
                .toList();
          } else if (response.data is Map<String, dynamic>) {
            final dataMap = response.data as Map<String, dynamic>;
            if (dataMap['data'] is List) {
              final dataList = dataMap['data'] as List<dynamic>;
              interactions = dataList
                  .map((e) {
                    try {
                      return ClientInteraction.fromJson(e as Map<String, dynamic>);
                    } catch (e) {
                      return null;
                    }
                  })
                  .whereType<ClientInteraction>()
                  .toList();
            }
          }
          
          debugPrint('✅ [CLIENT_SERVICE] ${interactions.length} interações carregadas');
          
          return ApiResponse.success(
            data: interactions,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CLIENT_SERVICE] Erro ao parsear interações: $e');
          debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados das interações: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar interações',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CLIENT_SERVICE] Erro ao buscar interações: $e');
      debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Cria uma nova interação — `POST /clients/:id/interactions` em
  /// multipart (campos `title`, `notes`, `interactionAt` e até 10 `files`
  /// de 20 MB), igual ao `ClientInteractionsPanel` do web.
  Future<ApiResponse<ClientInteraction>> createClientInteraction(
    String clientId, {
    required String notes,
    String? title,
    String? interactionAt,
    List<File> files = const [],
  }) {
    debugPrint('📝 [CLIENT_SERVICE] Criando interação para cliente $clientId...');
    return _sendInteractionMultipart(
      method: 'POST',
      endpoint: ApiConstants.clientInteractions(clientId),
      notes: notes,
      title: title,
      interactionAt: interactionAt,
      files: files,
      fallbackError: 'Erro ao criar interação',
    );
  }

  /// Edita uma interação — `PUT /clients/:id/interactions/:iid` em multipart.
  /// [retainAttachmentKeys] lista as chaves dos anexos já existentes que
  /// continuam; os que ficarem de fora são removidos pelo back.
  Future<ApiResponse<ClientInteraction>> updateClientInteraction(
    String clientId,
    String interactionId, {
    required String notes,
    String? title,
    String? interactionAt,
    List<File> files = const [],
    List<String> retainAttachmentKeys = const [],
  }) {
    debugPrint('📝 [CLIENT_SERVICE] Editando interação $interactionId...');
    return _sendInteractionMultipart(
      method: 'PUT',
      endpoint: ApiConstants.clientInteraction(clientId, interactionId),
      notes: notes,
      title: title,
      interactionAt: interactionAt,
      files: files,
      retainAttachmentKeys: retainAttachmentKeys,
      fallbackError: 'Erro ao atualizar interação',
    );
  }

  Future<ApiResponse<ClientInteraction>> _sendInteractionMultipart({
    required String method,
    required String endpoint,
    required String notes,
    String? title,
    String? interactionAt,
    List<File> files = const [],
    List<String>? retainAttachmentKeys,
    required String fallbackError,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');
      final request = http.MultipartRequest(method, uri);
      request.headers.addAll(
        await _apiService.buildOutboundHeaders(
          endpoint: endpoint,
          excludeContentType: true,
        ),
      );

      request.fields['notes'] = notes;
      if (title != null && title.trim().isNotEmpty) {
        request.fields['title'] = title.trim();
      }
      if (interactionAt != null && interactionAt.isNotEmpty) {
        request.fields['interactionAt'] = interactionAt;
      }
      if (retainAttachmentKeys != null) {
        request.fields['retainAttachmentKeys'] =
            jsonEncode(retainAttachmentKeys);
      }

      for (final file in files) {
        final name = file.path.split(RegExp(r'[\\/]')).last;
        request.files.add(
          await http.MultipartFile.fromPath(
            'files',
            file.path,
            filename: name,
            contentType: _guessMediaType(name),
          ),
        );
      }

      final streamed =
          await request.send().timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamed);

      dynamic decoded;
      try {
        decoded = response.body.isEmpty ? null : jsonDecode(response.body);
      } catch (_) {
        decoded = null;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final raw = decoded is Map<String, dynamic> ? decoded : null;
        if (raw == null) {
          return ApiResponse.error(
            message: 'Resposta inválida do servidor',
            statusCode: response.statusCode,
          );
        }
        // Algumas APIs envolvem o item em { data: {...} }
        final json = raw['data'] is Map<String, dynamic>
            ? raw['data'] as Map<String, dynamic>
            : raw;
        return ApiResponse.success(
          data: ClientInteraction.fromJson(json),
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: _extractMessage(decoded) ?? fallbackError,
        statusCode: response.statusCode,
        data: decoded,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CLIENT_SERVICE] $fallbackError: $e');
      debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  static MediaType? _guessMediaType(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'gif':
        return MediaType('image', 'gif');
      case 'webp':
        return MediaType('image', 'webp');
      case 'heic':
        return MediaType('image', 'heic');
      case 'pdf':
        return MediaType('application', 'pdf');
      case 'doc':
        return MediaType('application', 'msword');
      case 'docx':
        return MediaType(
          'application',
          'vnd.openxmlformats-officedocument.wordprocessingml.document',
        );
      case 'xls':
        return MediaType('application', 'vnd.ms-excel');
      case 'xlsx':
        return MediaType(
          'application',
          'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
      case 'txt':
        return MediaType('text', 'plain');
      case 'mp4':
        return MediaType('video', 'mp4');
      case 'mp3':
        return MediaType('audio', 'mpeg');
      default:
        return null;
    }
  }

  static String? _extractMessage(dynamic decoded) {
    if (decoded is Map) {
      final msg = decoded['message'];
      if (msg is String && msg.trim().isNotEmpty) return msg;
      if (msg is List && msg.isNotEmpty) {
        return msg.map((e) => e.toString()).join('\n');
      }
      final err = decoded['error'];
      if (err is String && err.trim().isNotEmpty) return err;
    }
    return null;
  }

  // ───────────────────────── Cônjuge (/spouses) ─────────────────────────

  /// `GET /spouses/client/:clientId` — 404 vira `data: null` (sem cônjuge),
  /// igual ao `spouseApi.getSpouseByClientId` do web.
  Future<ApiResponse<Spouse?>> getSpouseByClient(String clientId) async {
    try {
      final response =
          await _apiService.get<dynamic>(_spouseForClient(clientId));
      if (response.success) {
        final data = response.data;
        return ApiResponse.success(
          data: data is Map<String, dynamic> && data['id'] != null
              ? Spouse.fromJson(data)
              : null,
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode == 404) {
        return ApiResponse.success(data: null, statusCode: 404);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar cônjuge',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /spouses/:clientId`
  Future<ApiResponse<Spouse>> createSpouse(
    String clientId,
    Spouse spouse,
  ) async {
    try {
      final response = await _apiService.post<dynamic>(
        '$_spousesBase/$clientId',
        body: spouse.toJson(),
      );
      return _spouseResult(response, 'Erro ao cadastrar cônjuge');
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PATCH /spouses/:id`
  Future<ApiResponse<Spouse>> updateSpouse(
    String spouseId,
    Spouse spouse,
  ) async {
    try {
      final response = await _apiService.patch<dynamic>(
        '$_spousesBase/$spouseId',
        body: spouse.toJson(),
      );
      return _spouseResult(response, 'Erro ao atualizar cônjuge');
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `DELETE /spouses/:id`
  Future<ApiResponse<void>> deleteSpouse(String spouseId) async {
    try {
      final response =
          await _apiService.delete<dynamic>('$_spousesBase/$spouseId');
      if (response.success) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao remover cônjuge',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  ApiResponse<Spouse> _spouseResult(
    ApiResponse<dynamic> response,
    String fallback,
  ) {
    if (response.success) {
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final json = data['data'] is Map<String, dynamic>
            ? data['data'] as Map<String, dynamic>
            : data;
        return ApiResponse.success(
          data: Spouse.fromJson(json),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: 'Resposta inválida do servidor',
        statusCode: response.statusCode,
      );
    }
    return ApiResponse.error(
      message: response.message ?? fallback,
      statusCode: response.statusCode,
      data: response.error,
    );
  }

  // ───────────────────────── Captador ─────────────────────────

  /// Usuários da empresa para o seletor "Captador" — `GET /users?page=1&limit=100`,
  /// a mesma chamada que o `ClientFormPage` do web faz com `getUsers`.
  /// Sem acesso à listagem de usuários, cai para `/clients/users-for-transfer`.
  Future<ApiResponse<List<UserInfo>>> getCompanyUsers() async {
    try {
      final response = await _apiService.get<dynamic>(
        _companyUsers,
        queryParameters: const {'page': '1', 'limit': '100'},
      );
      if (response.success && response.data != null) {
        final data = response.data;
        final list = data is List
            ? data
            : (data is Map<String, dynamic> && data['data'] is List
                ? data['data'] as List<dynamic>
                : const <dynamic>[]);
        final users = list
            .whereType<Map>()
            .map((e) => UserInfo.fromJson(Map<String, dynamic>.from(e)))
            .where((u) => u.id.isNotEmpty)
            .toList();
        if (users.isNotEmpty) {
          return ApiResponse.success(
            data: users,
            statusCode: response.statusCode,
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ [CLIENT_SERVICE] getCompanyUsers: $e');
    }
    return getUsersForTransfer();
  }

  // ───────────────────────── Importação / exportação ─────────────────────────

  /// Planilha de erros de um job de importação —
  /// `GET /clients/import-jobs/:jobId/errors` (blob .xlsx).
  Future<ApiResponse<List<int>>> downloadImportErrors(String jobId) async {
    try {
      final endpoint = ApiConstants.clientsImportJobErrors(jobId);
      final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');
      final headers = await _apiService.buildOutboundHeaders(
        endpoint: endpoint,
      );
      final httpResponse = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 60));
      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        return ApiResponse.success(
          data: httpResponse.bodyBytes.toList(),
          statusCode: httpResponse.statusCode,
        );
      }
      return ApiResponse.error(
        message: httpResponse.statusCode == 404
            ? 'Planilha de erros não encontrada. Pode não haver erros ou o job ainda está processando.'
            : 'Erro ao baixar planilha de erros.',
        statusCode: httpResponse.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Todos os clientes da busca/filtro atual, página a página (limite 100),
  /// para a exportação local — o web exporta a lista filtrada da tela.
  Future<ApiResponse<List<Client>>> fetchAllClients({
    ClientSearchFilters? filters,
    String? search,
    int maxRecords = 10000,
  }) async {
    final all = <Client>[];
    var page = 1;
    var totalPages = 1;
    do {
      final response = await getClients(
        filters: (filters ?? ClientSearchFilters()).copyWith(
          search: search == null || search.trim().isEmpty
              ? null
              : search.trim(),
          page: page,
          limit: 100,
        ),
      );
      if (!response.success || response.data == null) {
        return ApiResponse.error(
          message: response.message ?? 'Erro ao buscar clientes',
          statusCode: response.statusCode,
          data: response.error,
        );
      }
      all.addAll(response.data!.data);
      totalPages = response.data!.pagination?.totalPages ?? 1;
      if (response.data!.data.isEmpty) break;
      page++;
    } while (page <= totalPages && all.length < maxRecords);
    return ApiResponse.success(data: all, statusCode: 200);
  }

  /// Exclui uma interação
  Future<ApiResponse<void>> deleteClientInteraction(
    String clientId,
    String interactionId,
  ) async {
    try {
      debugPrint('🗑️ [CLIENT_SERVICE] Excluindo interação $interactionId do cliente $clientId...');
      
      final response = await _apiService.delete(
        ApiConstants.clientInteraction(clientId, interactionId),
      );

      if (response.success) {
        debugPrint('✅ [CLIENT_SERVICE] Interação excluída com sucesso');
        return ApiResponse.success(
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao excluir interação',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CLIENT_SERVICE] Erro ao excluir interação: $e');
      debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Associa cliente a uma propriedade
  Future<ApiResponse<void>> associateClientToProperty(
    String clientId,
    String propertyId, {
    String? interestType,
    String? notes,
  }) async {
    try {
      debugPrint('🔗 [CLIENT_SERVICE] Associando cliente $clientId à propriedade $propertyId...');
      
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.clientPropertyAssociate(clientId, propertyId),
        body: {
          'interestType': ?interestType,
          'notes': ?notes,
        },
      );

      if (response.success) {
        debugPrint('✅ [CLIENT_SERVICE] Cliente associado à propriedade com sucesso');
        return ApiResponse.success(
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao associar cliente à propriedade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CLIENT_SERVICE] Erro ao associar cliente à propriedade: $e');
      debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Desassocia cliente de uma propriedade
  Future<ApiResponse<void>> disassociateClientFromProperty(
    String clientId,
    String propertyId,
  ) async {
    try {
      debugPrint('🔗 [CLIENT_SERVICE] Desassociando cliente $clientId da propriedade $propertyId...');
      
      final response = await _apiService.delete(
        ApiConstants.clientPropertyDisassociate(clientId, propertyId),
      );

      if (response.success) {
        debugPrint('✅ [CLIENT_SERVICE] Cliente desassociado da propriedade com sucesso');
        return ApiResponse.success(
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao desassociar cliente da propriedade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CLIENT_SERVICE] Erro ao desassociar cliente da propriedade: $e');
      debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista propriedades de um cliente
  Future<ApiResponse<List<dynamic>>> getClientProperties(String clientId) async {
    try {
      debugPrint('🏠 [CLIENT_SERVICE] Buscando propriedades do cliente $clientId...');
      
      final response = await _apiService.get<dynamic>(
        ApiConstants.clientProperties(clientId),
      );

      if (response.success && response.data != null) {
        try {
          List<dynamic> properties = [];
          
          if (response.data is List) {
            properties = response.data as List<dynamic>;
          } else if (response.data is Map<String, dynamic>) {
            final dataMap = response.data as Map<String, dynamic>;
            if (dataMap['data'] is List) {
              properties = dataMap['data'] as List<dynamic>;
            }
          }
          
          debugPrint('✅ [CLIENT_SERVICE] ${properties.length} propriedades encontradas');
          
          return ApiResponse.success(
            data: properties,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CLIENT_SERVICE] Erro ao parsear propriedades: $e');
          debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados das propriedades: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar propriedades',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CLIENT_SERVICE] Erro ao buscar propriedades: $e');
      debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista clientes de uma propriedade
  Future<ApiResponse<List<Client>>> getClientsByProperty(String propertyId) async {
    try {
      debugPrint('👥 [CLIENT_SERVICE] Buscando clientes da propriedade $propertyId...');
      
      final response = await _apiService.get<dynamic>(
        ApiConstants.clientByProperty(propertyId),
      );

      if (response.success && response.data != null) {
        try {
          List<Client> clients = [];
          
          if (response.data is List) {
            final dataList = response.data as List<dynamic>;
            clients = dataList
                .map((e) {
                  try {
                    return Client.fromJson(e as Map<String, dynamic>);
                  } catch (e) {
                    debugPrint('❌ [CLIENT_SERVICE] Erro ao parsear cliente: $e');
                    return null;
                  }
                })
                .whereType<Client>()
                .toList();
          } else if (response.data is Map<String, dynamic>) {
            final dataMap = response.data as Map<String, dynamic>;
            if (dataMap['data'] is List) {
              final dataList = dataMap['data'] as List<dynamic>;
              clients = dataList
                  .map((e) {
                    try {
                      return Client.fromJson(e as Map<String, dynamic>);
                    } catch (e) {
                      return null;
                    }
                  })
                  .whereType<Client>()
                  .toList();
            }
          }
          
          debugPrint('✅ [CLIENT_SERVICE] ${clients.length} clientes encontrados');
          
          return ApiResponse.success(
            data: clients,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CLIENT_SERVICE] Erro ao parsear clientes: $e');
          debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados dos clientes: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar clientes',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CLIENT_SERVICE] Erro ao buscar clientes: $e');
      debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Exporta clientes
  Future<ApiResponse<List<int>>> exportClients({
    ClientSearchFilters? filters,
    String format = 'xlsx', // 'xlsx' | 'csv'
  }) async {
    debugPrint('📤 [CLIENT_SERVICE] Exportando clientes (formato: $format)');

    try {
      final queryParams = filters?.toQueryParams() ?? <String, String>{};
      queryParams['format'] = format;

      final uri = Uri.parse('${ApiConstants.baseApiUrl}${ApiConstants.clientsExport}')
          .replace(queryParameters: queryParams);

      // Headers padronizados (Authorization + X-Company-ID) — paridade
      // `imobx-front` via `ApiService.buildOutboundHeaders`.
      final headers = await _apiService.buildOutboundHeaders(
        endpoint: ApiConstants.clientsExport,
      );

      final httpResponse = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 120));

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        debugPrint('✅ [CLIENT_SERVICE] Clientes exportados');
        return ApiResponse.success(
          data: httpResponse.bodyBytes.toList(),
          statusCode: httpResponse.statusCode,
        );
      }

      return ApiResponse.error(
        message: 'Erro ao exportar clientes',
        statusCode: httpResponse.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [CLIENT_SERVICE] Erro ao exportar clientes: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}

