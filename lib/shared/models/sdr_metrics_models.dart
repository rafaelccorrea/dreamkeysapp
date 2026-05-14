// Modelos alinhados a `SdrMetrics` em `imobx-front/src/services/kanbanMetricsApi.ts`
// e `imobx/src/kanban/kanban-analytics.service.ts` — apenas campos usados na UI móvel.

int _iv(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is double) return v.round();
  return int.tryParse(v.toString()) ?? 0;
}

double _dv(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

String _sv(dynamic v) => v?.toString() ?? '';

class SdrSummary {
  final int totalLeads;
  final int transferred;
  final int lost;
  final int inQualification;
  final double conversionRate;

  SdrSummary({
    required this.totalLeads,
    required this.transferred,
    required this.lost,
    required this.inQualification,
    required this.conversionRate,
  });

  factory SdrSummary.fromJson(Map<String, dynamic>? json) {
    final j = json ?? {};
    return SdrSummary(
      totalLeads: _iv(j['totalLeads']),
      transferred: _iv(j['transferred']),
      lost: _iv(j['lost']),
      inQualification: _iv(j['inQualification']),
      conversionRate: _dv(j['conversionRate']),
    );
  }
}

class SdrAgentRow {
  final String agentId;
  final String agentName;
  final int totalLeads;
  final int transferred;
  final int lost;
  final int inQualification;
  final double conversionRate;

  SdrAgentRow({
    required this.agentId,
    required this.agentName,
    required this.totalLeads,
    required this.transferred,
    required this.lost,
    required this.inQualification,
    required this.conversionRate,
  });

  factory SdrAgentRow.fromJson(Map<String, dynamic> j) {
    return SdrAgentRow(
      agentId: _sv(j['agentId']),
      agentName: _sv(j['agentName']),
      totalLeads: _iv(j['totalLeads']),
      transferred: _iv(j['transferred']),
      lost: _iv(j['lost']),
      inQualification: _iv(j['inQualification']),
      conversionRate: _dv(j['conversionRate']),
    );
  }
}

class SdrSourceRow {
  final String source;
  final int totalLeads;
  final int transferred;
  final int lost;
  final double conversionRate;
  final double averageValue;

  SdrSourceRow({
    required this.source,
    required this.totalLeads,
    required this.transferred,
    required this.lost,
    required this.conversionRate,
    required this.averageValue,
  });

  factory SdrSourceRow.fromJson(Map<String, dynamic> j) {
    return SdrSourceRow(
      source: _sv(j['source']),
      totalLeads: _iv(j['totalLeads']),
      transferred: _iv(j['transferred']),
      lost: _iv(j['lost']),
      conversionRate: _dv(j['conversionRate']),
      averageValue: _dv(j['averageValue']),
    );
  }
}

class SdrChannelRow {
  final String channel;
  final String label;
  final int totalLeads;
  final int transferred;
  final int lost;
  final double conversionRate;
  final double averageValue;

  SdrChannelRow({
    required this.channel,
    required this.label,
    required this.totalLeads,
    required this.transferred,
    required this.lost,
    required this.conversionRate,
    required this.averageValue,
  });

  factory SdrChannelRow.fromJson(Map<String, dynamic> j) {
    return SdrChannelRow(
      channel: _sv(j['channel']),
      label: _sv(j['label']),
      totalLeads: _iv(j['totalLeads']),
      transferred: _iv(j['transferred']),
      lost: _iv(j['lost']),
      conversionRate: _dv(j['conversionRate']),
      averageValue: _dv(j['averageValue']),
    );
  }
}

class SdrTransferRow {
  final String transferId;
  final String leadTitle;
  final String source;
  final String campaign;
  final String fromTeam;
  final String toTeam;
  final String transferredAt;
  final String sdrAgentName;

  SdrTransferRow({
    required this.transferId,
    required this.leadTitle,
    required this.source,
    required this.campaign,
    required this.fromTeam,
    required this.toTeam,
    required this.transferredAt,
    required this.sdrAgentName,
  });

  factory SdrTransferRow.fromJson(Map<String, dynamic> j) {
    return SdrTransferRow(
      transferId: _sv(j['transferId']),
      leadTitle: _sv(j['leadTitle']),
      source: _sv(j['source']),
      campaign: _sv(j['campaign']),
      fromTeam: _sv(j['fromTeam']),
      toTeam: _sv(j['toTeam']),
      transferredAt: _sv(j['transferredAt']),
      sdrAgentName: _sv(j['sdrAgentName']),
    );
  }
}

class SdrWhatsappSnapshot {
  final int awaitingReplyCount;
  final double? avgFirstResponseMinutes;
  final double? medianFirstResponseMinutes;
  final int firstResponseSampleSize;

  SdrWhatsappSnapshot({
    required this.awaitingReplyCount,
    required this.avgFirstResponseMinutes,
    required this.medianFirstResponseMinutes,
    required this.firstResponseSampleSize,
  });

  factory SdrWhatsappSnapshot.fromJson(Map<String, dynamic>? j) {
    if (j == null) {
      return SdrWhatsappSnapshot(
        awaitingReplyCount: 0,
        avgFirstResponseMinutes: null,
        medianFirstResponseMinutes: null,
        firstResponseSampleSize: 0,
      );
    }
    return SdrWhatsappSnapshot(
      awaitingReplyCount: _iv(j['awaitingReplyCount']),
      avgFirstResponseMinutes: j['avgFirstResponseMinutes'] == null
          ? null
          : _dv(j['avgFirstResponseMinutes']),
      medianFirstResponseMinutes: j['medianFirstResponseMinutes'] == null
          ? null
          : _dv(j['medianFirstResponseMinutes']),
      firstResponseSampleSize: _iv(j['firstResponseSampleSize']),
    );
  }
}

class SdrMetricsPayload {
  final SdrSummary summary;
  final List<SdrAgentRow> byAgent;
  final List<SdrSourceRow> bySource;
  final List<SdrChannelRow> byChannel;
  final List<SdrTransferRow> transferList;
  final SdrWhatsappSnapshot? whatsapp;

  SdrMetricsPayload({
    required this.summary,
    required this.byAgent,
    required this.bySource,
    required this.byChannel,
    required this.transferList,
    required this.whatsapp,
  });

  factory SdrMetricsPayload.fromJson(Map<String, dynamic> json) {
    List<T> mapList<T>(dynamic raw, T Function(Map<String, dynamic>) f) {
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((e) => f(Map<String, dynamic>.from(e)))
          .toList();
    }

    return SdrMetricsPayload(
      summary: SdrSummary.fromJson(
        json['summary'] is Map
            ? Map<String, dynamic>.from(json['summary'] as Map)
            : null,
      ),
      byAgent: mapList(json['byAgent'], SdrAgentRow.fromJson),
      bySource: mapList(json['bySource'], SdrSourceRow.fromJson),
      byChannel: mapList(json['byChannel'], SdrChannelRow.fromJson),
      transferList: mapList(json['transferList'], SdrTransferRow.fromJson),
      whatsapp: json['whatsapp'] is Map
          ? SdrWhatsappSnapshot.fromJson(
              Map<String, dynamic>.from(json['whatsapp'] as Map),
            )
          : null,
    );
  }
}
