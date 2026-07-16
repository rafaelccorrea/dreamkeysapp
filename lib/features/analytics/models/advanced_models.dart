// Models do Analytics Avançado — espelham `useAdvancedAnalytics` do
// imobx-front: performance da empresa (`/matches/performance/dashboard`),
// matches pendentes (`/matches?status=pending`), performance de corretores
// (`/ai-assistant/analytics/broker-performance`), churn
// (`/ai-assistant/predictive/churn`), funil (`/dashboard/conversion-funnel`)
// e captações (`/analytics/captures/statistics`).

import 'parse_utils.dart';

/// Estatísticas agregadas da empresa (matches + tarefas).
class CompanyStats {
  final int totalMatches;
  final int pendingMatches;
  final int acceptedMatches;
  final int ignoredMatches;
  final double avgAcceptanceRate;
  final double avgMatchScore;
  final int totalTasksCreated;
  final int totalTasksCompleted;

  const CompanyStats({
    required this.totalMatches,
    required this.pendingMatches,
    required this.acceptedMatches,
    required this.ignoredMatches,
    required this.avgAcceptanceRate,
    required this.avgMatchScore,
    required this.totalTasksCreated,
    required this.totalTasksCompleted,
  });

  factory CompanyStats.fromJson(Map<String, dynamic> json) {
    return CompanyStats(
      totalMatches: parseInt(json['totalMatches']),
      pendingMatches: parseInt(json['pendingMatches']),
      acceptedMatches: parseInt(json['acceptedMatches']),
      ignoredMatches: parseInt(json['ignoredMatches']),
      avgAcceptanceRate: parseDouble(json['avgAcceptanceRate']),
      avgMatchScore: parseDouble(json['avgMatchScore']),
      totalTasksCreated: parseInt(json['totalTasksCreated']),
      totalTasksCompleted: parseInt(json['totalTasksCompleted']),
    );
  }

  static const empty = CompanyStats(
    totalMatches: 0,
    pendingMatches: 0,
    acceptedMatches: 0,
    ignoredMatches: 0,
    avgAcceptanceRate: 0,
    avgMatchScore: 0,
    totalTasksCreated: 0,
    totalTasksCompleted: 0,
  );

  double get taskCompletionRate =>
      totalTasksCreated > 0 ? totalTasksCompleted / totalTasksCreated * 100 : 0;
}

/// Dashboard de performance (`GET /matches/performance/dashboard`).
class PerformanceDashboard {
  final CompanyStats companyStats;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  const PerformanceDashboard({
    required this.companyStats,
    this.periodStart,
    this.periodEnd,
  });

  factory PerformanceDashboard.fromJson(Map<String, dynamic> json) {
    final body = unwrapData(json);
    final period = parseMap(body['period']);
    return PerformanceDashboard(
      companyStats: parseMap(body['companyStats']) != null
          ? CompanyStats.fromJson(parseMap(body['companyStats'])!)
          : CompanyStats.empty,
      periodStart: parseDate(period?['start']),
      periodEnd: parseDate(period?['end']),
    );
  }
}

/// Match pendente (linha da lista de pendências).
class PendingMatch {
  final String id;
  final String clientName;
  final String propertyTitle;
  final double matchScore;
  final DateTime? createdAt;

  const PendingMatch({
    required this.id,
    required this.clientName,
    required this.propertyTitle,
    required this.matchScore,
    required this.createdAt,
  });

  factory PendingMatch.fromJson(Map<String, dynamic> json) {
    final client = parseMap(json['client']);
    final property = parseMap(json['property']);
    return PendingMatch(
      id: parseString(json['id']),
      clientName: parseString(client?['name'], 'Cliente não informado'),
      propertyTitle:
          parseString(property?['title'], 'Propriedade não informada'),
      matchScore: parseDouble(json['matchScore']),
      createdAt: parseDate(json['createdAt']),
    );
  }

  int get daysPending {
    final created = createdAt;
    if (created == null) return 0;
    return DateTime.now().difference(created).inDays;
  }
}

/// Resumo dos matches pendentes (contas derivadas no cliente — paridade web:
/// atraso > 7 dias, atenção entre 3 e 7).
class PendingMatchesSummary {
  final int total;
  final int overdue;
  final int warning;
  final List<PendingMatch> items;

  const PendingMatchesSummary({
    required this.total,
    required this.overdue,
    required this.warning,
    required this.items,
  });

  factory PendingMatchesSummary.fromMatches(
    List<PendingMatch> matches, {
    int total = 0,
  }) {
    var overdue = 0;
    var warning = 0;
    for (final m in matches) {
      final days = m.daysPending;
      if (days > 7) {
        overdue++;
      } else if (days > 3) {
        warning++;
      }
    }
    return PendingMatchesSummary(
      total: total > 0 ? total : matches.length,
      overdue: overdue,
      warning: warning,
      items: matches,
    );
  }

  static const empty =
      PendingMatchesSummary(total: 0, overdue: 0, warning: 0, items: []);
}

/// Performance individual de corretor (IA — broker-performance).
class BrokerPerformance {
  final String brokerId;
  final String brokerName;
  final double overallScore;
  final int salesCount;
  final double totalSalesValue;
  final double conversionRate;
  final double averageSaleTime;
  final int leadsGenerated;
  final int visitsCompleted;
  final String trend; // improving | stable | declining

  const BrokerPerformance({
    required this.brokerId,
    required this.brokerName,
    required this.overallScore,
    required this.salesCount,
    required this.totalSalesValue,
    required this.conversionRate,
    required this.averageSaleTime,
    required this.leadsGenerated,
    required this.visitsCompleted,
    required this.trend,
  });

  factory BrokerPerformance.fromJson(Map<String, dynamic> json) {
    return BrokerPerformance(
      brokerId: parseString(json['brokerId'], parseString(json['id'])),
      brokerName: parseString(json['brokerName'], 'Corretor'),
      overallScore: parseDouble(json['overallScore']),
      salesCount: parseInt(json['salesCount']),
      totalSalesValue: parseDouble(json['totalSalesValue']),
      conversionRate: parseDouble(json['conversionRate']),
      averageSaleTime: parseDouble(json['averageSaleTime']),
      leadsGenerated: parseInt(json['leadsGenerated']),
      visitsCompleted: parseInt(json['visitsCompleted']),
      trend: parseString(json['trend'], 'stable'),
    );
  }

  String get trendLabel {
    switch (trend) {
      case 'improving':
        return 'Melhorando';
      case 'declining':
        return 'Declinando';
      default:
        return 'Estável';
    }
  }
}

/// Cliente em risco de churn (IA — predictive/churn).
class ChurnPrediction {
  final String clientId;
  final String clientName;
  final double churnRiskScore;
  final String riskLevel; // high | medium | low
  final int daysSinceLastContact;
  final List<String> riskFactors;
  final List<String> recommendedActions;
  final double recoveryProbability;

  const ChurnPrediction({
    required this.clientId,
    required this.clientName,
    required this.churnRiskScore,
    required this.riskLevel,
    required this.daysSinceLastContact,
    required this.riskFactors,
    required this.recommendedActions,
    required this.recoveryProbability,
  });

  factory ChurnPrediction.fromJson(Map<String, dynamic> json) {
    return ChurnPrediction(
      clientId: parseString(json['clientId'], parseString(json['id'])),
      clientName: parseString(json['clientName'], 'Cliente'),
      churnRiskScore: parseDouble(json['churnRiskScore']),
      riskLevel: parseString(json['riskLevel'], 'low'),
      daysSinceLastContact: parseInt(json['daysSinceLastContact']),
      riskFactors: parseStringList(json['riskFactors']),
      recommendedActions: parseStringList(json['recommendedActions']),
      recoveryProbability: parseDouble(json['recoveryProbability']),
    );
  }

  String get riskLabel {
    switch (riskLevel) {
      case 'high':
        return 'Alto';
      case 'medium':
        return 'Médio';
      default:
        return 'Baixo';
    }
  }
}

/// Agregado de churn calculado no cliente (paridade com o hook web).
class ChurnAnalysis {
  final int totalClients;
  final int highRisk;
  final int mediumRisk;
  final int lowRisk;
  final double churnRate;
  final List<ChurnPrediction> atRiskClients;

  const ChurnAnalysis({
    required this.totalClients,
    required this.highRisk,
    required this.mediumRisk,
    required this.lowRisk,
    required this.churnRate,
    required this.atRiskClients,
  });

  factory ChurnAnalysis.fromPredictions(List<ChurnPrediction> list) {
    final high = list.where((c) => c.riskLevel == 'high').length;
    final medium = list.where((c) => c.riskLevel == 'medium').length;
    final low = list.where((c) => c.riskLevel == 'low').length;
    final sorted = [...list]
      ..sort((a, b) => b.churnRiskScore.compareTo(a.churnRiskScore));
    return ChurnAnalysis(
      totalClients: list.length,
      highRisk: high,
      mediumRisk: medium,
      lowRisk: low,
      churnRate: list.isNotEmpty ? high / list.length * 100 : 0,
      atRiskClients: sorted,
    );
  }

  static const empty = ChurnAnalysis(
    totalClients: 0,
    highRisk: 0,
    mediumRisk: 0,
    lowRisk: 0,
    churnRate: 0,
    atRiskClients: [],
  );

  bool get hasData => totalClients > 0;
}

/// Etapa do funil de conversão.
class FunnelStage {
  final String name;
  final int count;
  final double? conversionRate; // vs etapa anterior
  final double conversionRateFromTotal;

  const FunnelStage({
    required this.name,
    required this.count,
    required this.conversionRate,
    required this.conversionRateFromTotal,
  });

  factory FunnelStage.fromJson(Map<String, dynamic> json) {
    return FunnelStage(
      name: parseString(json['name'], 'Etapa'),
      count: parseInt(json['count']),
      conversionRate: parseDoubleOrNull(json['conversionRate']),
      conversionRateFromTotal: parseDouble(json['conversionRateFromTotal']),
    );
  }
}

class FunnelInsight {
  final String type; // success | info | warning | error
  final String title;
  final String description;
  final List<String> recommendations;

  const FunnelInsight({
    required this.type,
    required this.title,
    required this.description,
    required this.recommendations,
  });

  factory FunnelInsight.fromJson(Map<String, dynamic> json) {
    return FunnelInsight(
      type: parseString(json['type'], 'info'),
      title: parseString(json['title'], 'Insight'),
      description: parseString(json['description']),
      recommendations: parseStringList(json['recommendations']),
    );
  }
}

class FunnelAnalysis {
  final String summary;
  final List<String> strengths;
  final List<String> bottlenecks;
  final List<String> opportunities;
  final List<FunnelInsight> insights;
  final double overallScore;

  const FunnelAnalysis({
    required this.summary,
    required this.strengths,
    required this.bottlenecks,
    required this.opportunities,
    required this.insights,
    required this.overallScore,
  });

  factory FunnelAnalysis.fromJson(Map<String, dynamic> json) {
    return FunnelAnalysis(
      summary: parseString(json['summary']),
      strengths: parseStringList(json['strengths']),
      bottlenecks: parseStringList(json['bottlenecks']),
      opportunities: parseStringList(json['opportunities']),
      insights: parseMapList(json['insights'])
          .map(FunnelInsight.fromJson)
          .toList(growable: false),
      overallScore: parseDouble(json['overallScore']),
    );
  }
}

/// Funil de conversão (`GET /dashboard/conversion-funnel`).
class ConversionFunnelData {
  final List<FunnelStage> stages;
  final int totalLeads;
  final double overallConversionRate;
  final String period;
  final FunnelAnalysis? analysis;

  const ConversionFunnelData({
    required this.stages,
    required this.totalLeads,
    required this.overallConversionRate,
    required this.period,
    required this.analysis,
  });

  factory ConversionFunnelData.fromJson(Map<String, dynamic> json) {
    final body = unwrapData(json);
    return ConversionFunnelData(
      stages: parseMapList(body['stages'])
          .map(FunnelStage.fromJson)
          .toList(growable: false),
      totalLeads: parseInt(body['totalLeads']),
      overallConversionRate: parseDouble(body['overallConversionRate']),
      period: parseString(body['period']),
      analysis: parseMap(body['analysis']) != null
          ? FunnelAnalysis.fromJson(parseMap(body['analysis'])!)
          : null,
    );
  }
}

/// Ranking de captador.
class CapturerRanking {
  final String capturerId;
  final String capturerName;
  final int propertiesCount;
  final int clientsCount;
  final int totalCaptures;

  const CapturerRanking({
    required this.capturerId,
    required this.capturerName,
    required this.propertiesCount,
    required this.clientsCount,
    required this.totalCaptures,
  });

  factory CapturerRanking.fromJson(Map<String, dynamic> json) {
    return CapturerRanking(
      capturerId: parseString(json['capturerId']),
      capturerName: parseString(json['capturerName'], 'Captador'),
      propertiesCount: parseInt(json['propertiesCount']),
      clientsCount: parseInt(json['clientsCount']),
      totalCaptures: parseInt(json['totalCaptures']),
    );
  }
}

/// Estatísticas de captação (`GET /analytics/captures/statistics`).
class CapturesStats {
  final int totalProperties;
  final int totalClients;
  final List<CapturerRanking> byCapturer;
  final double propertiesSoldRate;
  final double clientsClosedRate;

  const CapturesStats({
    required this.totalProperties,
    required this.totalClients,
    required this.byCapturer,
    required this.propertiesSoldRate,
    required this.clientsClosedRate,
  });

  factory CapturesStats.fromJson(Map<String, dynamic> json) {
    final body = unwrapData(json);
    final conversion = parseMap(body['conversionRate']);
    final ranking = parseMapList(body['byCapturer'])
        .map(CapturerRanking.fromJson)
        .toList()
      ..sort((a, b) => b.totalCaptures.compareTo(a.totalCaptures));
    return CapturesStats(
      totalProperties: parseInt(body['totalProperties']),
      totalClients: parseInt(body['totalClients']),
      byCapturer: ranking,
      propertiesSoldRate: parseDouble(conversion?['propertiesSoldRate']),
      clientsClosedRate: parseDouble(conversion?['clientsClosedRate']),
    );
  }

  bool get hasData =>
      totalProperties > 0 || totalClients > 0 || byCapturer.isNotEmpty;
}
