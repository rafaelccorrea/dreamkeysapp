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
      // Lista de colaboradores: desativados aparecem exceto filtro "só ativos"
      if (active != true) {
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

  /// Detalhe completo do usuário (`GET /admin/users/:id`) — inclui as
  /// permissões atribuídas (`permissionIds`). Lida com payload direto ou
  /// envelopado em `{ data: {...} }`.
  Future<ApiResponse<AdminUser>> getUserById(String id) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.adminUserById(id),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar usuário',
          statusCode: res.statusCode,
        );
      }
      final body = res.data!;
      final raw = body['data'] is Map
          ? Map<String, dynamic>.from(body['data'] as Map)
          : body;
      return ApiResponse.success(
        data: AdminUser.fromJson(raw),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [ADMIN_USERS] getUserById: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Catálogo de permissões agrupado por categoria
  /// (`GET /permissions/by-category`) → `{ categoria: [permissões] }`.
  Future<ApiResponse<Map<String, List<UserPermission>>>>
      getPermissionCatalog() async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.permissionsByCategory,
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar permissões',
          statusCode: res.statusCode,
        );
      }
      final body = res.data!;
      final map = body['data'] is Map
          ? Map<String, dynamic>.from(body['data'] as Map)
          : body;
      final out = <String, List<UserPermission>>{};
      map.forEach((category, value) {
        if (value is List) {
          out[category] = value
              .whereType<Map>()
              .map((e) =>
                  UserPermission.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      });
      return ApiResponse.success(data: out, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [ADMIN_USERS] getPermissionCatalog: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Atualiza papel / gestores / permissões do usuário (`PUT /admin/users/:id`).
  /// Envia apenas os campos informados. (Acesso ao app vai pelo endpoint
  /// dedicado [updateAppAccess], espelhando o web.)
  Future<ApiResponse<void>> updateUser(
    String id, {
    String? role,
    List<String>? managerIds,
    List<String>? permissionIds,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (role != null) body['role'] = role;
      if (managerIds != null) body['managerIds'] = managerIds;
      if (permissionIds != null) body['permissionIds'] = permissionIds;

      final res = await _api.put<Map<String, dynamic>>(
        ApiConstants.adminUserById(id),
        body: body,
      );
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao salvar alterações',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: null, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [ADMIN_USERS] updateUser: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  // Acesso ao app móvel é controlado por empresa (mobile_app_access_for_all)
  // no painel web — sem toggle individual por usuário no app.

  /// Lista gestores elegíveis (papéis manager + admin) para vincular a um
  /// corretor. Espelha o `ManagerMultiSelector` do web.
  Future<ApiResponse<List<AdminUser>>> listManagers({String? search}) async {
    try {
      final results = await Future.wait([
        listUsers(role: 'manager', limit: 100, search: search, compact: true),
        listUsers(role: 'admin', limit: 100, search: search, compact: true),
      ]);
      final merged = <String, AdminUser>{};
      for (final r in results) {
        if (r.success && r.data != null) {
          for (final u in r.data!.users) {
            merged[u.id] = u;
          }
        }
      }
      final list = merged.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return ApiResponse.success(data: list, statusCode: 200);
    } catch (e) {
      debugPrint('❌ [ADMIN_USERS] listManagers: $e');
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
