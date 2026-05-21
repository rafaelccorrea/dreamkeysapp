import 'package:flutter/foundation.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../models/admin_user_model.dart';

/// Service de Usuários (admin) — paridade com `imobx-front` `usersApi.ts`.
///
/// Cobre apenas o subset que a app móvel consome no momento:
///   • Listagem paginada/filtrada (`GET /admin/users`)
///   • Estatísticas do hero (`GET /admin/users/stats`)
///   • Ativar / desativar usuário (PATCH)
///
/// CRUD completo (create/update/delete, share, etc.) pode ser adicionado
/// quando as telas de criação/edição forem trazidas para o mobile.
class AdminUsersService {
  AdminUsersService._();
  static final AdminUsersService instance = AdminUsersService._();
  final ApiService _api = ApiService.instance;

  Future<ApiResponse<AdminUsersPage>> listUsers({
    int page = 1,
    int limit = 20,
    String? search,
    String? role,
    bool? active,
    bool? includeInactiveCompanyUsers,
    bool? hasAvatar,
    String? dateRange,
    bool? neverLoggedIn,
    String? lastLoginFrom,
    String? lastLoginTo,
    bool? onlyMyData,
    bool? allCompanyUsers,
    bool compact = false,
  }) async {
    try {
      final params = <String, String>{
        'page': '$page',
        'limit': '$limit',
        if (compact) 'compact': 'true',
      };
      if (search != null && search.trim().isNotEmpty) {
        params['search'] = search.trim();
      }
      if (role != null && role.trim().isNotEmpty) {
        params['role'] = role.trim();
      }
      if (active != null) {
        params['active'] = active.toString();
      }
      if (includeInactiveCompanyUsers == true) {
        params['includeInactiveCompanyUsers'] = 'true';
      }
      if (hasAvatar != null) {
        params['hasAvatar'] = hasAvatar.toString();
      }
      if (dateRange != null && dateRange.trim().isNotEmpty) {
        params['dateRange'] = dateRange.trim();
      }
      if (neverLoggedIn == true) {
        params['neverLoggedIn'] = 'true';
      }
      if (lastLoginFrom != null && lastLoginFrom.trim().isNotEmpty) {
        params['lastLoginFrom'] = lastLoginFrom.trim();
      }
      if (lastLoginTo != null && lastLoginTo.trim().isNotEmpty) {
        params['lastLoginTo'] = lastLoginTo.trim();
      }
      if (onlyMyData == true) {
        params['onlyMyData'] = 'true';
      }
      if (allCompanyUsers == true) {
        params['allCompanyUsers'] = 'true';
      }

      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.adminUsers,
        queryParameters: params,
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao listar usuários',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: AdminUsersPage.fromJson(res.data!, page),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [ADMIN_USERS] listUsers: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<AdminUsersStats>> getStats() async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.adminUsersStats,
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar estatísticas',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: AdminUsersStats.fromJson(res.data!),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [ADMIN_USERS] getStats: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<void>> setActive(String userId, bool active) async {
    try {
      final url = active
          ? ApiConstants.adminUserActivate(userId)
          : ApiConstants.adminUserDeactivate(userId);
      final res =
          await _api.patch<Map<String, dynamic>>(url, body: const {});
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao atualizar status',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: null, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [ADMIN_USERS] setActive: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }
}
