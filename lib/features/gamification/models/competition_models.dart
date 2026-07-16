// Modelos de Competições e Prêmios — espelham `competition.types.ts` e
// `prizesApi.ts` do imobx-front (backend `competitions.controller.ts`).

import 'gamification_models.dart'
    show gamToDouble, gamToInt, gamToDate, gamToMap;

/// Tipo da competição (1:1 com `CompetitionType`).
enum CompetitionType {
  individual('individual', 'Individual'),
  team('team', 'Por Equipe'),
  mixed('mixed', 'Misto');

  const CompetitionType(this.value, this.label);
  final String value;
  final String label;

  /// Rótulo longo (paridade `CompetitionTypeLabels`).
  String get longLabel {
    switch (this) {
      case CompetitionType.individual:
        return 'Individual';
      case CompetitionType.team:
        return 'Por Equipe';
      case CompetitionType.mixed:
        return 'Misto (Individual + Equipe)';
    }
  }

  static CompetitionType fromRaw(String? raw) {
    for (final t in CompetitionType.values) {
      if (t.value == (raw ?? '').toLowerCase()) return t;
    }
    return CompetitionType.individual;
  }
}

/// Status da competição (1:1 com `CompetitionStatus`).
enum CompetitionStatus {
  draft('draft', 'Rascunho'),
  scheduled('scheduled', 'Agendada'),
  active('active', 'Em Andamento'),
  finished('finished', 'Finalizada'),
  cancelled('cancelled', 'Cancelada');

  const CompetitionStatus(this.value, this.label);
  final String value;
  final String label;

  static CompetitionStatus fromRaw(String? raw) {
    for (final s in CompetitionStatus.values) {
      if (s.value == (raw ?? '').toLowerCase()) return s;
    }
    return CompetitionStatus.draft;
  }
}

/// Prêmio de uma competição (`CompetitionPrize`).
class CompetitionPrize {
  final String id;
  final String competitionId;
  final int position;
  final String name;
  final String? description;
  final double? value;
  final String? imageUrl;
  final bool isDelivered;
  final String? winnerUserName;
  final String? winnerTeamName;
  final DateTime? deliveredAt;

  const CompetitionPrize({
    required this.id,
    required this.competitionId,
    required this.position,
    required this.name,
    this.description,
    this.value,
    this.imageUrl,
    required this.isDelivered,
    this.winnerUserName,
    this.winnerTeamName,
    this.deliveredAt,
  });

  factory CompetitionPrize.fromJson(Map<String, dynamic> j) {
    final winnerUser = gamToMap(j['winnerUser']);
    final winnerTeam = gamToMap(j['winnerTeam']);
    return CompetitionPrize(
      id: j['id']?.toString() ?? '',
      competitionId: j['competitionId']?.toString() ?? '',
      position: gamToInt(j['position']),
      name: j['name']?.toString() ?? '',
      description: j['description']?.toString(),
      value: j['value'] == null ? null : gamToDouble(j['value']),
      imageUrl: j['imageUrl']?.toString(),
      isDelivered: j['isDelivered'] == true,
      winnerUserName: winnerUser?['name']?.toString(),
      winnerTeamName: winnerTeam?['name']?.toString(),
      deliveredAt: gamToDate(j['deliveredAt']),
    );
  }
}

/// Competição (`Competition`).
class Competition {
  final String id;
  final String name;
  final String? description;
  final CompetitionType type;
  final CompetitionStatus status;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool useCompanyPointsConfig;
  final List<String>? participantUserIds;
  final List<String>? participantTeamIds;
  final bool autoStart;
  final bool autoEnd;
  final int? minParticipants;
  final int? maxParticipants;
  final String? createdByName;
  final List<CompetitionPrize> prizes;

  const Competition({
    required this.id,
    required this.name,
    this.description,
    required this.type,
    required this.status,
    this.startDate,
    this.endDate,
    required this.useCompanyPointsConfig,
    this.participantUserIds,
    this.participantTeamIds,
    required this.autoStart,
    required this.autoEnd,
    this.minParticipants,
    this.maxParticipants,
    this.createdByName,
    required this.prizes,
  });

  /// `null` em `participantUserIds` significa "todos os corretores".
  String get participantsLabel => participantUserIds == null
      ? 'Todos'
      : '${participantUserIds!.length}';

  /// `null` em `participantTeamIds` significa "todas as equipes".
  String get teamsLabel =>
      participantTeamIds == null ? 'Todas' : '${participantTeamIds!.length}';

  /// Dias restantes até o fim, arredondando pra cima (paridade
  /// `getDaysRemaining` do web). Pode ser negativo se já terminou.
  int? get daysRemaining {
    if (endDate == null) return null;
    final diff = endDate!.difference(DateTime.now());
    return (diff.inMinutes / (60 * 24)).ceil();
  }

  /// Só rascunho/agendada podem ser excluídas (regra do web).
  bool get canDelete =>
      status == CompetitionStatus.draft || status == CompetitionStatus.scheduled;

  bool get canFinalize => status == CompetitionStatus.active;

  factory Competition.fromJson(Map<String, dynamic> j) {
    List<String>? idList(dynamic v) {
      if (v is List) return v.map((e) => e.toString()).toList();
      return null;
    }

    final prizesRaw = j['prizes'];
    final createdBy = gamToMap(j['createdBy']);
    return Competition(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      description: j['description']?.toString(),
      type: CompetitionType.fromRaw(j['type']?.toString()),
      status: CompetitionStatus.fromRaw(j['status']?.toString()),
      startDate: gamToDate(j['startDate']),
      endDate: gamToDate(j['endDate']),
      useCompanyPointsConfig: j['useCompanyPointsConfig'] != false,
      participantUserIds: idList(j['participantUserIds']),
      participantTeamIds: idList(j['participantTeamIds']),
      autoStart: j['autoStart'] == true,
      autoEnd: j['autoEnd'] == true,
      minParticipants:
          j['minParticipants'] == null ? null : gamToInt(j['minParticipants']),
      maxParticipants:
          j['maxParticipants'] == null ? null : gamToInt(j['maxParticipants']),
      createdByName: createdBy?['name']?.toString(),
      prizes: prizesRaw is List
          ? prizesRaw
              .whereType<Map>()
              .map((e) =>
                  CompetitionPrize.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

/// Payload de criação/edição (`CreateCompetitionRequest`).
class CompetitionPayload {
  final String name;
  final String? description;
  final CompetitionType type;
  final DateTime startDate;
  final DateTime endDate;
  final bool useCompanyPointsConfig;
  final bool autoStart;
  final bool autoEnd;
  final int? minParticipants;
  final int? maxParticipants;

  /// `null` = todos (não envia a chave).
  final List<String>? participantUserIds;
  final List<String>? participantTeamIds;

  const CompetitionPayload({
    required this.name,
    this.description,
    required this.type,
    required this.startDate,
    required this.endDate,
    this.useCompanyPointsConfig = true,
    this.autoStart = true,
    this.autoEnd = true,
    this.minParticipants,
    this.maxParticipants,
    this.participantUserIds,
    this.participantTeamIds,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null && description!.trim().isNotEmpty)
        'description': description!.trim(),
      'type': type.value,
      'startDate': startDate.toUtc().toIso8601String(),
      'endDate': endDate.toUtc().toIso8601String(),
      'useCompanyPointsConfig': useCompanyPointsConfig,
      'autoStart': autoStart,
      'autoEnd': autoEnd,
      if (minParticipants != null) 'minParticipants': minParticipants,
      if (maxParticipants != null) 'maxParticipants': maxParticipants,
      if (participantUserIds != null)
        'participantUserIds': participantUserIds,
      if (participantTeamIds != null)
        'participantTeamIds': participantTeamIds,
    };
  }
}

/// Status do prêmio na visão global (`Prize.status` do `prizesApi.ts`).
enum PrizeStatus {
  available('available', 'Disponível'),
  pending('pending', 'Pendente'),
  delivered('delivered', 'Entregue'),
  unknown('unknown', 'Prêmio');

  const PrizeStatus(this.value, this.label);
  final String value;
  final String label;

  static PrizeStatus fromRaw(String? raw) {
    for (final s in PrizeStatus.values) {
      if (s.value == (raw ?? '').toLowerCase()) return s;
    }
    return PrizeStatus.unknown;
  }
}

/// Prêmio na listagem global (`GET /competitions/prizes/all`).
class Prize {
  final String id;
  final String name;
  final String? description;
  final double value;
  final PrizeStatus status;
  final String competitionId;
  final String competitionName;
  final int position;
  final String? winnerUserId;
  final String? winnerUserName;
  final String? winnerTeamId;
  final String? winnerTeamName;
  final DateTime? deliveredAt;
  final DateTime? createdAt;

  const Prize({
    required this.id,
    required this.name,
    this.description,
    required this.value,
    required this.status,
    required this.competitionId,
    required this.competitionName,
    required this.position,
    this.winnerUserId,
    this.winnerUserName,
    this.winnerTeamId,
    this.winnerTeamName,
    this.deliveredAt,
    this.createdAt,
  });

  bool get hasWinner =>
      (winnerUserId != null && winnerUserId!.isNotEmpty) ||
      (winnerTeamId != null && winnerTeamId!.isNotEmpty) ||
      (winnerUserName != null && winnerUserName!.isNotEmpty) ||
      (winnerTeamName != null && winnerTeamName!.isNotEmpty);

  /// Regras de ação (paridade `PrizesPage.tsx`).
  bool get canEdit => status != PrizeStatus.delivered && !hasWinner;
  bool get canDeliver => status == PrizeStatus.pending && hasWinner;
  bool get canDelete => status == PrizeStatus.available;

  factory Prize.fromJson(Map<String, dynamic> j) {
    return Prize(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      description: j['description']?.toString(),
      value: gamToDouble(j['value']),
      status: PrizeStatus.fromRaw(j['status']?.toString()),
      competitionId: j['competitionId']?.toString() ?? '',
      competitionName: j['competitionName']?.toString() ?? '',
      position: gamToInt(j['position']),
      winnerUserId: j['winnerUserId']?.toString(),
      winnerUserName: j['winnerUserName']?.toString(),
      winnerTeamId: j['winnerTeamId']?.toString(),
      winnerTeamName: j['winnerTeamName']?.toString(),
      deliveredAt: gamToDate(j['deliveredAt']),
      createdAt: gamToDate(j['createdAt']),
    );
  }
}

/// Payload de criação/edição de prêmio (`CreatePrizeRequest`).
class PrizePayload {
  final int position;
  final String name;
  final String? description;
  final double? value;
  final String? imageUrl;

  const PrizePayload({
    required this.position,
    required this.name,
    this.description,
    this.value,
    this.imageUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'position': position,
      'name': name,
      if (description != null && description!.trim().isNotEmpty)
        'description': description!.trim(),
      if (value != null) 'value': value,
      if (imageUrl != null && imageUrl!.trim().isNotEmpty)
        'imageUrl': imageUrl!.trim(),
    };
  }
}

/// Participante selecionável (corretor) — vindo de `GET /admin/users`.
class ParticipantUser {
  final String id;
  final String name;
  final String email;

  const ParticipantUser({
    required this.id,
    required this.name,
    required this.email,
  });

  factory ParticipantUser.fromJson(Map<String, dynamic> j) {
    return ParticipantUser(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      email: j['email']?.toString() ?? '',
    );
  }
}

/// Equipe selecionável — vindo de `GET /teams`.
class ParticipantTeam {
  final String id;
  final String name;

  const ParticipantTeam({required this.id, required this.name});

  factory ParticipantTeam.fromJson(Map<String, dynamic> j) {
    return ParticipantTeam(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
    );
  }
}
