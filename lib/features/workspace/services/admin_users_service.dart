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

  static const String _jobLevelsPath = '/job-levels';
  static String _kanbanRedistributePath(String projectId) =>
      '/kanban/projects/$projectId/redistribute-leads';

  /// Valida disponibilidade de email (`GET /admin/users/validate/email`).
  /// Na edição, [excludeUserId] ignora o próprio usuário (paridade com
  /// `usersApi.validateEmail(email, user.id)` do web).
  Future<bool?> validateEmailAvailable(
    String email, {
    String? excludeUserId,
  }) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        '${ApiConstants.adminUsers}/validate/email',
        queryParameters: {
          'email': email.trim(),
          if (excludeUserId != null && excludeUserId.isNotEmpty)
            'excludeUserId': excludeUserId,
        },
      );
      if (!res.success || res.data == null) return null;
      final root = res.data!['data'] is Map
          ? Map<String, dynamic>.from(res.data!['data'] as Map)
          : res.data!;
      return root['available'] == true;
    } catch (e) {
      debugPrint('❌ [ADMIN_USERS] validateEmail: $e');
      return null;
    }
  }

  /// Valida disponibilidade de CPF/CNPJ (`GET /admin/users/validate/document`).
  Future<bool?> validateDocumentAvailable(String document) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        '${ApiConstants.adminUsers}/validate/document',
        queryParameters: {'document': document.trim()},
      );
      if (!res.success || res.data == null) return null;
      final root = res.data!['data'] is Map
          ? Map<String, dynamic>.from(res.data!['data'] as Map)
          : res.data!;
      return root['available'] == true;
    } catch (e) {
      debugPrint('❌ [ADMIN_USERS] validateDocument: $e');
      return null;
    }
  }

  /// Cria usuário (`POST /admin/users` — paridade com `usersApi.createUser`).
  /// `body` segue o `CreateUserData` do web: name, email, password, document,
  /// phone (só dígitos), role, permissionIds?, tagIds?, managerIds?.
  Future<ApiResponse<AdminUser>> createUser(Map<String, dynamic> body) async {
    try {
      final res = await _api.post<Map<String, dynamic>>(
        ApiConstants.adminUsers,
        body: body,
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao criar usuário',
          statusCode: res.statusCode,
        );
      }
      final root = res.data!['data'] is Map
          ? Map<String, dynamic>.from(res.data!['data'] as Map)
          : res.data!;
      return ApiResponse.success(
        data: AdminUser.fromJson(root),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [ADMIN_USERS] createUser: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

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

  /// Atualiza o usuário (`PUT /admin/users/:id`) — paridade com o
  /// `UpdateUserData` do web: name, email, phone, password (só quando
  /// informada), role, permissionIds, tagIds, managerIds, jobLevelId,
  /// reportsToUserId e isAvailableForPublicSite. Envia apenas os campos
  /// informados. Cargo/superior vão só com [includeHierarchy] (null limpa).
  Future<ApiResponse<void>> updateUser(
    String id, {
    String? role,
    List<String>? managerIds,
    List<String>? permissionIds,
    String? name,
    String? email,
    String? phone,
    String? password,
    List<String>? tagIds,
    bool? isAvailableForPublicSite,
    bool includeHierarchy = false,
    String? jobLevelId,
    String? reportsToUserId,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (email != null) body['email'] = email;
      if (phone != null) body['phone'] = phone;
      if (password != null && password.isNotEmpty) {
        body['password'] = password;
      }
      if (role != null) body['role'] = role;
      if (managerIds != null) body['managerIds'] = managerIds;
      if (permissionIds != null) body['permissionIds'] = permissionIds;
      if (tagIds != null) body['tagIds'] = tagIds;
      if (isAvailableForPublicSite != null) {
        body['isAvailableForPublicSite'] = isAvailableForPublicSite;
      }
      if (includeHierarchy) {
        body['jobLevelId'] = jobLevelId;
        body['reportsToUserId'] = reportsToUserId;
      }

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

  /// Desativa o usuário NESTA empresa (`PATCH /admin/users/:id/deactivate`)
  /// e devolve o `propertyReassignment` que o back calculou (imóveis que
  /// mudaram de responsável/captador) — o web mostra isso no toast final.
  Future<ApiResponse<DeactivateUserResult>> deactivateInCompany(
    String userId,
  ) async {
    try {
      final res = await _api.patch<Map<String, dynamic>>(
        ApiConstants.adminUserDeactivate(userId),
        body: const {},
      );
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao desativar usuário',
          statusCode: res.statusCode,
        );
      }
      final body = res.data ?? const <String, dynamic>{};
      final root = body['data'] is Map && body['propertyReassignment'] == null
          ? Map<String, dynamic>.from(body['data'] as Map)
          : body;
      return ApiResponse.success(
        data: DeactivateUserResult.fromJson(root),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [ADMIN_USERS] deactivateInCompany: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Prévia dos cards em aberto do usuário por funil
  /// (`GET /admin/users/:id/funnel-assignment-preview`).
  Future<ApiResponse<UserFunnelPreview>> getFunnelAssignmentPreview(
    String userId,
  ) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        '${ApiConstants.adminUsers}/$userId/funnel-assignment-preview',
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar a prévia do funil',
          statusCode: res.statusCode,
        );
      }
      final body = res.data!;
      final root = body['data'] is Map && body['projects'] == null
          ? Map<String, dynamic>.from(body['data'] as Map)
          : body;
      return ApiResponse.success(
        data: UserFunnelPreview.fromJson(root),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [ADMIN_USERS] getFunnelAssignmentPreview: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Redistribui os cards em aberto de [fromUserId] entre os membros do
  /// funil (`POST /kanban/projects/:id/redistribute-leads`, modo
  /// `team_members`, só leads abertos) — o mesmo corpo do
  /// `redistributeUserFunnelLeadsBeforeDeactivate` do web. Devolve quantos
  /// cards foram atualizados.
  Future<ApiResponse<int>> redistributeFunnelLeads(
    String projectId,
    String fromUserId,
  ) async {
    try {
      final res = await _api.post<Map<String, dynamic>>(
        _kanbanRedistributePath(projectId),
        body: {
          'fromUserId': fromUserId,
          'distributionMode': 'team_members',
          'onlyOpenLeads': true,
        },
      );
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao redistribuir leads do funil',
          statusCode: res.statusCode,
        );
      }
      final body = res.data ?? const <String, dynamic>{};
      final root = body['data'] is Map && body['updatedCount'] == null
          ? Map<String, dynamic>.from(body['data'] as Map)
          : body;
      final updated = root['updatedCount'];
      return ApiResponse.success(
        data: updated is num ? updated.toInt() : 0,
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [ADMIN_USERS] redistributeFunnelLeads: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Escada de cargos da empresa (`GET /job-levels`) — mesma fonte do
  /// `CargoESuperiorFields` do web.
  Future<ApiResponse<List<JobLevelOption>>> listJobLevels() async {
    try {
      final res = await _api.get<dynamic>(_jobLevelsPath);
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar cargos',
          statusCode: res.statusCode,
        );
      }
      final raw = res.data;
      final list = raw is List
          ? raw
          : (raw is Map && raw['data'] is List ? raw['data'] as List : const []);
      final out = list
          .whereType<Map>()
          .map((e) => JobLevelOption.fromJson(Map<String, dynamic>.from(e)))
          .where((l) => l.id.isNotEmpty)
          .toList()
        ..sort((a, b) => a.rank.compareTo(b.rank));
      return ApiResponse.success(data: out, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [ADMIN_USERS] listJobLevels: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Colegas da empresa para o campo "Superior direto"
  /// (`GET /admin/users?allCompanyUsers=true&limit=10000`, como o web).
  Future<ApiResponse<List<AdminUser>>> listCompanyColleagues() async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.adminUsers,
        queryParameters: const {
          'page': '1',
          'limit': '10000',
          'allCompanyUsers': 'true',
        },
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao listar usuários',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: AdminUsersPage.fromJson(res.data!, 1).users,
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [ADMIN_USERS] listCompanyColleagues: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }
}

/// Resultado do `PATCH /admin/users/:id/deactivate`.
class DeactivateUserResult {
  final int propertiesMainResponsibleUpdated;
  final int propertyResponsiblesRowsRemoved;
  final int propertyCaptorRowsRemoved;
  final int propertiesCapturedByIdUpdated;
  final bool hasReassignment;

  const DeactivateUserResult({
    this.propertiesMainResponsibleUpdated = 0,
    this.propertyResponsiblesRowsRemoved = 0,
    this.propertyCaptorRowsRemoved = 0,
    this.propertiesCapturedByIdUpdated = 0,
    this.hasReassignment = false,
  });

  factory DeactivateUserResult.fromJson(Map<String, dynamic> json) {
    final r = json['propertyReassignment'];
    if (r is! Map) return const DeactivateUserResult();
    int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return DeactivateUserResult(
      propertiesMainResponsibleUpdated: n(r['propertiesMainResponsibleUpdated']),
      propertyResponsiblesRowsRemoved: n(r['propertyResponsiblesRowsRemoved']),
      propertyCaptorRowsRemoved: n(r['propertyCaptorRowsRemoved']),
      propertiesCapturedByIdUpdated: n(r['propertiesCapturedByIdUpdated']),
      hasReassignment: true,
    );
  }

  /// Mesma frase do `buildDeactivateSuccessMessage` do web.
  String successMessage(String userName) {
    var msg = '$userName foi desativado nesta empresa.';
    if (!hasReassignment) return msg;
    final parts = <String>[
      if (propertiesMainResponsibleUpdated > 0)
        '$propertiesMainResponsibleUpdated imóvel(is) com novo responsável principal',
      if (propertyResponsiblesRowsRemoved > 0)
        '$propertyResponsiblesRowsRemoved vínculo(s) de co-responsável removido(s)',
      if (propertyCaptorRowsRemoved > 0)
        '$propertyCaptorRowsRemoved captador(es) removido(s)',
      if (propertiesCapturedByIdUpdated > 0)
        '$propertiesCapturedByIdUpdated imóvel(is) com captador atualizado',
    ];
    if (parts.isNotEmpty) msg += ' ${parts.join('; ')}.';
    return msg;
  }
}

/// Um funil da prévia de desativação.
class UserFunnelPreviewProject {
  final String projectId;
  final String projectName;
  final int openTaskCount;

  const UserFunnelPreviewProject({
    required this.projectId,
    required this.projectName,
    required this.openTaskCount,
  });
}

/// `GET /admin/users/:id/funnel-assignment-preview`.
class UserFunnelPreview {
  final int totalOpenTasks;
  final List<UserFunnelPreviewProject> projects;

  const UserFunnelPreview({
    this.totalOpenTasks = 0,
    this.projects = const [],
  });

  factory UserFunnelPreview.fromJson(Map<String, dynamic> json) {
    int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final projects = (json['projects'] is List ? json['projects'] as List : [])
        .whereType<Map>()
        .map((p) => UserFunnelPreviewProject(
              projectId: p['projectId']?.toString() ?? '',
              projectName: p['projectName']?.toString() ?? 'Funil',
              openTaskCount: n(p['openTaskCount']),
            ))
        .where((p) => p.projectId.isNotEmpty)
        .toList();
    return UserFunnelPreview(
      totalOpenTasks: n(json['totalOpenTasks']),
      projects: projects,
    );
  }
}

/// Degrau da escada de cargos (`GET /job-levels`).
class JobLevelOption {
  final String id;
  final String name;
  final int rank;

  const JobLevelOption({
    required this.id,
    required this.name,
    required this.rank,
  });

  factory JobLevelOption.fromJson(Map<String, dynamic> json) {
    final r = json['rank'];
    return JobLevelOption(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      rank: r is num ? r.toInt() : int.tryParse('$r') ?? 999,
    );
  }
}
