import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/condominium_models.dart';
import '../models/development_models.dart';

/// Serviço de Empreendimentos — consome `/empreendimentos` (paridade com
/// `empreendimentoApi` do imobx-front). Endpoints declarados como constantes
/// privadas; a migração para `ApiConstants` é da fiação central.
class DevelopmentService {
  DevelopmentService._();

  static final DevelopmentService instance = DevelopmentService._();
  final ApiService _api = ApiService.instance;

  static const String _base = '/empreendimentos';
  static String _byId(String id) => '$_base/$id';
  static const String _checkSimilarity = '$_base/check-similarity';

  /// `GET /empreendimentos` — lista paginada com filtros.
  Future<ApiResponse<DevelopmentListResult>> getDevelopments({
    EstateListFilters filters = const EstateListFilters(),
  }) async {
    try {
      final response = await _api.get<dynamic>(
        _base,
        queryParameters: filters.toQueryParams(),
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: DevelopmentListResult.fromRaw(response.data),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar empreendimentos',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [DEVELOPMENT] getDevelopments: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /empreendimentos/:id` — detalhe.
  Future<ApiResponse<Development>> getById(String id) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(_byId(id));
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: Development.fromJson(_unwrap(response.data!)),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Empreendimento não encontrado',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [DEVELOPMENT] getById: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /empreendimentos` — criação (`CreateEmpreendimentoDto`).
  Future<ApiResponse<Development>> create(Map<String, dynamic> payload) async {
    try {
      final response =
          await _api.post<Map<String, dynamic>>(_base, body: payload);
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: Development.fromJson(_unwrap(response.data!)),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar empreendimento',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [DEVELOPMENT] create: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PATCH /empreendimentos/:id` — atualização (`UpdateEmpreendimentoDto`).
  Future<ApiResponse<Development>> update(
    String id,
    Map<String, dynamic> payload,
  ) async {
    try {
      final response =
          await _api.patch<Map<String, dynamic>>(_byId(id), body: payload);
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: Development.fromJson(_unwrap(response.data!)),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar empreendimento',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [DEVELOPMENT] update: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `DELETE /empreendimentos/:id`.
  Future<ApiResponse<void>> deleteDevelopment(String id) async {
    try {
      final response = await _api.delete<dynamic>(_byId(id));
      if (response.success) {
        return ApiResponse.success(data: null, statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao excluir empreendimento',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [DEVELOPMENT] delete: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /empreendimentos/check-similarity?name=`.
  Future<ApiResponse<SimilarityResult>> checkSimilarity(String name) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        _checkSimilarity,
        queryParameters: {'name': name},
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: SimilarityResult.fromJson(_unwrap(response.data!)),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao verificar similaridade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [DEVELOPMENT] checkSimilarity: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  static Map<String, dynamic> _unwrap(Map<String, dynamic> raw) {
    final inner = raw['data'];
    return inner is Map<String, dynamic> ? inner : raw;
  }
}
