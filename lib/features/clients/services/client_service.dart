import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../models/client_model.dart';

// Re-export UserInfo para uso no serviço
export '../models/client_model.dart' show UserInfo;

/// Serviço para gerenciar clientes
class ClientService {
  ClientService._();

  static final ClientService instance = ClientService._();
  final ApiService _apiService = ApiService.instance;

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

  /// Cria uma nova interação
  Future<ApiResponse<ClientInteraction>> createClientInteraction(
    String clientId, {
    required String notes,
    String? title,
    String? interactionAt,
  }) async {
    try {
      debugPrint('📝 [CLIENT_SERVICE] Criando interação para cliente $clientId...');

      final body = <String, dynamic>{
        'notes': notes,
        if (title != null && title.isNotEmpty) 'title': title,
        if (interactionAt != null && interactionAt.isNotEmpty)
          'interactionAt': interactionAt,
      };

      final response = await _apiService.post<dynamic>(
        ApiConstants.clientInteractions(clientId),
        body: body,
      );

      if (response.success && response.data != null) {
        try {
          final raw = response.data is Map<String, dynamic>
              ? response.data as Map<String, dynamic>
              : null;
          if (raw == null) {
            return ApiResponse.error(
              message: 'Resposta inválida ao criar interação',
              statusCode: response.statusCode,
            );
          }
          // Algumas APIs envolvem o item em { data: {...} }
          final json = raw['data'] is Map<String, dynamic>
              ? raw['data'] as Map<String, dynamic>
              : raw;
          final interaction = ClientInteraction.fromJson(json);
          return ApiResponse.success(
            data: interaction,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [CLIENT_SERVICE] Erro ao parsear interação criada: $e');
          debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar interação criada',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar interação',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CLIENT_SERVICE] Erro ao criar interação: $e');
      debugPrint('📚 [CLIENT_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
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

