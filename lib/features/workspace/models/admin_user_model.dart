import '../../../shared/utils/avatar_url_resolver.dart';

/// Modelo do usuário (admin) retornado pelos endpoints `/admin/users/*`.
///
/// Paridade com `imobx-front` `usersApi.ts` — campos cobertos:
/// `id`, `name`, `email`, `role`, `active`, `isActiveInCompany`,
/// `avatar`, `phone`, `document`, `hasAppAccess`, `lastLoginAt`,
/// `createdAt`, `updatedAt`.
class AdminUser {
  final String id;
  final String name;
  final String email;
  final String role;
  final bool active;
  final bool isActiveInCompany;
  final String? avatar;
  final String? phone;
  final String? document;
  final bool hasAppAccess;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// IDs das permissões atribuídas ao usuário. Populado por `GET
  /// /admin/users/:id` (a listagem compacta não traz — fica vazio).
  final List<String> permissionIds;

  /// IDs dos gestores responsáveis (apenas para corretores). Populado por
  /// `GET /admin/users/:id`.
  final List<String> managerIds;

  const AdminUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.active,
    required this.isActiveInCompany,
    this.avatar,
    this.phone,
    this.document,
    this.hasAppAccess = false,
    this.lastLoginAt,
    this.createdAt,
    this.updatedAt,
    this.permissionIds = const [],
    this.managerIds = const [],
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      final s = v.toString();
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    bool parseBool(dynamic v, {bool defaultValue = false}) {
      if (v == null) return defaultValue;
      if (v is bool) return v;
      final s = v.toString().toLowerCase();
      return s == 'true' || s == '1';
    }

    return AdminUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? 'user',
      active: parseBool(json['active'], defaultValue: true),
      isActiveInCompany: parseBool(
        json['isActiveInCompany'],
        defaultValue: true,
      ),
      avatar: AvatarUrlResolver.resolve(json['avatar']?.toString()),
      phone: (json['phone']?.toString() ?? '').isEmpty
          ? null
          : json['phone'].toString(),
      document: (json['document']?.toString() ?? '').isEmpty
          ? null
          : json['document'].toString(),
      hasAppAccess: parseBool(json['hasAppAccess']),
      lastLoginAt: parseDate(
        json['lastLoginAt'] ?? json['lastLogin'] ?? json['last_login'],
      ),
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
      permissionIds: _parsePermissionIds(json['permissions']),
      managerIds: _parseManagerIds(json),
    );
  }

  static List<String> _parseManagerIds(Map<String, dynamic> json) {
    final raw = json['managerIds'];
    if (raw is List) {
      final ids = raw
          .map((e) => e is Map ? e['id']?.toString() : e?.toString())
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toList();
      if (ids.isNotEmpty) return ids;
    }
    final single = json['managerId']?.toString();
    if (single != null && single.isNotEmpty) return [single];
    return const [];
  }

  static List<String> _parsePermissionIds(dynamic raw) {
    if (raw is! List) return const [];
    final ids = <String>[];
    for (final p in raw) {
      if (p is Map) {
        final id = p['id']?.toString();
        if (id != null && id.isNotEmpty) ids.add(id);
      } else if (p is String && p.isNotEmpty) {
        ids.add(p);
      }
    }
    return ids;
  }

  AdminUser copyWith({
    String? role,
    bool? active,
    bool? isActiveInCompany,
    bool? hasAppAccess,
    List<String>? permissionIds,
  }) {
    return AdminUser(
      id: id,
      name: name,
      email: email,
      role: role ?? this.role,
      active: active ?? this.active,
      isActiveInCompany: isActiveInCompany ?? this.isActiveInCompany,
      avatar: avatar,
      phone: phone,
      document: document,
      hasAppAccess: hasAppAccess ?? this.hasAppAccess,
      lastLoginAt: lastLoginAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      permissionIds: permissionIds ?? this.permissionIds,
    );
  }

  /// `true` quando o usuário nunca acessou o sistema (sem `lastLoginAt`).
  bool get neverLoggedIn => lastLoginAt == null;

  /// Label legível para o papel.
  String get roleLabel {
    switch (role.toLowerCase()) {
      case 'master':
        return 'Master';
      case 'admin':
        return 'Administrador';
      case 'manager':
        return 'Gestor';
      case 'user':
      default:
        return 'Corretor';
    }
  }
}

/// Resposta paginada de `/admin/users`.
class AdminUsersPage {
  final List<AdminUser> users;
  final int total;
  final int page;
  final int totalPages;

  const AdminUsersPage({
    required this.users,
    required this.total,
    required this.page,
    required this.totalPages,
  });

  factory AdminUsersPage.fromJson(Map<String, dynamic> json, int fallbackPage) {
    final raw = json['data'];
    final list = raw is List
        ? raw
              .map(
                (e) => AdminUser.fromJson(Map<String, dynamic>.from(e as Map)),
              )
              .toList()
        : <AdminUser>[];
    int parseInt(dynamic v, int fallback) {
      if (v == null) return fallback;
      if (v is int) return v;
      return int.tryParse(v.toString()) ?? fallback;
    }

    return AdminUsersPage(
      users: list,
      total: parseInt(json['total'], list.length),
      page: parseInt(json['page'], fallbackPage),
      totalPages: parseInt(json['totalPages'], 1),
    );
  }
}

/// Estatísticas para o hero de Usuários (`/admin/users/stats`).
class AdminUsersStats {
  final int total;
  final int regulars;
  final int admins;
  final int managers;
  final int newThisMonth;

  const AdminUsersStats({
    required this.total,
    required this.regulars,
    required this.admins,
    required this.managers,
    required this.newThisMonth,
  });

  factory AdminUsersStats.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      return int.tryParse(v.toString()) ?? 0;
    }

    // `usersByRole` é o breakdown por papel devolvido pelo backend
    // (`{ user, admin, master, manager }`). Quando os campos diretos
    // (`administrators`, `regulars`, `managers`) não vêm, derivamos a
    // contagem a partir desse mapa — mesma estratégia do
    // `imobx-front/UsersPage.tsx` `setStats(...)`.
    final usersByRole = json['usersByRole'];
    Map<String, dynamic>? roleMap;
    if (usersByRole is Map) {
      roleMap = Map<String, dynamic>.from(usersByRole);
    }
    final roleUser = parseInt(roleMap?['user']);
    final roleAdmin = parseInt(roleMap?['admin']);
    final roleMaster = parseInt(roleMap?['master']);
    final roleManager = parseInt(roleMap?['manager']);

    return AdminUsersStats(
      total: parseInt(json['totalUsers'] ?? json['total']),
      regulars:
          parseInt(json['regulars'] ?? json['users']) == 0 && roleMap != null
          ? roleUser
          : parseInt(json['regulars'] ?? json['users']),
      admins:
          parseInt(json['administrators'] ?? json['admins']) == 0 &&
              roleMap != null
          ? roleAdmin + roleMaster
          : parseInt(json['administrators'] ?? json['admins']),
      managers:
          parseInt(json['managers'] ?? json['gestores']) == 0 && roleMap != null
          ? roleManager
          : parseInt(json['managers'] ?? json['gestores']),
      newThisMonth: parseInt(
        json['newUsersThisMonth'] ?? json['newThisMonth'] ?? json['newUsers'],
      ),
    );
  }
}

/// Item do catálogo de permissões (`GET /permissions/by-category`).
class UserPermission {
  final String id;
  final String name;
  final String? description;
  final String category;

  const UserPermission({
    required this.id,
    required this.name,
    this.description,
    required this.category,
  });

  factory UserPermission.fromJson(Map<String, dynamic> json) {
    return UserPermission(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: (json['description']?.toString() ?? '').isEmpty
          ? null
          : json['description'].toString(),
      category: json['category']?.toString() ?? 'other',
    );
  }
}
