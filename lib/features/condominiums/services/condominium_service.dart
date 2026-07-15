import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/condominium_models.dart';

/// Serviço de Condomínios — consome `/condominiums` (paridade com
/// `condominiumApi` do imobx-front). Endpoints declarados como constantes
/// privadas; a migração para `ApiConstants` é da fiação central.
///
/// IMPORTANTE: o wizard de imóvel usa `PropertyService.listCondominiumsBrief`
/// para o seletor — este serviço é independente e não substitui aquele.
class CondominiumService {
  CondominiumService._();

  static final CondominiumService instance = CondominiumService._();
  final ApiService _api = ApiService.instance;

  static const String _base = '/condominiums';
  static String _byId(String id) => '$_base/$id';
  static const String _checkSimilarity = '$_base/check-similarity';

  /// `GET /condominiums` — lista paginada com filtros.
  Future<ApiResponse<CondominiumListResult>> getCondominiums({
    EstateListFilters filters = const EstateListFilters(),
  }) async {
    try {
      final response = await _api.get<dynamic>(
        _base,
        queryParameters: filters.toQueryParams(),
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: CondominiumListResult.fromRaw(response.data),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar condomínios',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [CONDOMINIUM] getCondominiums: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /condominiums/:id` — detalhe.
  Future<ApiResponse<Condominium>> getById(String id) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(_byId(id));
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: Condominium.fromJson(_unwrap(response.data!)),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Condomínio não encontrado',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [CONDOMINIUM] getById: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /condominiums` — criação (`CreateCondominiumDto`).
  Future<ApiResponse<Condominium>> create(Map<String, dynamic> payload) async {
    try {
      final response =
          await _api.post<Map<String, dynamic>>(_base, body: payload);
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: Condominium.fromJson(_unwrap(response.data!)),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar condomínio',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [CONDOMINIUM] create: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PATCH /condominiums/:id` — atualização (`UpdateCondominiumDto`).
  Future<ApiResponse<Condominium>> update(
    String id,
    Map<String, dynamic> payload,
  ) async {
    try {
      final response =
          await _api.patch<Map<String, dynamic>>(_byId(id), body: payload);
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: Condominium.fromJson(_unwrap(response.data!)),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar condomínio',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [CONDOMINIUM] update: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `DELETE /condominiums/:id`. O backend recusa quando há imóveis
  /// vinculados — a mensagem de erro é repassada para a UI.
  Future<ApiResponse<void>> deleteCondominium(String id) async {
    try {
      final response = await _api.delete<dynamic>(_byId(id));
      if (response.success) {
        return ApiResponse.success(data: null, statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao excluir condomínio',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [CONDOMINIUM] delete: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /condominiums/check-similarity?name=` — cadastros parecidos
  /// (aviso antes de criar duplicata).
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
      debugPrint('❌ [CONDOMINIUM] checkSimilarity: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Alguns endpoints embrulham o corpo em `{ data: {...} }`.
  static Map<String, dynamic> _unwrap(Map<String, dynamic> raw) {
    final inner = raw['data'];
    return inner is Map<String, dynamic> ? inner : raw;
  }
}
