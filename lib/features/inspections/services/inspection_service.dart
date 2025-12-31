import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../models/inspection_model.dart';

/// Serviço para gerenciar vistorias
class InspectionService {
  InspectionService._();

  static final InspectionService instance = InspectionService._();
  final ApiService _apiService = ApiService.instance;

  /// Lista vistorias com filtros
  Future<ApiResponse<InspectionListResponse>> listInspections({
    InspectionFilters? filters,
  }) async {
    try {
      debugPrint('🔍 [INSPECTION_SERVICE] Buscando vistorias...');
      
      final queryParams = filters?.toQueryParams() ?? <String, String>{};
      
      debugPrint('🔍 [INSPECTION_SERVICE] Filtros: $queryParams');
      
      final response = await _apiService.get<dynamic>(
        ApiConstants.inspections,
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );

      debugPrint('🔍 [INSPECTION_SERVICE] Resposta recebida:');
      debugPrint('   - Success: ${response.success}');
      debugPrint('   - Status Code: ${response.statusCode}');

      if (response.success && response.data != null) {
        try {
          InspectionListResponse listResponse;
          
          // Verificar se a resposta é uma lista direta ou um objeto com paginação
          if (response.data is List) {
            debugPrint('🔍 [INSPECTION_SERVICE] Resposta é uma lista direta');
            final inspections = (response.data as List)
                .map((e) => Inspection.fromJson(e as Map<String, dynamic>))
                .toList();

            listResponse = InspectionListResponse(
              inspections: inspections,
              total: inspections.length,
              page: filters?.page ?? 1,
              limit: filters?.limit ?? 20,
              totalPages: 1,
            );
          } else if (response.data is Map<String, dynamic>) {
            debugPrint('🔍 [INSPECTION_SERVICE] Resposta é um objeto com estrutura');
            listResponse = InspectionListResponse.fromJson(
              response.data as Map<String, dynamic>,
            );
          } else {
            throw Exception('Formato de resposta não reconhecido');
          }

          debugPrint('✅ [INSPECTION_SERVICE] ${listResponse.inspections.length} vistorias carregadas');
          
          return ApiResponse.success(
            data: listResponse,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [INSPECTION_SERVICE] Erro ao parsear lista de vistorias: $e');
          debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados das vistorias: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar vistorias',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [INSPECTION_SERVICE] Erro ao buscar vistorias: $e');
      debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca vistoria por ID
  Future<ApiResponse<Inspection>> getInspectionById(String id) async {
    try {
      debugPrint('🔍 [INSPECTION_SERVICE] Buscando vistoria: $id');
      
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.inspectionById(id),
      );

      if (response.success && response.data != null) {
        try {
          final inspection = Inspection.fromJson(response.data!);
          debugPrint('✅ [INSPECTION_SERVICE] Vistoria carregada: ${inspection.title}');
          
          return ApiResponse.success(
            data: inspection,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [INSPECTION_SERVICE] Erro ao parsear vistoria: $e');
          debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados da vistoria: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar vistoria',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [INSPECTION_SERVICE] Erro ao buscar vistoria: $e');
      debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Cria uma nova vistoria
  Future<ApiResponse<Inspection>> createInspection(CreateInspectionDto data) async {
    try {
      debugPrint('➕ [INSPECTION_SERVICE] Criando vistoria: ${data.title}');
      
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.inspections,
        body: data.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          final inspection = Inspection.fromJson(response.data!);
          debugPrint('✅ [INSPECTION_SERVICE] Vistoria criada: ${inspection.id}');
          
          return ApiResponse.success(
            data: inspection,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [INSPECTION_SERVICE] Erro ao parsear vistoria criada: $e');
          debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar vistoria',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [INSPECTION_SERVICE] Erro ao criar vistoria: $e');
      debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Atualiza uma vistoria
  Future<ApiResponse<Inspection>> updateInspection(
    String id,
    UpdateInspectionDto data,
  ) async {
    try {
      debugPrint('✏️ [INSPECTION_SERVICE] Atualizando vistoria: $id');
      
      final response = await _apiService.put<Map<String, dynamic>>(
        ApiConstants.inspectionUpdate(id),
        body: data.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          final inspection = Inspection.fromJson(response.data!);
          debugPrint('✅ [INSPECTION_SERVICE] Vistoria atualizada: ${inspection.title}');
          
          return ApiResponse.success(
            data: inspection,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [INSPECTION_SERVICE] Erro ao parsear vistoria atualizada: $e');
          debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar vistoria',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [INSPECTION_SERVICE] Erro ao atualizar vistoria: $e');
      debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Exclui uma vistoria
  Future<ApiResponse<void>> deleteInspection(String id) async {
    try {
      debugPrint('🗑️ [INSPECTION_SERVICE] Excluindo vistoria: $id');
      
      final response = await _apiService.delete<void>(
        ApiConstants.inspectionDelete(id),
      );

      if (response.success) {
        debugPrint('✅ [INSPECTION_SERVICE] Vistoria excluída com sucesso');
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao excluir vistoria',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [INSPECTION_SERVICE] Erro ao excluir vistoria: $e');
      debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista vistorias de uma propriedade
  Future<ApiResponse<List<Inspection>>> getInspectionsByProperty(
    String propertyId,
  ) async {
    try {
      debugPrint('🏠 [INSPECTION_SERVICE] Buscando vistorias da propriedade: $propertyId');
      
      final response = await _apiService.get<dynamic>(
        ApiConstants.inspectionByProperty(propertyId),
      );

      if (response.success && response.data != null) {
        try {
          List<Inspection> inspections = [];
          
          if (response.data is List) {
            final dataList = response.data as List<dynamic>;
            inspections = dataList
                .map((e) {
                  try {
                    return Inspection.fromJson(e as Map<String, dynamic>);
                  } catch (e) {
                    debugPrint('❌ [INSPECTION_SERVICE] Erro ao parsear vistoria: $e');
                    return null;
                  }
                })
                .whereType<Inspection>()
                .toList();
          } else if (response.data is Map<String, dynamic>) {
            final dataMap = response.data as Map<String, dynamic>;
            if (dataMap['data'] is List) {
              final dataList = dataMap['data'] as List<dynamic>;
              inspections = dataList
                  .map((e) {
                    try {
                      return Inspection.fromJson(e as Map<String, dynamic>);
                    } catch (e) {
                      return null;
                    }
                  })
                  .whereType<Inspection>()
                  .toList();
            }
          }
          
          debugPrint('✅ [INSPECTION_SERVICE] ${inspections.length} vistorias encontradas');
          
          return ApiResponse.success(
            data: inspections,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [INSPECTION_SERVICE] Erro ao parsear vistorias: $e');
          debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados das vistorias: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar vistorias da propriedade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [INSPECTION_SERVICE] Erro ao buscar vistorias da propriedade: $e');
      debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista vistorias de um vistoriador
  Future<ApiResponse<List<Inspection>>> getInspectionsByInspector(
    String inspectorId,
  ) async {
    try {
      debugPrint('👤 [INSPECTION_SERVICE] Buscando vistorias do vistoriador: $inspectorId');
      
      final response = await _apiService.get<dynamic>(
        ApiConstants.inspectionByInspector(inspectorId),
      );

      if (response.success && response.data != null) {
        try {
          List<Inspection> inspections = [];
          
          if (response.data is List) {
            final dataList = response.data as List<dynamic>;
            inspections = dataList
                .map((e) {
                  try {
                    return Inspection.fromJson(e as Map<String, dynamic>);
                  } catch (e) {
                    debugPrint('❌ [INSPECTION_SERVICE] Erro ao parsear vistoria: $e');
                    return null;
                  }
                })
                .whereType<Inspection>()
                .toList();
          }
          
          debugPrint('✅ [INSPECTION_SERVICE] ${inspections.length} vistorias encontradas');
          
          return ApiResponse.success(
            data: inspections,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [INSPECTION_SERVICE] Erro ao parsear vistorias: $e');
          debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar dados das vistorias: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar vistorias do vistoriador',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [INSPECTION_SERVICE] Erro ao buscar vistorias do vistoriador: $e');
      debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Faz upload de foto para uma vistoria
  Future<ApiResponse<Inspection>> uploadPhoto(String id, File file) async {
    try {
      debugPrint('📸 [INSPECTION_SERVICE] Fazendo upload de foto para vistoria: $id');
      
      final token = await SecureStorageService.instance.getAccessToken();
      if (token == null || token.isEmpty) {
        return ApiResponse.error(
          message: 'Token de autenticação não encontrado',
          statusCode: 401,
        );
      }

      final uri = Uri.parse(
        '${ApiConstants.baseApiUrl}${ApiConstants.inspectionUploadPhoto(id)}',
      );
      final request = http.MultipartRequest('POST', uri);

      // Headers
      request.headers['Authorization'] = 'Bearer $token';
      
      final companyId = await SecureStorageService.instance.getCompanyId();
      if (companyId != null) {
        request.headers['X-Company-ID'] = companyId;
      }
      
      // Adicionar arquivo
      final fileStream = http.ByteStream(file.openRead());
      final fileLength = await file.length();
      final multipartFile = http.MultipartFile(
        'file',
        fileStream,
        fileLength,
        filename: file.path.split('/').last.split('\\').last,
      );
      request.files.add(multipartFile);

      debugPrint('📤 [INSPECTION_SERVICE] Enviando arquivo: ${file.path}');
      
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
          final inspection = Inspection.fromJson(jsonData);
          debugPrint('✅ [INSPECTION_SERVICE] Foto enviada com sucesso');
          return ApiResponse.success(
            data: inspection,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [INSPECTION_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar resposta: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      String errorMessage = 'Erro ao fazer upload da foto';
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
    } catch (e, stackTrace) {
      debugPrint('❌ [INSPECTION_SERVICE] Erro ao fazer upload da foto: $e');
      debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Remove uma foto de uma vistoria
  Future<ApiResponse<Inspection>> removePhoto(String id, String photoUrl) async {
    try {
      debugPrint('🗑️ [INSPECTION_SERVICE] Removendo foto da vistoria: $id');
      
      final response = await _apiService.delete<Map<String, dynamic>>(
        ApiConstants.inspectionDeletePhoto(id, photoUrl),
      );

      if (response.success && response.data != null) {
        try {
          final inspection = Inspection.fromJson(response.data!);
          debugPrint('✅ [INSPECTION_SERVICE] Foto removida com sucesso');
          
          return ApiResponse.success(
            data: inspection,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [INSPECTION_SERVICE] Erro ao parsear resposta: $e');
          debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao remover foto',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [INSPECTION_SERVICE] Erro ao remover foto: $e');
      debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Solicita aprovação financeira
  Future<ApiResponse<Map<String, dynamic>>> requestApproval(
    CreateInspectionApprovalDto data,
  ) async {
    try {
      debugPrint('💰 [INSPECTION_SERVICE] Solicitando aprovação financeira');
      
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.inspectionApprovals,
        body: data.toJson(),
      );

      if (response.success && response.data != null) {
        debugPrint('✅ [INSPECTION_SERVICE] Aprovação solicitada com sucesso');
        return ApiResponse.success(
          data: response.data!,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao solicitar aprovação',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [INSPECTION_SERVICE] Erro ao solicitar aprovação: $e');
      debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista histórico de uma vistoria
  Future<ApiResponse<List<InspectionHistoryEntry>>> getHistory(String id) async {
    try {
      debugPrint('📜 [INSPECTION_SERVICE] Buscando histórico da vistoria: $id');
      
      final response = await _apiService.get<dynamic>(
        ApiConstants.inspectionHistory(id),
      );

      if (response.success && response.data != null) {
        try {
          List<InspectionHistoryEntry> history = [];
          
          if (response.data is List) {
            final dataList = response.data as List<dynamic>;
            history = dataList
                .map((e) {
                  try {
                    return InspectionHistoryEntry.fromJson(e as Map<String, dynamic>);
                  } catch (e) {
                    debugPrint('❌ [INSPECTION_SERVICE] Erro ao parsear entrada do histórico: $e');
                    return null;
                  }
                })
                .whereType<InspectionHistoryEntry>()
                .toList();
          }
          
          debugPrint('✅ [INSPECTION_SERVICE] ${history.length} entradas do histórico carregadas');
          
          return ApiResponse.success(
            data: history,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [INSPECTION_SERVICE] Erro ao parsear histórico: $e');
          debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
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
      debugPrint('❌ [INSPECTION_SERVICE] Erro ao buscar histórico: $e');
      debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Adiciona entrada ao histórico
  Future<ApiResponse<InspectionHistoryEntry>> addHistoryEntry(
    String id,
    CreateInspectionHistoryDto data,
  ) async {
    try {
      debugPrint('➕ [INSPECTION_SERVICE] Adicionando entrada ao histórico da vistoria: $id');
      
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.inspectionHistory(id),
        body: data.toJson(),
      );

      if (response.success && response.data != null) {
        try {
          final entry = InspectionHistoryEntry.fromJson(response.data!);
          debugPrint('✅ [INSPECTION_SERVICE] Entrada adicionada ao histórico');
          
          return ApiResponse.success(
            data: entry,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [INSPECTION_SERVICE] Erro ao parsear entrada do histórico: $e');
          debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao adicionar entrada ao histórico',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [INSPECTION_SERVICE] Erro ao adicionar entrada ao histórico: $e');
      debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Remove entrada do histórico
  Future<ApiResponse<void>> removeHistoryEntry(String id, String historyId) async {
    try {
      debugPrint('🗑️ [INSPECTION_SERVICE] Removendo entrada do histórico: $historyId');
      
      final response = await _apiService.delete<void>(
        ApiConstants.inspectionHistoryEntry(id, historyId),
      );

      if (response.success) {
        debugPrint('✅ [INSPECTION_SERVICE] Entrada removida do histórico com sucesso');
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao remover entrada do histórico',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [INSPECTION_SERVICE] Erro ao remover entrada do histórico: $e');
      debugPrint('📚 [INSPECTION_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
