import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/goal_model.dart';

/// Serviço de Metas — consome `/goals` (paridade com `goalsApi` do
/// imobx-front / `goals.controller.ts` do backend). Todas as rotas exigem
/// JWT + X-Company-ID (automáticos via [ApiService]). O acesso à tela é
/// restrito a admin/master (AdminRoute no web).
class GoalService {
  GoalService._();

  static final GoalService instance = GoalService._();
  final ApiService _api = ApiService.instance;

  // Endpoints privados — a migração para `api_constants.dart` é feita pela
  // fiação central (ver manifest).
  static const String _goals = '/goals';
  static const String _goalFilterOptions = '/goals/filters/options';
  static String _goalById(String id) => '/goals/$id';
  static String _goalAnalytics(String id) => '/goals/$id/analytics';
  static String _goalDuplicate(String id) => '/goals/$id/duplicate';
  static String _goalRefresh(String id) => '/goals/$id/refresh';

  // Fontes dos selects de responsável (mesmos endpoints dos hooks
  // `useUsers`/`useTeams` do web).
  static const String _adminUsers = '/admin/users';
  static const String _teams = '/teams';

  Map<String, dynamic> _unwrap(Map<String, dynamic> raw) {
    final data = raw['data'];
    return data is Map<String, dynamic> ? data : raw;
  }

  /// `GET /goals` — lista com filtros + estatísticas agregadas.
  Future<ApiResponse<GoalsListResult>> listGoals({
    GoalFilters filters = GoalFilters.none,
  }) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        _goals,
        queryParameters: filters.toQueryParams(),
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: GoalsListResult.fromJson(_unwrap(response.data!)),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar metas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GOALS] listGoals: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /goals/:id` — detalhe de uma meta.
  Future<ApiResponse<Goal>> getGoalById(String id) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(_goalById(id));
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: Goal.fromJson(_unwrap(response.data!)),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Meta não encontrada',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GOALS] getGoalById: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /goals` — cria meta. O backend exige `startDate`/`endDate`
  /// (ISO); valida `userId` para escopo user e `teamId` para escopo team.
  Future<ApiResponse<Goal>> createGoal({
    required String title,
    String? description,
    required GoalType type,
    required GoalPeriod period,
    required GoalScope scope,
    required double targetValue,
    required DateTime startDate,
    required DateTime endDate,
    String? userId,
    String? teamId,
    String? color,
    String? icon,
  }) async {
    try {
      final body = <String, dynamic>{
        'title': title,
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        'type': type.apiValue,
        'period': period.apiValue,
        'scope': scope.apiValue,
        'targetValue': targetValue,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        if (userId != null && userId.isNotEmpty) 'userId': userId,
        if (teamId != null && teamId.isNotEmpty) 'teamId': teamId,
        if (color != null && color.isNotEmpty) 'color': color,
        if (icon != null && icon.isNotEmpty) 'icon': icon,
      };
      final response = await _api.post<Map<String, dynamic>>(
        _goals,
        body: body,
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: Goal.fromJson(_unwrap(response.data!)),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar meta',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GOALS] createGoal: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `PUT /goals/:id` — atualiza meta (campos do `UpdateGoalDto`; tipo,
  /// período e escopo não são editáveis — paridade com EditGoalPage web).
  Future<ApiResponse<Goal>> updateGoal({
    required String id,
    String? title,
    String? description,
    double? targetValue,
    GoalStatus? status,
    bool? isActive,
    String? color,
    String? icon,
  }) async {
    try {
      final body = <String, dynamic>{
        'title': ?title,
        'description': ?description,
        'targetValue': ?targetValue,
        'status': ?status?.apiValue,
        'isActive': ?isActive,
        'color': ?color,
        'icon': ?icon,
      };
      final response = await _api.put<Map<String, dynamic>>(
        _goalById(id),
        body: body,
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: Goal.fromJson(_unwrap(response.data!)),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar meta',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GOALS] updateGoal: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `DELETE /goals/:id` — exclui a meta.
  Future<ApiResponse<void>> deleteGoal(String id) async {
    try {
      final response = await _api.delete<Map<String, dynamic>>(_goalById(id));
      if (response.success) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao excluir meta',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GOALS] deleteGoal: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /goals/:id/duplicate` — duplica a meta para o próximo período.
  Future<ApiResponse<Goal>> duplicateGoal(String id) async {
    try {
      final response =
          await _api.post<Map<String, dynamic>>(_goalDuplicate(id));
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: Goal.fromJson(_unwrap(response.data!)),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao duplicar meta',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GOALS] duplicateGoal: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /goals/:id/refresh` — força atualização do progresso.
  Future<ApiResponse<void>> refreshGoalProgress(String id) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(_goalRefresh(id));
      if (response.success) {
        return ApiResponse.success(statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar progresso',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GOALS] refreshGoalProgress: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /goals/:id/analytics` — análise detalhada (KPIs + histórico).
  Future<ApiResponse<GoalAnalytics>> getGoalAnalytics(String id) async {
    try {
      final response =
          await _api.get<Map<String, dynamic>>(_goalAnalytics(id));
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: GoalAnalytics.fromJson(_unwrap(response.data!)),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar análise da meta',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GOALS] getGoalAnalytics: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /goals/filters/options` — equipes/corretores que POSSUEM metas
  /// (para popular os filtros da listagem).
  Future<ApiResponse<GoalFormOptions>> getFilterOptions() async {
    try {
      final response =
          await _api.get<Map<String, dynamic>>(_goalFilterOptions);
      if (response.success && response.data != null) {
        final body = _unwrap(response.data!);
        return ApiResponse.success(
          data: GoalFormOptions(
            users: _parseOptions(body['users']),
            teams: _parseOptions(body['teams']),
          ),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar opções de filtro',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [GOALS] getFilterOptions: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Opções do FORMULÁRIO (corretores + equipes da empresa) — mesmos
  /// endpoints dos hooks `useUsers` (`/admin/users`) e `useTeams` (`/teams`)
  /// usados pelo NewGoalPage do web. Falha de uma fonte não derruba a outra.
  Future<ApiResponse<GoalFormOptions>> getFormOptions() async {
    try {
      final results = await Future.wait([
        _api.get<Map<String, dynamic>>(
          _adminUsers,
          queryParameters: const {'page': '1', 'limit': '1000'},
        ),
        _api.get<dynamic>(_teams),
      ]);

      final usersRes = results[0];
      final teamsRes = results[1];

      var users = <GoalOption>[];
      if (usersRes.success && usersRes.data != null) {
        final body = _unwrap(usersRes.data! as Map<String, dynamic>);
        users = _parseOptions(body['data'] ?? body['users']);
      }

      var teams = <GoalOption>[];
      if (teamsRes.success && teamsRes.data != null) {
        final raw = teamsRes.data;
        if (raw is List) {
          teams = _parseOptions(raw);
        } else if (raw is Map) {
          final body = Map<String, dynamic>.from(raw);
          teams = _parseOptions(body['data'] ?? body['teams']);
        }
      }

      return ApiResponse.success(
        data: GoalFormOptions(users: users, teams: teams),
        statusCode: 200,
      );
    } catch (e) {
      debugPrint('❌ [GOALS] getFormOptions: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  List<GoalOption> _parseOptions(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => GoalOption.fromJson(Map<String, dynamic>.from(e)))
        .where((o) => o.id.isNotEmpty && o.name.isNotEmpty)
        .toList();
  }
}
