import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/gamification_models.dart';

/// Serviço de Gamificação — consome `/gamification/*` (paridade com
/// `gamification.service.ts` do imobx-front). O backend envolve tudo em
/// `{ success, data }`, então aqui sempre desembrulhamos `data`.
class GamificationService {
  GamificationService._();

  static final GamificationService instance = GamificationService._();
  final ApiService _api = ApiService.instance;

  // Endpoints (paridade `gamification.controller.ts` do imobx).
  static const String _dashboard = '/gamification/dashboard';
  static const String _myAchievements = '/gamification/my-achievements';
  static const String _rankingsIndividual = '/gamification/rankings/individual';
  static const String _rankingsTeams = '/gamification/rankings/teams';
  static const String _leaderboard = '/gamification/leaderboard';
  static const String _config = '/gamification/config';

  Map<String, dynamic>? _unwrap(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final data = map['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return map;
  }

  List<dynamic> _unwrapList(dynamic raw) {
    if (raw is List) return raw;
    if (raw is Map) {
      final data = raw['data'];
      if (data is List) return data;
    }
    return const [];
  }

  /// `GET /gamification/dashboard?period=` — dashboard completo (meu score,
  /// conquistas recentes, top 5 + minha posição).
  Future<ApiResponse<GamificationDashboard>> getDashboard({
    ScorePeriod period = ScorePeriod.monthly,
  }) async {
    try {
      final response = await _api.get<dynamic>(
        _dashboard,
        queryParameters: {'period': period.value},
      );
      if (response.success && response.data != null) {
        final body = _unwrap(response.data);
        if (body != null) {
          return ApiResponse.success(
            data: GamificationDashboard.fromJson(body),
            statusCode: response.statusCode,
          );
        }
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar gamificação',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GAMIFICATION] getDashboard: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /gamification/rankings/individual?period=` — ranking completo.
  Future<ApiResponse<List<GamificationScore>>> getIndividualRankings({
    ScorePeriod period = ScorePeriod.monthly,
  }) async {
    try {
      final response = await _api.get<dynamic>(
        _rankingsIndividual,
        queryParameters: {'period': period.value},
      );
      if (response.success) {
        final list = _unwrapList(response.data)
            .whereType<Map>()
            .map((e) =>
                GamificationScore.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return ApiResponse.success(
          data: list,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar ranking',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GAMIFICATION] getIndividualRankings: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /gamification/rankings/teams?period=` — ranking de equipes.
  Future<ApiResponse<List<TeamScore>>> getTeamRankings({
    ScorePeriod period = ScorePeriod.monthly,
  }) async {
    try {
      final response = await _api.get<dynamic>(
        _rankingsTeams,
        queryParameters: {'period': period.value},
      );
      if (response.success) {
        final list = _unwrapList(response.data)
            .whereType<Map>()
            .map((e) => TeamScore.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return ApiResponse.success(
          data: list,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar ranking de equipes',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GAMIFICATION] getTeamRankings: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /gamification/my-achievements` — todas as minhas conquistas.
  Future<ApiResponse<List<UserAchievement>>> getMyAchievements() async {
    try {
      final response = await _api.get<dynamic>(_myAchievements);
      if (response.success) {
        final list = _unwrapList(response.data)
            .whereType<Map>()
            .map((e) => UserAchievement.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return ApiResponse.success(
          data: list,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar conquistas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GAMIFICATION] getMyAchievements: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /gamification/leaderboard?period=&limit=` — placar com top N.
  Future<ApiResponse<List<GamificationScore>>> getLeaderboard({
    ScorePeriod period = ScorePeriod.monthly,
    int limit = 10,
  }) async {
    try {
      final response = await _api.get<dynamic>(
        _leaderboard,
        queryParameters: {'period': period.value, 'limit': '$limit'},
      );
      if (response.success && response.data != null) {
        final body = _unwrap(response.data);
        final top = body?['topPerformers'];
        final list = top is List
            ? top
                .whereType<Map>()
                .map((e) =>
                    GamificationScore.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : <GamificationScore>[];
        return ApiResponse.success(
          data: list,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar placar',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GAMIFICATION] getLeaderboard: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /gamification/config` — configuração da empresa.
  Future<ApiResponse<GamificationConfig>> getConfig() async {
    try {
      final response = await _api.get<dynamic>(_config);
      if (response.success && response.data != null) {
        final body = _unwrap(response.data);
        if (body != null) {
          return ApiResponse.success(
            data: GamificationConfig.fromJson(body),
            statusCode: response.statusCode,
          );
        }
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar configuração',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GAMIFICATION] getConfig: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PUT /gamification/config` — atualiza a configuração.
  Future<ApiResponse<GamificationConfig>> updateConfig(
    GamificationConfig config,
  ) async {
    try {
      final response = await _api.put<dynamic>(
        _config,
        body: config.toUpdatePayload(),
      );
      if (response.success && response.data != null) {
        final body = _unwrap(response.data);
        if (body != null) {
          return ApiResponse.success(
            data: GamificationConfig.fromJson(body),
            statusCode: response.statusCode,
          );
        }
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao salvar configuração',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GAMIFICATION] updateConfig: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
