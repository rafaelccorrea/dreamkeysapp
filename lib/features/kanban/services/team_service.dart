import 'package:flutter/foundation.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../models/kanban_models.dart';

/// Serviço para gerenciar times/equipes do Kanban
class TeamService {
  TeamService._();

  static final TeamService instance = TeamService._();
  final ApiService _apiService = ApiService.instance;

  /// Lista todos os times disponíveis
  Future<ApiResponse<List<KanbanTeam>>> getTeams() async {
    try {
      debugPrint('👥 [TEAM_SERVICE] ========== getTeams ==========');
      debugPrint('👥 [TEAM_SERVICE] Endpoint: ${ApiConstants.teams}');
      debugPrint('👥 [TEAM_SERVICE] URL completa: ${ApiConstants.baseApiUrl}${ApiConstants.teams}');
      
      final response = await _apiService.get<List<dynamic>>(
        ApiConstants.teams,
      );

      debugPrint('👥 [TEAM_SERVICE] Resposta getTeams:');
      debugPrint('👥 [TEAM_SERVICE]   - success: ${response.success}');
      debugPrint('👥 [TEAM_SERVICE]   - statusCode: ${response.statusCode}');
      debugPrint('👥 [TEAM_SERVICE]   - message: ${response.message}');
      debugPrint('👥 [TEAM_SERVICE]   - data: ${response.data?.length ?? 0} itens');

      if (response.success && response.data != null) {
        try {
          final teams = (response.data as List)
              .map((e) => KanbanTeam.fromJson(e as Map<String, dynamic>))
              .toList();
          
          debugPrint('👥 [TEAM_SERVICE] ✅ ${teams.length} times parseados');
          for (var i = 0; i < teams.length; i++) {
            final t = teams[i];
            debugPrint('👥 [TEAM_SERVICE]   [$i] ${t.name} (${t.id})');
          }
          
          return ApiResponse.success(
            data: teams,
            statusCode: response.statusCode,
          );
        } catch (e, stackTrace) {
          debugPrint('❌ [TEAM_SERVICE] Erro ao fazer parse: $e');
          debugPrint('📚 [TEAM_SERVICE] StackTrace: $stackTrace');
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
          );
        }
      }

      debugPrint('👥 [TEAM_SERVICE] ❌ Erro na resposta: ${response.message}');
      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar times',
        statusCode: response.statusCode,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [TEAM_SERVICE] ========== EXCEÇÃO em getTeams ==========');
      debugPrint('❌ [TEAM_SERVICE] Erro: $e');
      debugPrint('📚 [TEAM_SERVICE] StackTrace: $stackTrace');
      return ApiResponse.error(
        message: 'Erro ao listar times: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Obtém um time por ID
  Future<ApiResponse<KanbanTeam>> getTeamById(String id) async {
    try {
      debugPrint('👥 [TEAM_SERVICE] Obtendo time: $id');
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConstants.teamById(id),
      );

      if (response.success && response.data != null) {
        try {
          final team = KanbanTeam.fromJson(response.data!);
          return ApiResponse.success(
            data: team,
            statusCode: response.statusCode,
          );
        } catch (e) {
          return ApiResponse.error(
            message: 'Erro ao processar resposta',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao obter time',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [TEAM_SERVICE] Exceção ao obter time: $e');
      return ApiResponse.error(
        message: 'Erro ao obter time: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}



