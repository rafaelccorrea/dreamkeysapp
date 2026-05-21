import '../../../shared/utils/avatar_url_resolver.dart';

/// Membro de uma equipe da empresa. Paridade com web `Team.members[*]`.
class CompanyTeamMember {
  final String userId;
  final String name;
  final String email;
  final String? avatar;
  final String role; // 'member' | 'leader'

  const CompanyTeamMember({
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    this.avatar,
  });

  factory CompanyTeamMember.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    String id = '';
    String name = '';
    String email = '';
    String? avatarRaw;
    if (user is Map) {
      final u = Map<String, dynamic>.from(user);
      id = u['id']?.toString() ?? '';
      name = u['name']?.toString() ?? '';
      email = u['email']?.toString() ?? '';
      final av = u['avatar']?.toString();
      if (av != null && av.isNotEmpty) avatarRaw = av;
    }
    id = id.isNotEmpty ? id : (json['userId']?.toString() ?? '');
    name = name.isNotEmpty ? name : (json['name']?.toString() ?? '');
    email = email.isNotEmpty ? email : (json['email']?.toString() ?? '');
    avatarRaw ??= json['avatar']?.toString();

    return CompanyTeamMember(
      userId: id,
      name: name,
      email: email,
      avatar: AvatarUrlResolver.resolve(avatarRaw),
      role: json['role']?.toString() ?? 'member',
    );
  }

  bool get isLeader => role.toLowerCase() == 'leader';
}

/// Equipe da empresa — paridade com web `Team` (`teamApi.ts`).
class CompanyTeam {
  final String id;
  final String name;
  final String? description;
  final String? color;
  final bool isActive;
  final bool useInSaleForms;
  final List<CompanyTeamMember> members;
  final int? memberCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CompanyTeam({
    required this.id,
    required this.name,
    required this.isActive,
    required this.useInSaleForms,
    required this.members,
    this.description,
    this.color,
    this.memberCount,
    this.createdAt,
    this.updatedAt,
  });

  factory CompanyTeam.fromJson(Map<String, dynamic> json) {
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

    final rawMembers = json['members'];
    final members = rawMembers is List
        ? rawMembers
            .whereType<Map>()
            .map((e) => CompanyTeamMember.fromJson(
                  Map<String, dynamic>.from(e),
                ))
            .toList()
        : <CompanyTeamMember>[];

    int? count;
    final mc = json['memberCount'] ?? json['membersCount'];
    if (mc != null) {
      count = int.tryParse(mc.toString());
    }

    return CompanyTeam(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: (json['description']?.toString() ?? '').isEmpty
          ? null
          : json['description'].toString(),
      color: (json['color']?.toString() ?? '').isEmpty
          ? null
          : json['color'].toString(),
      isActive: parseBool(json['isActive'], defaultValue: true),
      useInSaleForms: parseBool(json['useInSaleForms']),
      members: members,
      memberCount: count,
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    );
  }

  int get totalMembers => memberCount ?? members.length;
  int get leadersCount => members.where((m) => m.isLeader).length;
}

/// Resposta paginada de `/teams/filtered`.
class CompanyTeamsPage {
  final List<CompanyTeam> teams;
  final int total;
  final int page;
  final int totalPages;

  const CompanyTeamsPage({
    required this.teams,
    required this.total,
    required this.page,
    required this.totalPages,
  });

  factory CompanyTeamsPage.fromJson(
    Map<String, dynamic> json,
    int fallbackPage,
  ) {
    final raw = json['data'] ?? json['teams'];
    final list = raw is List
        ? raw
            .map((e) =>
                CompanyTeam.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList()
        : <CompanyTeam>[];
    int parseInt(dynamic v, int fallback) {
      if (v == null) return fallback;
      if (v is int) return v;
      return int.tryParse(v.toString()) ?? fallback;
    }

    return CompanyTeamsPage(
      teams: list,
      total: parseInt(json['total'], list.length),
      page: parseInt(json['page'], fallbackPage),
      totalPages: parseInt(json['totalPages'], 1),
    );
  }
}
