/// Modelos das métricas do dashboard SDR — paridade com o payload de
/// `GET /kanban/analytics/sdr/metrics` (imobx) e com o `SdrMetrics` do
/// `kanbanMetricsApi.ts` do imobx-front. Parsing 100% defensivo: aceita
/// null / string / number em todos os campos numéricos.
library;

int _asInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(v.toString()) ?? (double.tryParse(v.toString())?.round() ?? 0);
}

double _asDouble(dynamic v) {
  if (v == null) return 0;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
}

double? _asDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '.'));
}

String _asString(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final s = v.toString().trim();
  return s.isEmpty ? fallback : s;
}

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}

List<Map<String, dynamic>> _asMapList(dynamic v) {
  if (v is! List) return const [];
  return v
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
}

/// Resumo geral do pré-atendimento no período.
class SdrSummary {
  const SdrSummary({
    required this.totalLeads,
    required this.totalEntries,
    required this.uniqueLeads,
    required this.duplicateLeads,
    required this.transferred,
    required this.lost,
    required this.inQualification,
    required this.conversionRate,
    required this.entriesCohort,
    this.lostByEntry = 0,
    this.transferredByEntry = 0,
  });

  final int totalLeads;

  /// Cards criados no período (pode incluir estados fora do funil SDR).
  final int totalEntries;

  /// Leads únicos após dedup (telefone → e-mail → nome).
  final int uniqueLeads;
  final int duplicateLeads;
  final int transferred;
  final int lost;
  final int inQualification;

  /// Percentual 0–100.
  final double conversionRate;

  /// Total real de entradas no período (base do funil por coorte).
  final int entriesCohort;

  /// Perdidos cujo card foi criado no período (leitura por entrada — base do
  /// funil do web). `lost` é a leitura pela data da perda.
  final int lostByEntry;

  /// Transferidos cujo lead de origem foi criado no período.
  final int transferredByEntry;

  static const SdrSummary zero = SdrSummary(
    totalLeads: 0,
    totalEntries: 0,
    uniqueLeads: 0,
    duplicateLeads: 0,
    transferred: 0,
    lost: 0,
    inQualification: 0,
    conversionRate: 0,
    entriesCohort: 0,
  );

  factory SdrSummary.fromJson(Map<String, dynamic> json) {
    return SdrSummary(
      totalLeads: _asInt(json['totalLeads']),
      totalEntries: _asInt(json['totalEntries'] ?? json['totalLeads']),
      uniqueLeads: _asInt(json['uniqueLeads']),
      duplicateLeads: _asInt(json['duplicateLeads']),
      transferred: _asInt(json['transferred']),
      lost: _asInt(json['lost']),
      inQualification: _asInt(json['inQualification']),
      conversionRate: _asDouble(json['conversionRate']),
      entriesCohort: _asInt(json['entriesCohort'] ?? json['totalEntries']),
      lostByEntry: _asInt(json['lostByEntry']),
      transferredByEntry: _asInt(json['transferredByEntry']),
    );
  }
}

/// Desempenho de um agente SDR no período.
class SdrAgentMetric {
  const SdrAgentMetric({
    required this.agentId,
    required this.agentName,
    required this.totalLeads,
    required this.transferred,
    required this.lost,
    required this.inQualification,
    required this.conversionRate,
  });

  final String agentId;
  final String agentName;
  final int totalLeads;
  final int transferred;
  final int lost;
  final int inQualification;
  final double conversionRate;

  factory SdrAgentMetric.fromJson(Map<String, dynamic> json) {
    return SdrAgentMetric(
      agentId: _asString(json['agentId']),
      agentName: _asString(json['agentName'], 'Sem responsável'),
      totalLeads: _asInt(json['totalLeads']),
      transferred: _asInt(json['transferred']),
      lost: _asInt(json['lost']),
      inQualification: _asInt(json['inQualification']),
      conversionRate: _asDouble(json['conversionRate']),
    );
  }
}

/// Desempenho por origem/mídia do lead.
class SdrSourceMetric {
  const SdrSourceMetric({
    required this.source,
    required this.totalLeads,
    required this.transferred,
    required this.lost,
    required this.conversionRate,
    required this.averageValue,
  });

  final String source;
  final int totalLeads;
  final int transferred;
  final int lost;
  final double conversionRate;
  final double averageValue;

  factory SdrSourceMetric.fromJson(Map<String, dynamic> json) {
    return SdrSourceMetric(
      source: _asString(json['source'], 'Sem origem'),
      totalLeads: _asInt(json['totalLeads']),
      transferred: _asInt(json['transferred']),
      lost: _asInt(json['lost']),
      conversionRate: _asDouble(json['conversionRate']),
      averageValue: _asDouble(json['averageValue']),
    );
  }
}

/// Desempenho por campanha.
class SdrCampaignMetric {
  const SdrCampaignMetric({
    required this.campaign,
    required this.totalLeads,
    required this.transferred,
    required this.lost,
    required this.inQualification,
    required this.conversionRate,
  });

  final String campaign;
  final int totalLeads;
  final int transferred;
  final int lost;
  final int inQualification;
  final double conversionRate;

  factory SdrCampaignMetric.fromJson(Map<String, dynamic> json) {
    return SdrCampaignMetric(
      campaign: _asString(json['campaign'], 'Sem campanha'),
      totalLeads: _asInt(json['totalLeads']),
      transferred: _asInt(json['transferred']),
      lost: _asInt(json['lost']),
      inQualification: _asInt(json['inQualification']),
      conversionRate: _asDouble(json['conversionRate']),
    );
  }
}

/// Leads por qualificação (quente/morno/frio…).
class SdrQualificationMetric {
  const SdrQualificationMetric({
    required this.qualification,
    required this.totalLeads,
    required this.transferred,
    required this.conversionRate,
  });

  final String qualification;
  final int totalLeads;
  final int transferred;
  final double conversionRate;

  factory SdrQualificationMetric.fromJson(Map<String, dynamic> json) {
    return SdrQualificationMetric(
      qualification: _asString(json['qualification'], 'Sem qualificação'),
      totalLeads: _asInt(json['totalLeads']),
      transferred: _asInt(json['transferred']),
      conversionRate: _asDouble(json['conversionRate']),
    );
  }
}

/// Entradas por dia (fuso Brasília) com dedup.
class SdrDayPoint {
  const SdrDayPoint({
    required this.date,
    required this.total,
    required this.unique,
    required this.duplicates,
  });

  final DateTime? date;
  final int total;
  final int unique;
  final int duplicates;

  factory SdrDayPoint.fromJson(Map<String, dynamic> json) {
    return SdrDayPoint(
      date: _asDate(json['date']),
      total: _asInt(json['total']),
      unique: _asInt(json['unique']),
      duplicates: _asInt(json['duplicates']),
    );
  }
}

/// Evolução mensal.
class SdrMonthPoint {
  const SdrMonthPoint({
    required this.month,
    required this.totalLeads,
    required this.transferred,
    required this.lost,
  });

  final String month;
  final int totalLeads;
  final int transferred;
  final int lost;

  factory SdrMonthPoint.fromJson(Map<String, dynamic> json) {
    return SdrMonthPoint(
      month: _asString(json['month']),
      totalLeads: _asInt(json['totalLeads']),
      transferred: _asInt(json['transferred']),
      lost: _asInt(json['lost']),
    );
  }
}

/// Motivo de perda + contagem.
class SdrLossReason {
  const SdrLossReason({required this.reason, required this.count});

  final String reason;
  final int count;

  factory SdrLossReason.fromJson(Map<String, dynamic> json) {
    return SdrLossReason(
      reason: _asString(json['reason'], 'Sem motivo'),
      count: _asInt(json['count']),
    );
  }
}

/// Corretores que mais receberam leads transferidos.
class SdrTopBroker {
  const SdrTopBroker({
    required this.brokerId,
    required this.brokerName,
    required this.received,
  });

  final String brokerId;
  final String brokerName;
  final int received;

  factory SdrTopBroker.fromJson(Map<String, dynamic> json) {
    return SdrTopBroker(
      brokerId: _asString(json['brokerId']),
      brokerName: _asString(json['brokerName'], 'Sem nome'),
      received: _asInt(json['received']),
    );
  }
}

/// SLA de atendimento no WhatsApp (snapshot + primeira resposta no período).
class SdrWhatsappMetrics {
  const SdrWhatsappMetrics({
    required this.awaitingReplyCount,
    required this.avgFirstResponseMinutes,
    required this.medianFirstResponseMinutes,
    required this.firstResponseSampleSize,
    required this.periodStart,
    required this.periodEnd,
  });

  final int awaitingReplyCount;
  final double? avgFirstResponseMinutes;
  final double? medianFirstResponseMinutes;
  final int firstResponseSampleSize;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  factory SdrWhatsappMetrics.fromJson(Map<String, dynamic> json) {
    return SdrWhatsappMetrics(
      awaitingReplyCount: _asInt(json['awaitingReplyCount']),
      avgFirstResponseMinutes: _asDoubleOrNull(json['avgFirstResponseMinutes']),
      medianFirstResponseMinutes:
          _asDoubleOrNull(json['medianFirstResponseMinutes']),
      firstResponseSampleSize: _asInt(json['firstResponseSampleSize']),
      periodStart: _asDate(json['firstResponsePeriodStart']),
      periodEnd: _asDate(json['firstResponsePeriodEnd']),
    );
  }
}

/// Payload completo consumido pelo dashboard SDR do app (subconjunto do
/// `SdrMetrics` do web — só o que a tela mobile exibe).
class SdrMetrics {
  const SdrMetrics({
    required this.summary,
    required this.byAgent,
    required this.bySource,
    required this.byCampaign,
    required this.byQualification,
    required this.byMonth,
    required this.leadsByDay,
    required this.lossReasons,
    required this.topBrokers,
    this.whatsapp,
    this.byColumn = const [],
    this.listTotals = SdrListTotals.zero,
    this.transferAggregates = SdrTransferAggregates.empty,
  });

  final SdrSummary summary;
  final List<SdrAgentMetric> byAgent;
  final List<SdrSourceMetric> bySource;
  final List<SdrCampaignMetric> byCampaign;
  final List<SdrQualificationMetric> byQualification;
  final List<SdrMonthPoint> byMonth;
  final List<SdrDayPoint> leadsByDay;
  final List<SdrLossReason> lossReasons;
  final List<SdrTopBroker> topBrokers;
  final SdrWhatsappMetrics? whatsapp;

  /// Leads por coluna do funil SDR (aba Funil do web).
  final List<SdrColumnMetric> byColumn;

  /// Tamanho real das listas de leads — vem mesmo com `lists=none`.
  final SdrListTotals listTotals;

  /// Agregados de transferência (também vêm com `lists=none`).
  final SdrTransferAggregates transferAggregates;

  static const SdrMetrics empty = SdrMetrics(
    summary: SdrSummary.zero,
    byAgent: [],
    bySource: [],
    byCampaign: [],
    byQualification: [],
    byMonth: [],
    leadsByDay: [],
    lossReasons: [],
    topBrokers: [],
  );

  factory SdrMetrics.fromJson(Map<String, dynamic> json) {
    final summaryRaw = json['summary'];
    return SdrMetrics(
      summary: summaryRaw is Map
          ? SdrSummary.fromJson(Map<String, dynamic>.from(summaryRaw))
          : SdrSummary.zero,
      byAgent: _asMapList(json['byAgent'])
          .map(SdrAgentMetric.fromJson)
          .toList(growable: false),
      bySource: _asMapList(json['bySource'])
          .map(SdrSourceMetric.fromJson)
          .toList(growable: false),
      byCampaign: _asMapList(json['byCampaign'])
          .map(SdrCampaignMetric.fromJson)
          .toList(growable: false),
      byQualification: _asMapList(json['byQualification'])
          .map(SdrQualificationMetric.fromJson)
          .toList(growable: false),
      byMonth: _asMapList(json['byMonth'])
          .map(SdrMonthPoint.fromJson)
          .toList(growable: false),
      leadsByDay: _asMapList(json['leadsByDay'])
          .map(SdrDayPoint.fromJson)
          .toList(growable: false),
      lossReasons: _asMapList(json['lossReasons'])
          .map(SdrLossReason.fromJson)
          .toList(growable: false),
      topBrokers: _asMapList(json['topBrokers'])
          .map(SdrTopBroker.fromJson)
          .toList(growable: false),
      whatsapp: json['whatsapp'] is Map
          ? SdrWhatsappMetrics.fromJson(
              Map<String, dynamic>.from(json['whatsapp'] as Map))
          : null,
      byColumn: (_asMapList(json['byColumn'])
              .map(SdrColumnMetric.fromJson)
              .toList()
            ..sort((a, b) => a.position.compareTo(b.position)))
          .toList(growable: false),
      listTotals: json['listTotals'] is Map
          ? SdrListTotals.fromJson(
              Map<String, dynamic>.from(json['listTotals'] as Map))
          : SdrListTotals.fromLists(json),
      transferAggregates: json['transferAggregates'] is Map
          ? SdrTransferAggregates.fromJson(
              Map<String, dynamic>.from(json['transferAggregates'] as Map))
          : SdrTransferAggregates.empty,
    );
  }
}

/// Funil (projeto do Kanban) — catálogo que traduz equipe em `projectId`.
/// Só ativos e não pessoais entram (`filterDashboardKanbanProjects` do web).
class SdrProjectOption {
  const SdrProjectOption({
    required this.id,
    required this.name,
    this.teamId,
    this.teamIds = const [],
  });

  final String id;
  final String name;
  final String? teamId;

  /// Equipes vinculadas por compartilhamento (`kanban_project_teams`).
  final List<String> teamIds;

  /// `projectBelongsToTeams` do web: equipe principal OU compartilhada.
  bool belongsToAny(Set<String> teams) {
    if (teams.isEmpty) return false;
    final primary = teamId?.trim() ?? '';
    if (primary.isNotEmpty && teams.contains(primary)) return true;
    return teamIds.any((t) => teams.contains(t.trim()));
  }

  static SdrProjectOption? tryParse(Map<String, dynamic> json) {
    final id = _asString(json['id']);
    if (id.isEmpty) return null;
    final status = _asString(json['status']).toLowerCase();
    if (json['isPersonal'] == true) return null;
    if (status.isNotEmpty && status != 'active') return null;
    final shared = <String>[];
    final rawTeams = json['teamIds'];
    if (rawTeams is List) {
      for (final t in rawTeams) {
        final v = t?.toString().trim() ?? '';
        if (v.isNotEmpty) shared.add(v);
      }
    }
    final teamObjs = json['teams'];
    if (teamObjs is List) {
      for (final t in teamObjs) {
        if (t is Map && t['id'] != null) shared.add(t['id'].toString());
      }
    }
    final team = json['team'];
    return SdrProjectOption(
      id: id,
      name: _asString(json['name'], 'Funil'),
      teamId: json['teamId']?.toString() ??
          (team is Map ? team['id']?.toString() : null),
      teamIds: shared,
    );
  }
}

/// Opção genérica de filtro (campanha, pessoa, tag, mídia).
class SdrFilterOption {
  const SdrFilterOption({required this.value, required this.label, this.hint});

  final String value;
  final String label;

  /// Procedência curta (ex.: "Meta", "Sistema") mostrada no seletor.
  final String? hint;
}

/// Leads por coluna do funil (ordenados pela posição da coluna).
class SdrColumnMetric {
  const SdrColumnMetric({
    required this.columnId,
    required this.columnTitle,
    required this.position,
    required this.totalLeads,
  });

  final String columnId;
  final String columnTitle;
  final int position;
  final int totalLeads;

  factory SdrColumnMetric.fromJson(Map<String, dynamic> json) {
    return SdrColumnMetric(
      columnId: _asString(json['columnId']),
      columnTitle: _asString(json['columnTitle'], 'Coluna'),
      position: _asInt(json['position']),
      totalLeads: _asInt(json['totalLeads']),
    );
  }
}

/// Tamanho real das listas de leads (vem mesmo com `lists=none`).
class SdrListTotals {
  const SdrListTotals({
    required this.transferList,
    required this.lostLeadsList,
    required this.qualificationLeadsList,
    required this.periodLeadsList,
  });

  final int transferList;
  final int lostLeadsList;
  final int qualificationLeadsList;
  final int periodLeadsList;

  static const SdrListTotals zero = SdrListTotals(
    transferList: 0,
    lostLeadsList: 0,
    qualificationLeadsList: 0,
    periodLeadsList: 0,
  );

  factory SdrListTotals.fromJson(Map<String, dynamic> json) => SdrListTotals(
        transferList: _asInt(json['transferList']),
        lostLeadsList: _asInt(json['lostLeadsList']),
        qualificationLeadsList: _asInt(json['qualificationLeadsList']),
        periodLeadsList: _asInt(json['periodLeadsList']),
      );

  /// Back antigo (sem `listTotals`): conta pelas próprias listas.
  factory SdrListTotals.fromLists(Map<String, dynamic> json) => SdrListTotals(
        transferList: (json['transferList'] as List?)?.length ?? 0,
        lostLeadsList: (json['lostLeadsList'] as List?)?.length ?? 0,
        qualificationLeadsList:
            (json['qualificationLeadsList'] as List?)?.length ?? 0,
        periodLeadsList: (json['periodLeadsList'] as List?)?.length ?? 0,
      );
}

/// Par rótulo + contagem dos agregados de transferência.
class SdrLabelCount {
  const SdrLabelCount({required this.label, required this.count});

  final String label;
  final int count;

  factory SdrLabelCount.fromJson(Map<String, dynamic> json) => SdrLabelCount(
        label: _asString(json['label'], 'Não identificado'),
        count: _asInt(json['count']),
      );
}

/// Agregados de transferência (`transferAggregates`).
class SdrTransferAggregates {
  const SdrTransferAggregates({
    required this.byDestinationTeam,
    required this.byDestinationFunnel,
    required this.byAttendant,
    required this.byTransferredBy,
    required this.byResponsible,
  });

  final List<SdrLabelCount> byDestinationTeam;
  final List<SdrLabelCount> byDestinationFunnel;

  /// SDR dono do lead na tarefa original.
  final List<SdrLabelCount> byAttendant;

  /// Quem executou a transferência no Kanban.
  final List<SdrLabelCount> byTransferredBy;

  /// Corretor que recebeu.
  final List<SdrLabelCount> byResponsible;

  static const SdrTransferAggregates empty = SdrTransferAggregates(
    byDestinationTeam: [],
    byDestinationFunnel: [],
    byAttendant: [],
    byTransferredBy: [],
    byResponsible: [],
  );

  bool get isEmpty =>
      byDestinationTeam.isEmpty &&
      byDestinationFunnel.isEmpty &&
      byAttendant.isEmpty &&
      byTransferredBy.isEmpty &&
      byResponsible.isEmpty;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  /// `transferAggToGroups` do web: rótulo que é UUID vira "Não identificado"
  /// e as contagens se somam; ordena do maior para o menor.
  static List<SdrLabelCount> _grouped(dynamic raw) {
    final map = <String, int>{};
    for (final r in _asMapList(raw).map(SdrLabelCount.fromJson)) {
      final l = r.label.trim();
      final label = l.isEmpty || _uuid.hasMatch(l) ? 'Não identificado' : l;
      map[label] = (map[label] ?? 0) + r.count;
    }
    return map.entries
        .map((e) => SdrLabelCount(label: e.key, count: e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  factory SdrTransferAggregates.fromJson(Map<String, dynamic> json) =>
      SdrTransferAggregates(
        byDestinationTeam: _grouped(json['byDestinationTeam']),
        byDestinationFunnel: _grouped(json['byDestinationFunnel']),
        byAttendant: _grouped(json['byAttendant']),
        byTransferredBy: _grouped(json['byTransferredBy']),
        byResponsible: _grouped(json['byResponsible']),
      );
}

/// Equipe (opção do filtro do dashboard).
///
/// 29/09/2026 (sdr-09): vem de `GET /kanban/teams?allActive=true`, a mesma
/// fonte do web (antes era `GET /teams`, que devolve outro conjunto).
class SdrTeamOption {
  const SdrTeamOption({required this.id, required this.name});

  final String id;
  final String name;

  factory SdrTeamOption.fromJson(Map<String, dynamic> json) {
    return SdrTeamOption(
      id: _asString(json['id']),
      name: _asString(json['name'], 'Equipe'),
    );
  }
}
