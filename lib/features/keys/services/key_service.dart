import 'package:flutter/foundation.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../models/key_model.dart' as key_models;

/// Serviço para gerenciar chaves
class KeyService {
  KeyService._();

  static final KeyService instance = KeyService._();
  final ApiService _apiService = ApiService.instance;

  /// Lista chaves com filtros
  Future<ApiResponse<List<key_models.Key>>> getKeys({key_models.KeyFilters? filters}) async {
    try {
      debugPrint('🔑 [KEY_SERVICE] Buscando chaves...');
      
      final queryParams = filters?.toQueryParams() ?? {};
      debugPrint('🔑 [KEY_SERVICE] Filtros: $queryParams');

      final response = await _apiService.get<dynamic>(
        ApiConstants.keys,
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      if (response.success && response.data != null) {
        try {
          List<key_models.Key> keys;
          
          if (response.data is List) {
            keys = (response.data as List)
                .map((e) => key_models.Key.fromJson(e as Map<String, dynamic>))
                .toList();
          } else if (response.data is Map<String, dynamic>) {
            final data = response.data as Map<String, dynamic>;
            final keysList = data['keys'] as List? ?? data['data'] as List? ?? [];
            keys = keysList
                .map((e) => key_models.Key.fromJson(e as Map<String, dynamic>))
                .toList();
          } else {
            keys = [];
          }

          debugPrint('✅ [KEY_SERVICE] ${keys.length} chaves carregadas');
          
          return ApiResponse.success(
            data: keys,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [KEY_SERVICE] Erro ao parsear lista de chaves: $e');
          debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados das chaves: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar chaves',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [KEY_SERVICE] Erro ao buscar chaves: $e');
      debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca chave por ID
  Future<ApiResponse<key_models.Key>> getKeyById(String id) async {
    try {
      debugPrint('🔑 [KEY_SERVICE] Buscando chave: $id');

      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.keyById(id),
      );

      if (response.success && response.data != null) {
        try {
          final key = key_models.Key.fromJson(response.data!);
          debugPrint('✅ [KEY_SERVICE] Chave encontrada: ${key.name}');
          
          return ApiResponse.success(
            data: key,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [KEY_SERVICE] Erro ao parsear chave: $e');
          debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados da chave: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar chave',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [KEY_SERVICE] Erro ao buscar chave: $e');
      debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Cria nova chave
  Future<ApiResponse<key_models.Key>> createKey(key_models.CreateKeyDto dto) async {
    try {
      debugPrint('🔑 [KEY_SERVICE] Criando chave...');
      
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.keys,
        body: dto.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          final key = key_models.Key.fromJson(response.data!);
          debugPrint('✅ [KEY_SERVICE] Chave criada com sucesso: ${key.id}');
          
          return ApiResponse.success(
            data: key,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [KEY_SERVICE] Erro ao parsear chave criada: $e');
          debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar chave',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [KEY_SERVICE] Erro ao criar chave: $e');
      debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Atualiza chave
  Future<ApiResponse<key_models.Key>> updateKey(String id, key_models.UpdateKeyDto dto) async {
    try {
      debugPrint('🔑 [KEY_SERVICE] Atualizando chave: $id');
      
      final response = await _apiService.patch<Map<String, dynamic>>(
        ApiConstants.keyUpdate(id),
        body: dto.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          final key = key_models.Key.fromJson(response.data!);
          debugPrint('✅ [KEY_SERVICE] Chave atualizada com sucesso');
          
          return ApiResponse.success(
            data: key,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [KEY_SERVICE] Erro ao parsear chave atualizada: $e');
          debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar chave',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [KEY_SERVICE] Erro ao atualizar chave: $e');
      debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Exclui chave
  Future<ApiResponse<void>> deleteKey(String id) async {
    try {
      debugPrint('🔑 [KEY_SERVICE] Excluindo chave: $id');

      final response = await _apiService.delete<void>(
        ApiConstants.keyDelete(id),
      );

      if (response.success) {
        debugPrint('✅ [KEY_SERVICE] Chave excluída com sucesso');
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao excluir chave',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [KEY_SERVICE] Erro ao excluir chave: $e');
      debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Obtém estatísticas de chaves
  Future<ApiResponse<key_models.KeyStatistics>> getStatistics() async {
    try {
      debugPrint('🔑 [KEY_SERVICE] Buscando estatísticas...');

      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.keyStatistics,
      );

      if (response.success && response.data != null) {
        try {
          final statistics = key_models.KeyStatistics.fromJson(response.data!);
          debugPrint('✅ [KEY_SERVICE] Estatísticas carregadas');
          
          return ApiResponse.success(
            data: statistics,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [KEY_SERVICE] Erro ao parsear estatísticas: $e');
          debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
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
      debugPrint('❌ [KEY_SERVICE] Erro ao buscar estatísticas: $e');
      debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Retira chave (checkout)
  Future<ApiResponse<key_models.KeyControl>> checkoutKey(key_models.CreateKeyControlDto dto) async {
    try {
      debugPrint('🔑 [KEY_SERVICE] Retirando chave (checkout)...');
      
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.keyCheckout,
        body: dto.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          final control = key_models.KeyControl.fromJson(response.data!);
          debugPrint('✅ [KEY_SERVICE] Chave retirada com sucesso');
          
          return ApiResponse.success(
            data: control,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [KEY_SERVICE] Erro ao parsear controle: $e');
          debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao retirar chave',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [KEY_SERVICE] Erro ao retirar chave: $e');
      debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Devolve chave (return)
  Future<ApiResponse<key_models.KeyControl>> returnKey(
    String keyControlId,
    key_models.ReturnKeyDto dto,
  ) async {
    try {
      debugPrint('🔑 [KEY_SERVICE] Devolvendo chave: $keyControlId');
      
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.keyReturn(keyControlId),
        body: dto.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          final control = key_models.KeyControl.fromJson(response.data!);
          debugPrint('✅ [KEY_SERVICE] Chave devolvida com sucesso');
          
          return ApiResponse.success(
            data: control,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [KEY_SERVICE] Erro ao parsear controle: $e');
          debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao devolver chave',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [KEY_SERVICE] Erro ao devolver chave: $e');
      debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista todos os controles
  Future<ApiResponse<List<key_models.KeyControl>>> getAllControls({String? status}) async {
    try {
      debugPrint('🔑 [KEY_SERVICE] Buscando todos os controles...');
      
      final queryParams = status != null ? {'status': status} : null;

      final response = await _apiService.get<dynamic>(
        ApiConstants.keyControlsAll,
        queryParameters: queryParams,
      );

      if (response.success && response.data != null) {
        try {
          List<key_models.KeyControl> controls;
          
          if (response.data is List) {
            controls = (response.data as List)
                .map((e) => key_models.KeyControl.fromJson(e as Map<String, dynamic>))
                .toList();
          } else {
            controls = [];
          }

          debugPrint('✅ [KEY_SERVICE] ${controls.length} controles carregados');
          
          return ApiResponse.success(
            data: controls,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [KEY_SERVICE] Erro ao parsear controles: $e');
          debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar controles',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [KEY_SERVICE] Erro ao buscar controles: $e');
      debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista chaves em atraso
  Future<ApiResponse<List<key_models.KeyControl>>> getOverdueKeys() async {
    try {
      debugPrint('🔑 [KEY_SERVICE] Buscando chaves em atraso...');

      final response = await _apiService.get<dynamic>(
        ApiConstants.keyControlsOverdue,
      );

      if (response.success && response.data != null) {
        try {
          List<key_models.KeyControl> controls;
          
          if (response.data is List) {
            controls = (response.data as List)
                .map((e) => key_models.KeyControl.fromJson(e as Map<String, dynamic>))
                .toList();
          } else {
            controls = [];
          }

          debugPrint('✅ [KEY_SERVICE] ${controls.length} chaves em atraso');
          
          return ApiResponse.success(
            data: controls,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [KEY_SERVICE] Erro ao parsear chaves em atraso: $e');
          debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar chaves em atraso',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [KEY_SERVICE] Erro ao buscar chaves em atraso: $e');
      debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista controles do usuário logado
  Future<ApiResponse<List<key_models.KeyControl>>> getUserControls({String? status}) async {
    try {
      debugPrint('🔑 [KEY_SERVICE] Buscando controles do usuário...');
      
      final queryParams = status != null ? {'status': status} : null;

      final response = await _apiService.get<dynamic>(
        ApiConstants.keyControlsUser,
        queryParameters: queryParams,
      );

      if (response.success && response.data != null) {
        try {
          List<key_models.KeyControl> controls;
          
          if (response.data is List) {
            controls = (response.data as List)
                .map((e) => key_models.KeyControl.fromJson(e as Map<String, dynamic>))
                .toList();
          } else {
            controls = [];
          }

          debugPrint('✅ [KEY_SERVICE] ${controls.length} controles do usuário');
          
          return ApiResponse.success(
            data: controls,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [KEY_SERVICE] Erro ao parsear controles: $e');
          debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar controles do usuário',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [KEY_SERVICE] Erro ao buscar controles do usuário: $e');
      debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca controle por ID
  Future<ApiResponse<key_models.KeyControl>> getControlById(String id) async {
    try {
      debugPrint('🔑 [KEY_SERVICE] Buscando controle: $id');

      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.keyControlById(id),
      );

      if (response.success && response.data != null) {
        try {
          final control = key_models.KeyControl.fromJson(response.data!);
          debugPrint('✅ [KEY_SERVICE] Controle encontrado');
          
          return ApiResponse.success(
            data: control,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [KEY_SERVICE] Erro ao parsear controle: $e');
          debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar controle',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [KEY_SERVICE] Erro ao buscar controle: $e');
      debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca histórico de uma chave
  Future<ApiResponse<List<key_models.KeyHistoryRecord>>> getKeyHistory(
    String keyId, {
    int? limit,
  }) async {
    try {
      debugPrint('🔑 [KEY_SERVICE] Buscando histórico da chave: $keyId');
      
      final queryParams = limit != null ? {'limit': limit.toString()} : null;

      final response = await _apiService.get<dynamic>(
        ApiConstants.keyHistoryByKey(keyId),
        queryParameters: queryParams,
      );

      if (response.success && response.data != null) {
        try {
          List<key_models.KeyHistoryRecord> history;
          
          if (response.data is List) {
            history = (response.data as List)
                .map((e) => key_models.KeyHistoryRecord.fromJson(e as Map<String, dynamic>))
                .toList();
          } else {
            history = [];
          }

          debugPrint('✅ [KEY_SERVICE] ${history.length} registros de histórico');
          
          return ApiResponse.success(
            data: history,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [KEY_SERVICE] Erro ao parsear histórico: $e');
          debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar histórico: ${e.toString()}',
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
      debugPrint('❌ [KEY_SERVICE] Erro ao buscar histórico: $e');
      debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca histórico de um usuário
  Future<ApiResponse<List<key_models.KeyHistoryRecord>>> getUserHistory(
    String userId, {
    int? limit,
  }) async {
    try {
      debugPrint('🔑 [KEY_SERVICE] Buscando histórico do usuário: $userId');
      
      final queryParams = limit != null ? {'limit': limit.toString()} : null;

      final response = await _apiService.get<dynamic>(
        ApiConstants.keyHistoryByUser(userId),
        queryParameters: queryParams,
      );

      if (response.success && response.data != null) {
        try {
          List<key_models.KeyHistoryRecord> history;
          
          if (response.data is List) {
            history = (response.data as List)
                .map((e) => key_models.KeyHistoryRecord.fromJson(e as Map<String, dynamic>))
                .toList();
          } else {
            history = [];
          }

          debugPrint('✅ [KEY_SERVICE] ${history.length} registros de histórico');
          
          return ApiResponse.success(
            data: history,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [KEY_SERVICE] Erro ao parsear histórico: $e');
          debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar histórico: ${e.toString()}',
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
      debugPrint('❌ [KEY_SERVICE] Erro ao buscar histórico: $e');
      debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca histórico do usuário logado
  Future<ApiResponse<List<key_models.KeyHistoryRecord>>> getMyHistory({int? limit}) async {
    try {
      debugPrint('🔑 [KEY_SERVICE] Buscando meu histórico...');
      
      final queryParams = limit != null ? {'limit': limit.toString()} : null;

      final response = await _apiService.get<dynamic>(
        ApiConstants.keyHistoryMyHistory,
        queryParameters: queryParams,
      );

      if (response.success && response.data != null) {
        try {
          List<key_models.KeyHistoryRecord> history;
          
          if (response.data is List) {
            history = (response.data as List)
                .map((e) => key_models.KeyHistoryRecord.fromJson(e as Map<String, dynamic>))
                .toList();
          } else {
            history = [];
          }

          debugPrint('✅ [KEY_SERVICE] ${history.length} registros de histórico');
          
          return ApiResponse.success(
            data: history,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [KEY_SERVICE] Erro ao parsear histórico: $e');
          debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar histórico: ${e.toString()}',
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
      debugPrint('❌ [KEY_SERVICE] Erro ao buscar histórico: $e');
      debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca estatísticas do histórico
  Future<ApiResponse<key_models.KeyHistoryStatistics>> getHistoryStatistics({
    String? keyId,
    String? userId,
  }) async {
    try {
      debugPrint('🔑 [KEY_SERVICE] Buscando estatísticas do histórico...');
      
      final queryParams = <String, String>{};
      if (keyId != null) queryParams['keyId'] = keyId;
      if (userId != null) queryParams['userId'] = userId;

      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.keyHistoryStatistics,
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      if (response.success && response.data != null) {
        try {
          final statistics = key_models.KeyHistoryStatistics.fromJson(response.data!);
          debugPrint('✅ [KEY_SERVICE] Estatísticas do histórico carregadas');
          
          return ApiResponse.success(
            data: statistics,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [KEY_SERVICE] Erro ao parsear estatísticas: $e');
          debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar estatísticas: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar estatísticas do histórico',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [KEY_SERVICE] Erro ao buscar estatísticas: $e');
      debugPrint('📚 [KEY_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}

