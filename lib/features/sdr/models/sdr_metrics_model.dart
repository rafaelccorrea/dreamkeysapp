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
    );
  }
}

/// Equipe (opção do filtro do dashboard). Vem de `GET /teams`.
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
