// Modelos da Monitoria Online (Master) — espelham `presenceApi` do
// imobx-front e o `presence.controller.ts` (`/master/presence/*`, @Roles(MASTER)).

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

int _toInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? fallback;
}

/// Bucket de presença por empresa.
class PresenceCompanyBucket {
  final String? companyId;
  final String companyName;
  final int online;

  const PresenceCompanyBucket({
    this.companyId,
    required this.companyName,
    required this.online,
  });

  factory PresenceCompanyBucket.fromJson(Map<String, dynamic> json) {
    return PresenceCompanyBucket(
      companyId: json['companyId']?.toString(),
      companyName: json['companyName']?.toString() ?? 'Sem empresa',
      online: _toInt(json['online']),
    );
  }
}

/// `GET /master/presence/overview`.
class PresenceOverview {
  final int totalOnline;
  final int totalConnections;
  final int usersWithMultipleSessions;
  final int activeCompanies;
  final int peakToday;
  final DateTime? peakTodayAt;
  final List<PresenceCompanyBucket> perCompany;
  final DateTime? generatedAt;

  const PresenceOverview({
    required this.totalOnline,
    required this.totalConnections,
    required this.usersWithMultipleSessions,
    required this.activeCompanies,
    required this.peakToday,
    this.peakTodayAt,
    this.perCompany = const [],
    this.generatedAt,
  });

  static const zero = PresenceOverview(
    totalOnline: 0,
    totalConnections: 0,
    usersWithMultipleSessions: 0,
    activeCompanies: 0,
    peakToday: 0,
  );

  factory PresenceOverview.fromJson(Map<String, dynamic> json) {
    final rawCompanies = json['perCompany'];
    return PresenceOverview(
      totalOnline: _toInt(json['totalOnline']),
      totalConnections: _toInt(json['totalConnections']),
      usersWithMultipleSessions: _toInt(json['usersWithMultipleSessions']),
      activeCompanies: _toInt(json['activeCompanies']),
      peakToday: _toInt(json['peakToday']),
      peakTodayAt: _toDate(json['peakTodayAt']),
      perCompany: rawCompanies is List
          ? rawCompanies
              .whereType<Map>()
              .map((e) =>
                  PresenceCompanyBucket.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      generatedAt: _toDate(json['generatedAt']),
    );
  }
}

/// Nível de atividade derivado do `lastSeen` (mesma régua do web:
/// ≤2min ativo, ≤15min ocioso, depois ausente).
enum PresenceActivity {
  active,
  idle,
  away;

  String get label {
    switch (this) {
      case PresenceActivity.active:
        return 'Ativo';
      case PresenceActivity.idle:
        return 'Ocioso';
      case PresenceActivity.away:
        return 'Ausente';
    }
  }
}

/// Tipo de dispositivo inferido da string `device` do backend.
enum PresenceDeviceKind { desktop, mobile, tablet }

/// Usuário online em `GET /master/presence/online-users`.
class OnlineUser {
  final String userId;
  final String name;
  final String email;
  final String role;
  final String? companyId;
  final String? companyName;
  final int connections;
  final String? device;
  final String? browser;
  final String? ip;
  final DateTime? connectedAt;
  final DateTime? lastSeen;

  const OnlineUser({
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    this.companyId,
    this.companyName,
    required this.connections,
    this.device,
    this.browser,
    this.ip,
    this.connectedAt,
    this.lastSeen,
  });

  PresenceActivity get activity {
    final seen = lastSeen;
    if (seen == null) return PresenceActivity.away;
    final min = DateTime.now().difference(seen).inMinutes;
    if (min <= 2) return PresenceActivity.active;
    if (min <= 15) return PresenceActivity.idle;
    return PresenceActivity.away;
  }

  PresenceDeviceKind get deviceKind {
    final d = (device ?? '').toLowerCase();
    if (d.contains('mobile')) return PresenceDeviceKind.mobile;
    if (d.contains('tablet')) return PresenceDeviceKind.tablet;
    return PresenceDeviceKind.desktop;
  }

  String get roleLabel {
    switch (role.trim().toLowerCase()) {
      case 'master':
        return 'Master';
      case 'admin':
        return 'Admin';
      case 'manager':
        return 'Gerente';
      case 'user':
        return 'Usuário';
      default:
        return role;
    }
  }

  String get initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// "5min", "2h 10min", "3d" — tempo conectado.
  String get onlineFor => _durationSince(connectedAt);

  /// "agora", "4min atrás", "2h atrás" — última atividade.
  String get lastSeenAgo {
    final seen = lastSeen;
    if (seen == null) return '—';
    final diff = DateTime.now().difference(seen);
    if (diff.inSeconds < 60) return 'agora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}min atrás';
    if (diff.inHours < 24) return '${diff.inHours}h atrás';
    return '${diff.inDays}d atrás';
  }

  static String _durationSince(DateTime? value) {
    if (value == null) return '—';
    final min = DateTime.now().difference(value).inMinutes;
    if (min < 1) return '<1min';
    if (min < 60) return '${min}min';
    final h = min ~/ 60;
    final rem = min % 60;
    if (h < 24) return rem > 0 ? '${h}h ${rem}min' : '${h}h';
    return '${h ~/ 24}d';
  }

  factory OnlineUser.fromJson(Map<String, dynamic> json) {
    return OnlineUser(
      userId: json['userId']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      companyId: json['companyId']?.toString(),
      companyName: json['companyName']?.toString(),
      connections: _toInt(json['connections'], 1),
      device: json['device']?.toString(),
      browser: json['browser']?.toString(),
      ip: json['ip']?.toString(),
      connectedAt: _toDate(json['connectedAt']),
      lastSeen: _toDate(json['lastSeen']),
    );
  }
}

/// Resposta paginada de `GET /master/presence/online-users`.
class OnlineUsersResult {
  final List<OnlineUser> users;
  final int total;

  const OnlineUsersResult({required this.users, required this.total});

  static const empty = OnlineUsersResult(users: [], total: 0);

  factory OnlineUsersResult.fromJson(Map<String, dynamic> json) {
    final raw = json['users'];
    final list = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => OnlineUser.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <OnlineUser>[];
    return OnlineUsersResult(users: list, total: _toInt(json['total'], list.length));
  }
}

/// Resultado de force-logout (individual): sockets encerrados.
class ForceLogoutResult {
  final bool success;
  final int disconnectedSockets;

  const ForceLogoutResult({
    required this.success,
    required this.disconnectedSockets,
  });

  factory ForceLogoutResult.fromJson(Map<String, dynamic> json) {
    return ForceLogoutResult(
      success: json['success'] == true,
      disconnectedSockets: _toInt(json['disconnectedSockets']),
    );
  }
}
