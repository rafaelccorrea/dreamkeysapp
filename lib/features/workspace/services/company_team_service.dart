import 'package:flutter/foundation.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../models/company_team_model.dart';

/// Service de Equipes da empresa — paridade com `imobx-front` `teamApi.ts`.
///
/// Cobre o que a app móvel consome no momento:
///   • Listagem filtrada/paginada (`GET /teams/filtered`).
///   • Detalhe (`GET /teams/:teamId`).
///   • Create / Update / Delete da equipe.
///   • Add / Remove de membros.
class CompanyTeamService {
  CompanyTeamService._();
  static final CompanyTeamService instance = CompanyTeamService._();
  final ApiService _api = ApiService.instance;

  Future<ApiResponse<CompanyTeamsPage>> listTeams({
    int page = 1,
    int limit = 12,
    String? search,
    String? teamName,
    String? memberName,
    String? tag,
    String? status, // 'active' | 'inactive' | 'all'
    String? color,
    String? dateRange,
    bool? onlyMyData,
  }) async {
    try {
      final params = <String, String>{
        'page': '$page',
        'limit': '$limit',
      };
      if (search != null && search.trim().isNotEmpty) {
        params['search'] = search.trim();
      }
      if (teamName != null && teamName.trim().isNotEmpty) {
        params['teamName'] = teamName.trim();
      }
      if (memberName != null && memberName.trim().isNotEmpty) {
        params['memberName'] = memberName.trim();
      }
      if (tag != null && tag.trim().isNotEmpty) {
        params['tag'] = tag.trim();
      }
      if (status != null && status.trim().isNotEmpty) {
        params['status'] = status.trim();
      }
      if (color != null && color.trim().isNotEmpty) {
        params['color'] = color.trim();
      }
      if (dateRange != null && dateRange.trim().isNotEmpty) {
        params['dateRange'] = dateRange.trim();
      }
      if (onlyMyData == true) {
        params['onlyMyData'] = 'true';
      }

      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.teamsFiltered,
        queryParameters: params,
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao listar equipes',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: CompanyTeamsPage.fromJson(res.data!, page),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [COMPANY_TEAMS] listTeams: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<CompanyTeam>> getTeam(String teamId) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.teamById(teamId),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao obter equipe',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: CompanyTeam.fromJson(res.data!),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [COMPANY_TEAMS] getTeam: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<CompanyTeam>> createTeam({
    required String name,
    String? description,
    required String color,
    List<Map<String, String>> members = const [],
  }) async {
    try {
      final body = <String, dynamic>{
        'name': name,
        'color': color,
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        if (members.isNotEmpty) 'members': members,
      };
      final res = await _api.post<Map<String, dynamic>>(
        ApiConstants.teams,
        body: body,
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao criar equipe',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: CompanyTeam.fromJson(res.data!),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [COMPANY_TEAMS] createTeam: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<CompanyTeam>> updateTeam({
    required String teamId,
    String? name,
    String? description,
    String? color,
    bool? isActive,
    bool? useInSaleForms,
    List<Map<String, String>>? members,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (description != null) body['description'] = description;
      if (color != null) body['color'] = color;
      if (isActive != null) body['isActive'] = isActive;
      if (useInSaleForms != null) body['useInSaleForms'] = useInSaleForms;
      if (members != null) body['members'] = members;

      final res = await _api.put<Map<String, dynamic>>(
        ApiConstants.teamById(teamId),
        body: body,
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao atualizar equipe',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: CompanyTeam.fromJson(res.data!),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [COMPANY_TEAMS] updateTeam: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<void>> deleteTeam(String teamId) async {
    try {
      final res = await _api.delete<dynamic>(
        ApiConstants.teamById(teamId),
      );
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao excluir equipe',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: null, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [COMPANY_TEAMS] deleteTeam: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<void>> addMember({
    required String teamId,
    required String userId,
    String role = 'member',
  }) async {
    try {
      final res = await _api.post<Map<String, dynamic>>(
        ApiConstants.teamMembers(teamId),
        body: {'userId': userId, 'role': role},
      );
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao adicionar membro',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: null, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [COMPANY_TEAMS] addMember: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<void>> removeMember({
    required String teamId,
    required String userId,
  }) async {
    try {
      final res = await _api.delete<dynamic>(
        ApiConstants.teamMemberByUser(teamId, userId),
      );
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao remover membro',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: null, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [COMPANY_TEAMS] removeMember: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }
}
