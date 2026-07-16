// Models de Comparação de Performance — espelham `types/performance.ts` e
// `usePerformance.ts` do imobx-front
// (`POST /matches/performance/compare/users|teams`).

import 'parse_utils.dart';

/// Membro da empresa (seleção de corretores).
class MemberOption {
  final String id;
  final String name;
  final String email;
  final String? avatar;

  const MemberOption({
    required this.id,
    required this.name,
    required this.email,
    this.avatar,
  });

  factory MemberOption.fromJson(Map<String, dynamic> json) {
    return MemberOption(
      id: parseString(json['id']),
      name: parseString(json['name'], 'Sem nome'),
      email: parseString(json['email']),
      avatar: parseStringOrNull(json['avatar']),
    );
  }
}

/// Equipe da empresa (seleção de equipes).
class TeamOption {
  final String id;
  final String name;
  final int? memberCount;

  const TeamOption({required this.id, required this.name, this.memberCount});

  factory TeamOption.fromJson(Map<String, dynamic> json) {
    final members = json['members'];
    return TeamOption(
      id: parseString(json['id']),
      name: parseString(json['name'], 'Equipe'),
      memberCount: json['memberCount'] != null
          ? parseInt(json['memberCount'])
          : (members is List ? members.length : null),
    );
  }
}

/// Performance de um usuário na comparação.
class UserPerformanceData {
  final String userId;
  final String userName;
  final int totalMatches;
  final int pendingMatches;
  final int acceptedMatches;
  final int ignoredMatches;
  final double acceptanceRate;
  final double avgAcceptedScore;
  final int tasksCreatedFromMatches;
  final int tasksCompletedFromMatches;
  final double taskCompletionRate;
  final double avgResponseTime; // horas
  final int totalSales;
  final int totalRentals;
  final double salesRevenue;
  final double rentalsRevenue;
  final double totalCommissions;

  const UserPerformanceData({
    required this.userId,
    required this.userName,
    required this.totalMatches,
    required this.pendingMatches,
    required this.acceptedMatches,
    required this.ignoredMatches,
    required this.acceptanceRate,
    required this.avgAcceptedScore,
    required this.tasksCreatedFromMatches,
    required this.tasksCompletedFromMatches,
    required this.taskCompletionRate,
    required this.avgResponseTime,
    required this.totalSales,
    required this.totalRentals,
    required this.salesRevenue,
    required this.rentalsRevenue,
    required this.totalCommissions,
  });

  factory UserPerformanceData.fromJson(Map<String, dynamic> json) {
    return UserPerformanceData(
      userId: parseString(json['userId'], parseString(json['id'])),
      userName: parseString(json['userName'], 'Corretor'),
      totalMatches: parseInt(json['totalMatches']),
      pendingMatches: parseInt(json['pendingMatches']),
      acceptedMatches: parseInt(json['acceptedMatches']),
      ignoredMatches: parseInt(json['ignoredMatches']),
      acceptanceRate: parseDouble(json['acceptanceRate']),
      avgAcceptedScore: parseDouble(json['avgAcceptedScore']),
      tasksCreatedFromMatches: parseInt(json['tasksCreatedFromMatches']),
      tasksCompletedFromMatches: parseInt(json['tasksCompletedFromMatches']),
      taskCompletionRate: parseDouble(json['taskCompletionRate']),
      avgResponseTime: parseDouble(json['avgResponseTime']),
      totalSales: parseInt(json['totalSales']),
      totalRentals: parseInt(json['totalRentals']),
      salesRevenue: parseDouble(json['salesRevenue']),
      rentalsRevenue: parseDouble(json['rentalsRevenue']),
      totalCommissions: parseDouble(json['totalCommissions']),
    );
  }

  double get totalRevenue => salesRevenue + rentalsRevenue;
}

/// Performance de uma equipe na comparação.
class TeamPerformanceData {
  final String teamId;
  final String teamName;
  final int memberCount;
  final int totalMatches;
  final int pendingMatches;
  final int acceptedMatches;
  final int ignoredMatches;
  final double acceptanceRate;
  final double avgMatchScore;
  final int totalSales;
  final int totalRentals;
  final double salesRevenue;
  final double rentalsRevenue;
  final double totalCommissions;
  final double conversionRate;
  final String? topPerformerName;

  const TeamPerformanceData({
    required this.teamId,
    required this.teamName,
    required this.memberCount,
    required this.totalMatches,
    required this.pendingMatches,
    required this.acceptedMatches,
    required this.ignoredMatches,
    required this.acceptanceRate,
    required this.avgMatchScore,
    required this.totalSales,
    required this.totalRentals,
    required this.salesRevenue,
    required this.rentalsRevenue,
    required this.totalCommissions,
    required this.conversionRate,
    required this.topPerformerName,
  });

  factory TeamPerformanceData.fromJson(Map<String, dynamic> json) {
    final topPerformer = parseMap(json['topPerformer']);
    return TeamPerformanceData(
      teamId: parseString(json['teamId'], parseString(json['id'])),
      teamName: parseString(json['teamName'], 'Equipe'),
      memberCount: parseInt(json['memberCount']),
      totalMatches: parseInt(json['totalMatches']),
      pendingMatches: parseInt(json['pendingMatches']),
      acceptedMatches: parseInt(json['acceptedMatches']),
      ignoredMatches: parseInt(json['ignoredMatches']),
      acceptanceRate: parseDouble(json['acceptanceRate']),
      avgMatchScore: parseDouble(json['avgMatchScore']),
      totalSales: parseInt(json['totalSales']),
      totalRentals: parseInt(json['totalRentals']),
      salesRevenue: parseDouble(json['salesRevenue']),
      rentalsRevenue: parseDouble(json['rentalsRevenue']),
      totalCommissions: parseDouble(json['totalCommissions']),
      conversionRate: parseDouble(json['conversionRate']),
      topPerformerName: parseStringOrNull(topPerformer?['userName']),
    );
  }

  double get totalRevenue => salesRevenue + rentalsRevenue;
}

/// Vencedor de uma categoria ("melhores em").
class BestEntry {
  final String id;
  final String name;
  final double value;

  const BestEntry({required this.id, required this.name, required this.value});

  static BestEntry? fromJson(
    Map<String, dynamic>? json, {
    String idKey = 'userId',
    String nameKey = 'userName',
  }) {
    if (json == null) return null;
    final name = parseStringOrNull(json[nameKey]);
    if (name == null) return null;
    return BestEntry(
      id: parseString(json[idKey]),
      name: name,
      value: parseDouble(json['value']),
    );
  }
}

/// Resposta de `POST /matches/performance/compare/users`.
class UsersComparison {
  final List<UserPerformanceData> users;
  final BestEntry? bestAcceptanceRate;
  final BestEntry? bestAvgScore;
  final BestEntry? bestTasksCompleted;
  final BestEntry? bestResponseTime;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  const UsersComparison({
    required this.users,
    required this.bestAcceptanceRate,
    required this.bestAvgScore,
    required this.bestTasksCompleted,
    required this.bestResponseTime,
    required this.periodStart,
    required this.periodEnd,
  });

  factory UsersComparison.fromJson(Map<String, dynamic> json) {
    final body = unwrapData(json);
    final bestIn = parseMap(body['bestIn']);
    final period = parseMap(body['period']);
    return UsersComparison(
      users: parseMapList(body['users'])
          .map(UserPerformanceData.fromJson)
          .toList(growable: false),
      bestAcceptanceRate: BestEntry.fromJson(parseMap(bestIn?['acceptanceRate'])),
      bestAvgScore: BestEntry.fromJson(parseMap(bestIn?['avgScore'])),
      bestTasksCompleted: BestEntry.fromJson(parseMap(bestIn?['tasksCompleted'])),
      bestResponseTime: BestEntry.fromJson(parseMap(bestIn?['responseTime'])),
      periodStart: parseDate(period?['start']),
      periodEnd: parseDate(period?['end']),
    );
  }
}

/// Usuário presente em mais de uma equipe comparada.
class SharedUser {
  final String userId;
  final String userName;
  final List<String> teams;
  final int totalSales;
  final int totalRentals;

  const SharedUser({
    required this.userId,
    required this.userName,
    required this.teams,
    required this.totalSales,
    required this.totalRentals,
  });

  factory SharedUser.fromJson(Map<String, dynamic> json) {
    return SharedUser(
      userId: parseString(json['userId']),
      userName: parseString(json['userName'], 'Corretor'),
      teams: parseStringList(json['teams']),
      totalSales: parseInt(json['totalSales']),
      totalRentals: parseInt(json['totalRentals']),
    );
  }
}

/// Resposta de `POST /matches/performance/compare/teams`.
class TeamsComparison {
  final List<TeamPerformanceData> teams;
  final BestEntry? bestAcceptanceRate;
  final BestEntry? bestAvgScore;
  final BestEntry? bestTotalMatches;
  final List<SharedUser> sharedUsers;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  const TeamsComparison({
    required this.teams,
    required this.bestAcceptanceRate,
    required this.bestAvgScore,
    required this.bestTotalMatches,
    required this.sharedUsers,
    required this.periodStart,
    required this.periodEnd,
  });

  factory TeamsComparison.fromJson(Map<String, dynamic> json) {
    final body = unwrapData(json);
    final best = parseMap(body['bestTeam']);
    final period = parseMap(body['period']);
    return TeamsComparison(
      teams: parseMapList(body['teams'])
          .map(TeamPerformanceData.fromJson)
          .toList(growable: false),
      bestAcceptanceRate: BestEntry.fromJson(
        parseMap(best?['acceptanceRate']),
        idKey: 'teamId',
        nameKey: 'teamName',
      ),
      bestAvgScore: BestEntry.fromJson(
        parseMap(best?['avgScore']),
        idKey: 'teamId',
        nameKey: 'teamName',
      ),
      bestTotalMatches: BestEntry.fromJson(
        parseMap(best?['totalMatches']),
        idKey: 'teamId',
        nameKey: 'teamName',
      ),
      sharedUsers: parseMapList(body['sharedUsers'])
          .map(SharedUser.fromJson)
          .toList(growable: false),
      periodStart: parseDate(period?['start']),
      periodEnd: parseDate(period?['end']),
    );
  }
}

/// Filtros extras compartilhados pelas duas comparações (paridade web).
class CompareFilters {
  final DateTime? startDate;
  final DateTime? endDate;
  final String propertyType; // all | sale | rental
  final String region; // UF (2 letras) ou vazio
  final double? minPrice;
  final double? maxPrice;

  const CompareFilters({
    this.startDate,
    this.endDate,
    this.propertyType = 'all',
    this.region = '',
    this.minPrice,
    this.maxPrice,
  });

  int get activeCount {
    var n = 0;
    if (startDate != null && endDate != null) n++;
    if (propertyType != 'all') n++;
    if (region.trim().isNotEmpty) n++;
    if (minPrice != null || maxPrice != null) n++;
    return n;
  }

  Map<String, dynamic> toBody() {
    final body = <String, dynamic>{};
    if (startDate != null) {
      body['startDate'] = startDate!.toIso8601String().split('T').first;
    }
    if (endDate != null) {
      body['endDate'] = endDate!.toIso8601String().split('T').first;
    }
    if (propertyType.isNotEmpty) body['propertyType'] = propertyType;
    if (region.trim().isNotEmpty) body['region'] = region.trim().toUpperCase();
    if (minPrice != null) body['minPrice'] = minPrice;
    if (maxPrice != null) body['maxPrice'] = maxPrice;
    return body;
  }
}
