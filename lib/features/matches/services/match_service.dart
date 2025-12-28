import 'package:flutter/foundation.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../models/match_model.dart';

Map<String, dynamic> _convertToMap(dynamic value) {
  if (value == null) return <String, dynamic>{};
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

/// Serviço para gerenciar matches
class MatchService {
  MatchService._();

  static final MatchService instance = MatchService._();
  final ApiService _apiService = ApiService.instance;

  /// Lista matches com filtros
  Future<ApiResponse<MatchListResponse>> getMatches({
    MatchStatus? status,
    int? page,
    int? limit,
    String? propertyId,
    String? clientId,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (status != null) queryParams['status'] = status.value;
      if (page != null) queryParams['page'] = page.toString();
      if (limit != null) queryParams['limit'] = limit.toString();
      if (propertyId != null) queryParams['propertyId'] = propertyId;
      if (clientId != null) queryParams['clientId'] = clientId;

      final response = await _apiService.get<dynamic>(
        ApiConstants.matches,
        queryParameters: queryParams,
      );

      if (response.success && response.data != null) {
        try {
          MatchListResponse matchList;
          if (response.data is List) {
            matchList = MatchListResponse(
              matches: (response.data as List)
                  .map((e) => Match.fromJson(_convertToMap(e)))
                  .toList(),
              total: (response.data as List).length,
              page: page ?? 1,
              totalPages: 1,
            );
          } else if (response.data is Map) {
            Map<String, dynamic> dataMap;
            if (response.data is Map<String, dynamic>) {
              dataMap = response.data as Map<String, dynamic>;
            } else if (response.data is Map) {
              dataMap = Map<String, dynamic>.from(response.data as Map);
            } else {
              return ApiResponse<MatchListResponse>(
                success: false,
                message: 'Formato de resposta inválido',
                statusCode: response.statusCode ?? 400,
              );
            }
            matchList = MatchListResponse.fromJson(dataMap);
          } else {
          return ApiResponse<MatchListResponse>(
            success: false,
            message: 'Formato de resposta inválido',
            statusCode: response.statusCode ?? 400,
          );
          }

          return ApiResponse<MatchListResponse>(
            success: true,
            data: matchList,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [MATCH_SERVICE] Erro ao parsear matches: $e');
          return ApiResponse<MatchListResponse>(
            success: false,
            message: 'Erro ao processar resposta: $e',
            statusCode: response.statusCode ?? 500,
          );
        }
      }

      return ApiResponse<MatchListResponse>(
        success: false,
        message: response.message ?? 'Erro ao buscar matches',
        statusCode: response.statusCode ?? 500,
      );
    } catch (e) {
      debugPrint('❌ [MATCH_SERVICE] Erro ao buscar matches: $e');
      return ApiResponse<MatchListResponse>(
        success: false,
        message: 'Erro de conexão: $e',
        statusCode: 0,
      );
    }
  }

  /// Busca match por ID
  Future<ApiResponse<Match>> getMatchById(String matchId) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.matchById(matchId),
      );

      if (response.success && response.data != null) {
        return ApiResponse<Match>(
          success: true,
          data: Match.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }

      return ApiResponse<Match>(
        success: false,
        message: response.message ?? 'Erro ao buscar match',
        statusCode: response.statusCode ?? 500,
      );
    } catch (e) {
      debugPrint('❌ [MATCH_SERVICE] Erro ao buscar match: $e');
      return ApiResponse<Match>(
        success: false,
        message: 'Erro de conexão: $e',
        statusCode: 0,
      );
    }
  }

  /// Aceita um match
  Future<ApiResponse<AcceptMatchResponse>> acceptMatch(String matchId) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.matchAccept(matchId),
        body: {},
      );

      if (response.success && response.data != null) {
        return ApiResponse<AcceptMatchResponse>(
          success: true,
          data: AcceptMatchResponse.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }

      return ApiResponse<AcceptMatchResponse>(
        success: false,
        message: response.message ?? 'Erro ao aceitar match',
        statusCode: response.statusCode ?? 500,
      );
    } catch (e) {
      debugPrint('❌ [MATCH_SERVICE] Erro ao aceitar match: $e');
      return ApiResponse<AcceptMatchResponse>(
        success: false,
        message: 'Erro de conexão: $e',
        statusCode: 0,
      );
    }
  }

  /// Ignora um match
  Future<ApiResponse<IgnoreMatchResponse>> ignoreMatch(
    String matchId,
    IgnoreReason reason, {
    String? notes,
  }) async {
    try {
      final request = IgnoreMatchRequest(reason: reason, notes: notes);
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConstants.matchIgnore(matchId),
        body: request.toJson(),
      );

      if (response.success && response.data != null) {
        return ApiResponse<IgnoreMatchResponse>(
          success: true,
          data: IgnoreMatchResponse.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }

      return ApiResponse<IgnoreMatchResponse>(
        success: false,
        message: response.message ?? 'Erro ao ignorar match',
        statusCode: response.statusCode ?? 500,
      );
    } catch (e) {
      debugPrint('❌ [MATCH_SERVICE] Erro ao ignorar match: $e');
      return ApiResponse<IgnoreMatchResponse>(
        success: false,
        message: 'Erro de conexão: $e',
        statusCode: 0,
      );
    }
  }

  /// Marca match como visualizado
  Future<ApiResponse<void>> viewMatch(String matchId) async {
    try {
      final response = await _apiService.post<void>(
        ApiConstants.matchView(matchId),
        body: {},
      );

      return ApiResponse<void>(
        success: response.success,
        message: response.message,
        statusCode: response.statusCode ?? 200,
      );
    } catch (e) {
      debugPrint('❌ [MATCH_SERVICE] Erro ao marcar match como visualizado: $e');
      return ApiResponse<void>(
        success: false,
        message: 'Erro de conexão: $e',
        statusCode: 0,
      );
    }
  }

  /// Atualiza status do match
  Future<ApiResponse<Match>> updateMatchStatus(
    String matchId,
    MatchStatus status,
  ) async {
    try {
      final response = await _apiService.patch<Map<String, dynamic>>(
        ApiConstants.matchStatus(matchId),
        body: {'status': status.value},
      );

      if (response.success && response.data != null) {
        return ApiResponse<Match>(
          success: true,
          data: Match.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }

      return ApiResponse<Match>(
        success: false,
        message: response.message ?? 'Erro ao atualizar status',
        statusCode: response.statusCode ?? 500,
      );
    } catch (e) {
      debugPrint('❌ [MATCH_SERVICE] Erro ao atualizar status: $e');
      return ApiResponse<Match>(
        success: false,
        message: 'Erro de conexão: $e',
        statusCode: 0,
      );
    }
  }

  /// Busca resumo de matches
  Future<ApiResponse<MatchSummaryWithRecent>> getMatchesSummary() async {
    try {
      // Por enquanto, vamos buscar os matches e calcular o resumo
      // Futuramente pode ter um endpoint específico
      final matchesResponse = await getMatches(limit: 100);
      
      if (matchesResponse.success && matchesResponse.data != null) {
        final matches = matchesResponse.data!.matches;
        final summary = MatchSummaryWithRecent(
          total: matchesResponse.data!.total,
          pending: matches.where((m) => m.status == MatchStatus.pending).length,
          accepted: matches.where((m) => m.status == MatchStatus.accepted).length,
          ignored: matches.where((m) => m.status == MatchStatus.ignored).length,
          highScore: matches.where((m) => m.matchScore >= 80).length,
          recent: matches.take(5).toList(),
        );

        return ApiResponse<MatchSummaryWithRecent>(
          success: true,
          data: summary,
          statusCode: matchesResponse.statusCode ?? 200,
        );
      }

      return ApiResponse<MatchSummaryWithRecent>(
        success: false,
        message: matchesResponse.message ?? 'Erro ao buscar resumo',
        statusCode: matchesResponse.statusCode ?? 500,
      );
    } catch (e) {
      debugPrint('❌ [MATCH_SERVICE] Erro ao buscar resumo: $e');
      return ApiResponse<MatchSummaryWithRecent>(
        success: false,
        message: 'Erro de conexão: $e',
        statusCode: 0,
      );
    }
  }
}

