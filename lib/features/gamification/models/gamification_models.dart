// Modelos de Gamificação — espelham `gamification.types.ts` do imobx-front e
// as respostas de `GET /gamification/*` do backend (NestJS). Parse defensivo:
// número pode vir como string, campos podem faltar.

double gamToDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

int gamToInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

DateTime? gamToDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

Map<String, dynamic>? gamToMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

/// Período do score (1:1 com `ScorePeriod` do backend).
enum ScorePeriod {
  daily('daily', 'Hoje'),
  weekly('weekly', 'Semana'),
  monthly('monthly', 'Mês'),
  quarterly('quarterly', 'Trimestre'),
  yearly('yearly', 'Ano'),
  allTime('all_time', 'Sempre');

  const ScorePeriod(this.value, this.label);
  final String value;
  final String label;

  /// Rótulo longo (paridade `ScorePeriodLabels` do web).
  String get longLabel {
    switch (this) {
      case ScorePeriod.daily:
        return 'Hoje';
      case ScorePeriod.weekly:
        return 'Esta Semana';
      case ScorePeriod.monthly:
        return 'Este Mês';
      case ScorePeriod.quarterly:
        return 'Este Trimestre';
      case ScorePeriod.yearly:
        return 'Este Ano';
      case ScorePeriod.allTime:
        return 'Todo o Período';
    }
  }

  static ScorePeriod fromRaw(String? raw) {
    for (final p in ScorePeriod.values) {
      if (p.value == raw) return p;
    }
    return ScorePeriod.monthly;
  }
}

/// Nível/tier da conquista (1:1 com `AchievementTier`).
enum AchievementTier {
  bronze('bronze', 'Bronze', 0xFFCD7F32),
  silver('silver', 'Prata', 0xFF9CA3AF),
  gold('gold', 'Ouro', 0xFFD4A017),
  platinum('platinum', 'Platina', 0xFF8FA6B2),
  diamond('diamond', 'Diamante', 0xFF38BDF8);

  const AchievementTier(this.value, this.label, this.colorValue);
  final String value;
  final String label;

  /// Cor de exibição (versão saturada das do web para legibilidade mobile).
  final int colorValue;

  static AchievementTier fromRaw(String? raw) {
    for (final t in AchievementTier.values) {
      if (t.value == (raw ?? '').toLowerCase()) return t;
    }
    return AchievementTier.bronze;
  }
}

/// Categoria da conquista (1:1 com `AchievementCategory`).
enum AchievementCategory {
  sales('sales', 'Vendas'),
  relationship('relationship', 'Relacionamento'),
  activity('activity', 'Atividade'),
  milestone('milestone', 'Marco'),
  special('special', 'Especial');

  const AchievementCategory(this.value, this.label);
  final String value;
  final String label;

  static AchievementCategory fromRaw(String? raw) {
    for (final c in AchievementCategory.values) {
      if (c.value == (raw ?? '').toLowerCase()) return c;
    }
    return AchievementCategory.special;
  }
}

/// Usuário resumido embutido no score.
class GamificationUser {
  final String id;
  final String name;
  final String email;
  final String? profileImageUrl;

  const GamificationUser({
    required this.id,
    required this.name,
    required this.email,
    this.profileImageUrl,
  });

  factory GamificationUser.fromJson(Map<String, dynamic> j) {
    return GamificationUser(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      email: j['email']?.toString() ?? '',
      profileImageUrl: j['profileImageUrl']?.toString(),
    );
  }
}

/// Score individual (`GamificationScore`).
class GamificationScore {
  final String id;
  final String userId;
  final ScorePeriod period;

  // Vendas
  final int propertiesSold;
  final double totalSalesValue;
  final int rentalsCreated;
  final double totalCommission;

  // Relacionamento
  final int clientsContacted;
  final int newClientsCreated;
  final int meetingsScheduled;

  // Atividade
  final int propertiesCreated;
  final int inspectionsCompleted;
  final int keysDelivered;
  final int tasksCompleted;

  // Pontos
  final int totalPoints;
  final int salesPoints;
  final int activityPoints;
  final int relationshipPoints;

  final int? rankPosition;
  final GamificationUser? user;

  const GamificationScore({
    required this.id,
    required this.userId,
    required this.period,
    required this.propertiesSold,
    required this.totalSalesValue,
    required this.rentalsCreated,
    required this.totalCommission,
    required this.clientsContacted,
    required this.newClientsCreated,
    required this.meetingsScheduled,
    required this.propertiesCreated,
    required this.inspectionsCompleted,
    required this.keysDelivered,
    required this.tasksCompleted,
    required this.totalPoints,
    required this.salesPoints,
    required this.activityPoints,
    required this.relationshipPoints,
    this.rankPosition,
    this.user,
  });

  static GamificationScore empty([ScorePeriod period = ScorePeriod.monthly]) =>
      GamificationScore(
        id: '',
        userId: '',
        period: period,
        propertiesSold: 0,
        totalSalesValue: 0,
        rentalsCreated: 0,
        totalCommission: 0,
        clientsContacted: 0,
        newClientsCreated: 0,
        meetingsScheduled: 0,
        propertiesCreated: 0,
        inspectionsCompleted: 0,
        keysDelivered: 0,
        tasksCompleted: 0,
        totalPoints: 0,
        salesPoints: 0,
        activityPoints: 0,
        relationshipPoints: 0,
      );

  factory GamificationScore.fromJson(Map<String, dynamic> j) {
    final userMap = gamToMap(j['user']);
    return GamificationScore(
      id: j['id']?.toString() ?? '',
      userId: j['userId']?.toString() ?? '',
      period: ScorePeriod.fromRaw(j['period']?.toString()),
      propertiesSold: gamToInt(j['propertiesSold']),
      totalSalesValue: gamToDouble(j['totalSalesValue']),
      rentalsCreated: gamToInt(j['rentalsCreated']),
      totalCommission: gamToDouble(j['totalCommission']),
      clientsContacted: gamToInt(j['clientsContacted']),
      newClientsCreated: gamToInt(j['newClientsCreated']),
      meetingsScheduled: gamToInt(j['meetingsScheduled']),
      propertiesCreated: gamToInt(j['propertiesCreated']),
      inspectionsCompleted: gamToInt(j['inspectionsCompleted']),
      keysDelivered: gamToInt(j['keysDelivered']),
      tasksCompleted: gamToInt(j['tasksCompleted']),
      totalPoints: gamToInt(j['totalPoints']),
      salesPoints: gamToInt(j['salesPoints']),
      activityPoints: gamToInt(j['activityPoints']),
      relationshipPoints: gamToInt(j['relationshipPoints']),
      rankPosition:
          j['rankPosition'] == null ? null : gamToInt(j['rankPosition']),
      user: userMap != null ? GamificationUser.fromJson(userMap) : null,
    );
  }
}

/// Score de equipe (`TeamScore`).
class TeamScore {
  final String id;
  final String teamId;
  final ScorePeriod period;
  final int totalMembers;
  final int propertiesSold;
  final double totalSalesValue;
  final int newClientsCreated;
  final int clientsContacted;
  final int tasksCompleted;
  final int totalPoints;
  final double averagePointsPerMember;
  final int? rankPosition;
  final String? teamName;
  final String? teamDescription;

  const TeamScore({
    required this.id,
    required this.teamId,
    required this.period,
    required this.totalMembers,
    required this.propertiesSold,
    required this.totalSalesValue,
    required this.newClientsCreated,
    required this.clientsContacted,
    required this.tasksCompleted,
    required this.totalPoints,
    required this.averagePointsPerMember,
    this.rankPosition,
    this.teamName,
    this.teamDescription,
  });

  factory TeamScore.fromJson(Map<String, dynamic> j) {
    final team = gamToMap(j['team']);
    return TeamScore(
      id: j['id']?.toString() ?? '',
      teamId: j['teamId']?.toString() ?? '',
      period: ScorePeriod.fromRaw(j['period']?.toString()),
      totalMembers: gamToInt(j['totalMembers']),
      propertiesSold: gamToInt(j['propertiesSold']),
      totalSalesValue: gamToDouble(j['totalSalesValue']),
      newClientsCreated: gamToInt(j['newClientsCreated']),
      clientsContacted: gamToInt(j['clientsContacted']),
      tasksCompleted: gamToInt(j['tasksCompleted']),
      totalPoints: gamToInt(j['totalPoints']),
      averagePointsPerMember: gamToDouble(j['averagePointsPerMember']),
      rankPosition:
          j['rankPosition'] == null ? null : gamToInt(j['rankPosition']),
      teamName: team?['name']?.toString(),
      teamDescription: team?['description']?.toString(),
    );
  }
}

/// Definição da conquista (`Achievement`).
class Achievement {
  final String id;
  final String code;
  final String namePt;
  final String descriptionPt;
  final AchievementCategory category;
  final AchievementTier tier;
  final int pointsReward;
  final String? iconEmoji;

  const Achievement({
    required this.id,
    required this.code,
    required this.namePt,
    required this.descriptionPt,
    required this.category,
    required this.tier,
    required this.pointsReward,
    this.iconEmoji,
  });

  factory Achievement.fromJson(Map<String, dynamic> j) {
    return Achievement(
      id: j['id']?.toString() ?? '',
      code: j['code']?.toString() ?? '',
      namePt: j['namePt']?.toString() ?? j['name']?.toString() ?? '',
      descriptionPt:
          j['descriptionPt']?.toString() ?? j['description']?.toString() ?? '',
      category: AchievementCategory.fromRaw(j['category']?.toString()),
      tier: AchievementTier.fromRaw(j['tier']?.toString()),
      pointsReward: gamToInt(j['pointsReward']),
      iconEmoji: j['iconEmoji']?.toString(),
    );
  }
}

/// Conquista desbloqueada pelo usuário (`UserAchievement`).
class UserAchievement {
  final String id;
  final DateTime? unlockedAt;
  final int pointsEarned;
  final Achievement achievement;

  const UserAchievement({
    required this.id,
    required this.unlockedAt,
    required this.pointsEarned,
    required this.achievement,
  });

  factory UserAchievement.fromJson(Map<String, dynamic> j) {
    final ach = gamToMap(j['achievement']) ?? const <String, dynamic>{};
    return UserAchievement(
      id: j['id']?.toString() ?? '',
      unlockedAt: gamToDate(j['unlockedAt']),
      pointsEarned: gamToInt(j['pointsEarned']),
      achievement: Achievement.fromJson(ach),
    );
  }
}

/// Dashboard completo (`GET /gamification/dashboard`).
class GamificationDashboard {
  final GamificationScore myScore;
  final int achievementsTotal;
  final List<UserAchievement> recentAchievements;
  final int myPosition;
  final int totalParticipants;
  final List<GamificationScore> top5;
  final ScorePeriod period;

  const GamificationDashboard({
    required this.myScore,
    required this.achievementsTotal,
    required this.recentAchievements,
    required this.myPosition,
    required this.totalParticipants,
    required this.top5,
    required this.period,
  });

  factory GamificationDashboard.fromJson(Map<String, dynamic> j) {
    final myScore = gamToMap(j['myScore']);
    final achievements = gamToMap(j['myAchievements']);
    final rankings = gamToMap(j['rankings']);
    final recentRaw = achievements?['recent'];
    final top5Raw = rankings?['top5'];
    return GamificationDashboard(
      myScore: myScore != null
          ? GamificationScore.fromJson(myScore)
          : GamificationScore.empty(),
      achievementsTotal: gamToInt(achievements?['total']),
      recentAchievements: recentRaw is List
          ? recentRaw
              .whereType<Map>()
              .map((e) =>
                  UserAchievement.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      myPosition: gamToInt(rankings?['myPosition']),
      totalParticipants: gamToInt(rankings?['totalParticipants']),
      top5: top5Raw is List
          ? top5Raw
              .whereType<Map>()
              .map((e) =>
                  GamificationScore.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      period: ScorePeriod.fromRaw(j['period']?.toString()),
    );
  }
}

/// Configuração da gamificação da empresa (`GamificationConfig`).
class GamificationConfig {
  final String id;
  final bool isEnabled;

  // Pontos de vendas
  final int pointsPropertySale;
  final int pointsRentalCreated;
  final double pointsCommissionMultiplier;

  // Pontos de relacionamento
  final int pointsNewClient;
  final int pointsClientContact;
  final int pointsMeetingScheduled;

  // Pontos de atividade
  final int pointsPropertyCreated;
  final int pointsInspectionCompleted;
  final int pointsTaskCompleted;
  final int pointsKeyDelivered;

  // Visibilidade
  final bool showIndividualRanking;
  final bool showTeamRanking;
  final bool showAchievements;

  final List<String> enabledPeriods;
  final String? welcomeMessage;
  final String? rankingMessage;

  // Notificações
  final bool notifyNewAchievement;
  final bool notifyRankChange;
  final bool notifyWeeklySummary;

  const GamificationConfig({
    required this.id,
    required this.isEnabled,
    required this.pointsPropertySale,
    required this.pointsRentalCreated,
    required this.pointsCommissionMultiplier,
    required this.pointsNewClient,
    required this.pointsClientContact,
    required this.pointsMeetingScheduled,
    required this.pointsPropertyCreated,
    required this.pointsInspectionCompleted,
    required this.pointsTaskCompleted,
    required this.pointsKeyDelivered,
    required this.showIndividualRanking,
    required this.showTeamRanking,
    required this.showAchievements,
    required this.enabledPeriods,
    this.welcomeMessage,
    this.rankingMessage,
    required this.notifyNewAchievement,
    required this.notifyRankChange,
    required this.notifyWeeklySummary,
  });

  factory GamificationConfig.fromJson(Map<String, dynamic> j) {
    bool asBool(dynamic v, [bool fallback = false]) {
      if (v is bool) return v;
      if (v is String) return v.toLowerCase() == 'true';
      if (v is num) return v != 0;
      return fallback;
    }

    final periodsRaw = j['enabledPeriods'];
    return GamificationConfig(
      id: j['id']?.toString() ?? '',
      isEnabled: asBool(j['isEnabled']),
      pointsPropertySale: gamToInt(j['pointsPropertySale']),
      pointsRentalCreated: gamToInt(j['pointsRentalCreated']),
      pointsCommissionMultiplier: gamToDouble(j['pointsCommissionMultiplier']),
      pointsNewClient: gamToInt(j['pointsNewClient']),
      pointsClientContact: gamToInt(j['pointsClientContact']),
      pointsMeetingScheduled: gamToInt(j['pointsMeetingScheduled']),
      pointsPropertyCreated: gamToInt(j['pointsPropertyCreated']),
      pointsInspectionCompleted: gamToInt(j['pointsInspectionCompleted']),
      pointsTaskCompleted: gamToInt(j['pointsTaskCompleted']),
      pointsKeyDelivered: gamToInt(j['pointsKeyDelivered']),
      showIndividualRanking: asBool(j['showIndividualRanking'], true),
      showTeamRanking: asBool(j['showTeamRanking'], true),
      showAchievements: asBool(j['showAchievements'], true),
      enabledPeriods: periodsRaw is List
          ? periodsRaw.map((e) => e.toString()).toList()
          : const [],
      welcomeMessage: j['welcomeMessage']?.toString(),
      rankingMessage: j['rankingMessage']?.toString(),
      notifyNewAchievement: asBool(j['notifyNewAchievement'], true),
      notifyRankChange: asBool(j['notifyRankChange'], true),
      notifyWeeklySummary: asBool(j['notifyWeeklySummary'], true),
    );
  }

  GamificationConfig copyWith({
    bool? isEnabled,
    int? pointsPropertySale,
    int? pointsRentalCreated,
    double? pointsCommissionMultiplier,
    int? pointsNewClient,
    int? pointsClientContact,
    int? pointsMeetingScheduled,
    int? pointsPropertyCreated,
    int? pointsInspectionCompleted,
    int? pointsTaskCompleted,
    int? pointsKeyDelivered,
    bool? showIndividualRanking,
    bool? showTeamRanking,
    bool? showAchievements,
    List<String>? enabledPeriods,
    String? welcomeMessage,
    String? rankingMessage,
    bool? notifyNewAchievement,
    bool? notifyRankChange,
    bool? notifyWeeklySummary,
  }) {
    return GamificationConfig(
      id: id,
      isEnabled: isEnabled ?? this.isEnabled,
      pointsPropertySale: pointsPropertySale ?? this.pointsPropertySale,
      pointsRentalCreated: pointsRentalCreated ?? this.pointsRentalCreated,
      pointsCommissionMultiplier:
          pointsCommissionMultiplier ?? this.pointsCommissionMultiplier,
      pointsNewClient: pointsNewClient ?? this.pointsNewClient,
      pointsClientContact: pointsClientContact ?? this.pointsClientContact,
      pointsMeetingScheduled:
          pointsMeetingScheduled ?? this.pointsMeetingScheduled,
      pointsPropertyCreated:
          pointsPropertyCreated ?? this.pointsPropertyCreated,
      pointsInspectionCompleted:
          pointsInspectionCompleted ?? this.pointsInspectionCompleted,
      pointsTaskCompleted: pointsTaskCompleted ?? this.pointsTaskCompleted,
      pointsKeyDelivered: pointsKeyDelivered ?? this.pointsKeyDelivered,
      showIndividualRanking:
          showIndividualRanking ?? this.showIndividualRanking,
      showTeamRanking: showTeamRanking ?? this.showTeamRanking,
      showAchievements: showAchievements ?? this.showAchievements,
      enabledPeriods: enabledPeriods ?? this.enabledPeriods,
      welcomeMessage: welcomeMessage ?? this.welcomeMessage,
      rankingMessage: rankingMessage ?? this.rankingMessage,
      notifyNewAchievement: notifyNewAchievement ?? this.notifyNewAchievement,
      notifyRankChange: notifyRankChange ?? this.notifyRankChange,
      notifyWeeklySummary: notifyWeeklySummary ?? this.notifyWeeklySummary,
    );
  }

  /// Payload de `PUT /gamification/config` (paridade
  /// `UpdateGamificationConfigRequest` do web — envia o estado completo).
  Map<String, dynamic> toUpdatePayload() {
    return {
      'isEnabled': isEnabled,
      'pointsPropertySale': pointsPropertySale,
      'pointsRentalCreated': pointsRentalCreated,
      'pointsCommissionMultiplier': pointsCommissionMultiplier,
      'pointsNewClient': pointsNewClient,
      'pointsClientContact': pointsClientContact,
      'pointsMeetingScheduled': pointsMeetingScheduled,
      'pointsPropertyCreated': pointsPropertyCreated,
      'pointsInspectionCompleted': pointsInspectionCompleted,
      'pointsTaskCompleted': pointsTaskCompleted,
      'pointsKeyDelivered': pointsKeyDelivered,
      'showIndividualRanking': showIndividualRanking,
      'showTeamRanking': showTeamRanking,
      'showAchievements': showAchievements,
      if (enabledPeriods.isNotEmpty) 'enabledPeriods': enabledPeriods,
      if (welcomeMessage != null) 'welcomeMessage': welcomeMessage,
      if (rankingMessage != null) 'rankingMessage': rankingMessage,
      'notifyNewAchievement': notifyNewAchievement,
      'notifyRankChange': notifyRankChange,
      'notifyWeeklySummary': notifyWeeklySummary,
    };
  }
}
