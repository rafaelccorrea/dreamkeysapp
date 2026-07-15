// Modelos da Hierarquia de gestores — espelham o `User` de
// `imobx-front/src/services/usersApi.ts` (campos usados pela HierarchyPage).

/// Papel do usuário (1:1 com o backend).
enum OrgUserRole {
  user,
  manager,
  admin,
  master,
  unknown;

  static OrgUserRole fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'user':
        return OrgUserRole.user;
      case 'manager':
        return OrgUserRole.manager;
      case 'admin':
        return OrgUserRole.admin;
      case 'master':
        return OrgUserRole.master;
      default:
        return OrgUserRole.unknown;
    }
  }

  /// Tradução pt-BR (paridade `roleTranslations` do web).
  String get label {
    switch (this) {
      case OrgUserRole.user:
        return 'Corretor';
      case OrgUserRole.manager:
        return 'Gestor';
      case OrgUserRole.admin:
        return 'Administrador';
      case OrgUserRole.master:
        return 'Master';
      case OrgUserRole.unknown:
        return 'Usuário';
    }
  }
}

/// Usuário da empresa com vínculo hierárquico (`managerId`).
class OrgUser {
  final String id;
  final String name;
  final String email;
  final OrgUserRole role;
  final String? avatar;
  final String? managerId;

  const OrgUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.avatar,
    this.managerId,
  });

  factory OrgUser.fromJson(Map<String, dynamic> json) {
    final managerId = json['managerId']?.toString();
    return OrgUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Sem nome',
      email: json['email']?.toString() ?? '',
      role: OrgUserRole.fromRaw(json['role']?.toString()),
      avatar: json['avatar']?.toString(),
      managerId: (managerId == null || managerId.isEmpty) ? null : managerId,
    );
  }
}
