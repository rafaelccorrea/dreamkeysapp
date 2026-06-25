import 'package:flutter/foundation.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../models/commission_model.dart';

/// Serviço das Comissões — consome `/commissions` (paridade com
/// `commissionApi` do imobx-front). O backend já escopa por corretor: um
/// usuário comum só recebe as próprias comissões; master/admin veem todas.
class CommissionService {
  CommissionService._();

  static final CommissionService instance = CommissionService._();
  final ApiService _api = ApiService.instance;

  /// `GET /commissions` — lista paginada com filtros (status/paid/search).
  Future<ApiResponse<CommissionListResult>> getCommissions({
    CommissionFilters filters = const CommissionFilters(),
  }) async {
    try {
      final response = await _api.get<dynamic>(
        ApiConstants.commissions,
        queryParameters: filters.toQueryParams(),
      );
      if (response.success && response.data != null) {
        final raw = response.data;
        final result = raw is Map<String, dynamic>
            ? CommissionListResult.fromJson(raw)
            : raw is Map
                ? CommissionListResult.fromJson(
                    Map<String, dynamic>.from(raw))
                : raw is List
                    ? CommissionListResult(
                        commissions: raw
                            .whereType<Map>()
                            .map((e) => Commission.fromJson(
                                Map<String, dynamic>.from(e)))
                            .toList(),
                        total: raw.length,
                        page: 1,
                        limit: filters.limit,
                        totalPages: 1,
                      )
                    : CommissionListResult.empty;
        return ApiResponse.success(
          data: result,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar comissões',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [COMMISSION] getCommissions: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /commissions/statistics` — totais por status + valores agregados.
  Future<ApiResponse<CommissionStats>> getStatistics() async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        ApiConstants.commissionStatistics,
      );
      if (response.success && response.data != null) {
        final raw = response.data!;
        final body = raw['data'] is Map<String, dynamic>
            ? raw['data'] as Map<String, dynamic>
            : raw;
        return ApiResponse.success(
          data: CommissionStats.fromJson(body),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar estatísticas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [COMMISSION] getStatistics: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /commissions/:id` — detalhe de uma comissão.
  Future<ApiResponse<Commission>> getById(String id) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        ApiConstants.commissionById(id),
      );
      if (response.success && response.data != null) {
        final raw = response.data!;
        final body = raw['data'] is Map<String, dynamic>
            ? raw['data'] as Map<String, dynamic>
            : raw;
        return ApiResponse.success(
          data: Commission.fromJson(body),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Comissão não encontrada',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [COMMISSION] getById: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
