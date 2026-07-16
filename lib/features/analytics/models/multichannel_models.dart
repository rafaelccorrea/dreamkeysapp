// Models da Análise Multicanal — espelham `analyticsApi.ts` do imobx-front
// (`GET /analytics/public-site/*`). fromJson defensivo em todos.

import 'parse_utils.dart';

/// Cidade em que a empresa possui imóveis (filtro multicanal).
class CityOption {
  final String city;
  final String state;
  final String key; // "Cidade,UF"
  final String label;

  const CityOption({
    required this.city,
    required this.state,
    required this.key,
    required this.label,
  });

  factory CityOption.fromJson(Map<String, dynamic> json) {
    final city = parseString(json['city']);
    final state = parseString(json['state']);
    return CityOption(
      city: city,
      state: state,
      key: parseString(json['key'], '$city,$state'),
      label: parseString(json['label'], '$city – $state'),
    );
  }
}

/// Canal de origem (Instagram, Google Ads, WhatsApp, orgânico…).
class SourceChannel {
  final String channel;
  final String label;
  final int views;
  final int whatsappClicks;
  final int contactIntents;
  final int leads;
  final double spend;
  final double? cpl;
  final double revenue;
  final double? roi;
  final double viewToLeadRate;

  const SourceChannel({
    required this.channel,
    required this.label,
    required this.views,
    required this.whatsappClicks,
    required this.contactIntents,
    required this.leads,
    required this.spend,
    required this.cpl,
    required this.revenue,
    required this.roi,
    required this.viewToLeadRate,
  });

  factory SourceChannel.fromJson(Map<String, dynamic> json) {
    return SourceChannel(
      channel: parseString(json['channel'], 'unknown'),
      label: parseString(json['label'], parseString(json['channel'], 'Canal')),
      views: parseInt(json['views']),
      whatsappClicks: parseInt(json['whatsappClicks']),
      contactIntents: parseInt(json['contactIntents']),
      leads: parseInt(json['leads']),
      spend: parseDouble(json['spend']),
      cpl: parseDoubleOrNull(json['cpl']),
      revenue: parseDouble(json['revenue']),
      roi: parseDoubleOrNull(json['roi']),
      viewToLeadRate: parseDouble(json['viewToLeadRate']),
    );
  }
}

/// Ponto diário da série (leads/investimento por canal).
class SourceDailyPoint {
  final String date; // YYYY-MM-DD
  final String channel;
  final int leads;
  final double spend;

  const SourceDailyPoint({
    required this.date,
    required this.channel,
    required this.leads,
    required this.spend,
  });

  factory SourceDailyPoint.fromJson(Map<String, dynamic> json) {
    return SourceDailyPoint(
      date: parseString(json['date']),
      channel: parseString(json['channel']),
      leads: parseInt(json['leads']),
      spend: parseDouble(json['spend']),
    );
  }
}

/// Campanha destacada no período.
class TopCampaign {
  final String channel;
  final String campaign;
  final int leads;
  final double spend;
  final double? cpl;
  final String? recommendedAction; // increase | maintain | decrease

  const TopCampaign({
    required this.channel,
    required this.campaign,
    required this.leads,
    required this.spend,
    required this.cpl,
    this.recommendedAction,
  });

  factory TopCampaign.fromJson(Map<String, dynamic> json) {
    return TopCampaign(
      channel: parseString(json['channel']),
      campaign: parseString(json['campaign'], 'Sem nome'),
      leads: parseInt(json['leads']),
      spend: parseDouble(json['spend']),
      cpl: parseDoubleOrNull(json['cpl']),
      recommendedAction: parseStringOrNull(json['recommendedAction']),
    );
  }
}

/// Qualidade da atribuição (leads sem origem rastreável).
class SourcesDataQuality {
  final int totalLeads;
  final int unattributedLeads;
  final double unattributedLeadsPct;
  final String confidence; // high | medium | low

  const SourcesDataQuality({
    required this.totalLeads,
    required this.unattributedLeads,
    required this.unattributedLeadsPct,
    required this.confidence,
  });

  factory SourcesDataQuality.fromJson(Map<String, dynamic> json) {
    return SourcesDataQuality(
      totalLeads: parseInt(json['totalLeads']),
      unattributedLeads: parseInt(json['unattributedLeads']),
      unattributedLeadsPct: parseDouble(json['unattributedLeadsPct']),
      confidence: parseString(json['confidence'], 'low'),
    );
  }

  String get confidenceLabel {
    switch (confidence) {
      case 'high':
        return 'Alta';
      case 'medium':
        return 'Média';
      default:
        return 'Baixa';
    }
  }
}

/// Resumo multicanal (`GET /analytics/public-site/sources/summary`).
class SourcesSummary {
  final List<SourceChannel> channels;
  final List<SourceDailyPoint> timeseries;
  final List<TopCampaign> topCampaigns;
  final SourcesDataQuality? dataQuality;
  final String period;
  final String startDate;
  final String endDate;

  const SourcesSummary({
    required this.channels,
    required this.timeseries,
    required this.topCampaigns,
    required this.dataQuality,
    required this.period,
    required this.startDate,
    required this.endDate,
  });

  factory SourcesSummary.fromJson(Map<String, dynamic> json) {
    final body = unwrapData(json);
    return SourcesSummary(
      channels: parseMapList(body['channels'])
          .map(SourceChannel.fromJson)
          .toList(growable: false),
      timeseries: parseMapList(body['timeseries'])
          .map(SourceDailyPoint.fromJson)
          .toList(growable: false),
      topCampaigns: parseMapList(body['topCampaigns'])
          .map(TopCampaign.fromJson)
          .toList(growable: false),
      dataQuality: parseMap(body['dataQuality']) != null
          ? SourcesDataQuality.fromJson(parseMap(body['dataQuality'])!)
          : null,
      period: parseString(body['period'], 'monthly'),
      startDate: parseString(body['startDate']),
      endDate: parseString(body['endDate']),
    );
  }

  int get totalLeads => channels.fold(0, (acc, c) => acc + c.leads);
  int get totalViews => channels.fold(0, (acc, c) => acc + c.views);
  int get totalContacts => channels.fold(0, (acc, c) => acc + c.contactIntents);
  double get totalSpend => channels.fold(0.0, (acc, c) => acc + c.spend);
  double get totalRevenue => channels.fold(0.0, (acc, c) => acc + c.revenue);

  /// CPL/ROI calculados SÓ sobre canais com gasto importado (paridade com o
  /// hero do web — misturar orgânico derrubava o CPL para baixo do real).
  double? get paidCpl {
    final paid = channels.where((c) => c.spend > 0).toList();
    final leads = paid.fold(0, (acc, c) => acc + c.leads);
    final spend = paid.fold(0.0, (acc, c) => acc + c.spend);
    if (spend <= 0 || leads <= 0) return null;
    return spend / leads;
  }

  double? get paidRoi {
    final paid = channels.where((c) => c.spend > 0).toList();
    final spend = paid.fold(0.0, (acc, c) => acc + c.spend);
    final revenue = paid.fold(0.0, (acc, c) => acc + c.revenue);
    if (spend <= 0) return null;
    return (revenue - spend) / spend * 100;
  }

  /// Leads por dia (todas as origens somadas), ordenado por data.
  List<({String date, int leads})> get leadsPerDay {
    final map = <String, int>{};
    for (final p in timeseries) {
      if (p.date.isEmpty) continue;
      map[p.date] = (map[p.date] ?? 0) + p.leads;
    }
    final keys = map.keys.toList()..sort();
    return keys
        .map((d) => (date: d, leads: map[d] ?? 0))
        .toList(growable: false);
  }
}

/// Totais de engajamento do site público.
class EngagementTotals {
  final int views;
  final int whatsappClicks;
  final int phoneClicks;
  final int emailClicks;
  final int favorites;
  final int shares;
  final int prints;
  final int contactIntents;

  const EngagementTotals({
    required this.views,
    required this.whatsappClicks,
    required this.phoneClicks,
    required this.emailClicks,
    required this.favorites,
    required this.shares,
    required this.prints,
    required this.contactIntents,
  });

  factory EngagementTotals.fromJson(Map<String, dynamic> json) {
    return EngagementTotals(
      views: parseInt(json['views']),
      whatsappClicks: parseInt(json['whatsappClicks']),
      phoneClicks: parseInt(json['phoneClicks']),
      emailClicks: parseInt(json['emailClicks']),
      favorites: parseInt(json['favorites']),
      shares: parseInt(json['shares']),
      prints: parseInt(json['prints']),
      contactIntents: parseInt(json['contactIntents']),
    );
  }

  static const empty = EngagementTotals(
    views: 0,
    whatsappClicks: 0,
    phoneClicks: 0,
    emailClicks: 0,
    favorites: 0,
    shares: 0,
    prints: 0,
    contactIntents: 0,
  );
}

class EngagementConversion {
  final double viewToContactRate;
  final double viewToWhatsappRate;

  const EngagementConversion({
    required this.viewToContactRate,
    required this.viewToWhatsappRate,
  });

  factory EngagementConversion.fromJson(Map<String, dynamic> json) {
    return EngagementConversion(
      viewToContactRate: parseDouble(json['viewToContactRate']),
      viewToWhatsappRate: parseDouble(json['viewToWhatsappRate']),
    );
  }

  static const empty =
      EngagementConversion(viewToContactRate: 0, viewToWhatsappRate: 0);
}

class EngagementDevice {
  final String device;
  final int count;
  final double percentage;

  const EngagementDevice({
    required this.device,
    required this.count,
    required this.percentage,
  });

  factory EngagementDevice.fromJson(Map<String, dynamic> json) {
    return EngagementDevice(
      device: parseString(json['device'], 'outros'),
      count: parseInt(json['count']),
      percentage: parseDouble(json['percentage']),
    );
  }

  String get label {
    switch (device.toLowerCase()) {
      case 'mobile':
        return 'Celular';
      case 'desktop':
        return 'Computador';
      case 'tablet':
        return 'Tablet';
      default:
        return device;
    }
  }
}

class EngagementDailyPoint {
  final String date;
  final int views;
  final int contactIntents;
  final int whatsappClicks;

  const EngagementDailyPoint({
    required this.date,
    required this.views,
    required this.contactIntents,
    required this.whatsappClicks,
  });

  factory EngagementDailyPoint.fromJson(Map<String, dynamic> json) {
    return EngagementDailyPoint(
      date: parseString(json['date']),
      views: parseInt(json['views']),
      contactIntents: parseInt(json['contactIntents']),
      whatsappClicks: parseInt(json['whatsappClicks']),
    );
  }
}

class TopEngagedProperty {
  final String propertyId;
  final String title;
  final String? neighborhood;
  final double? price;
  final int views;
  final int whatsappClicks;
  final int phoneClicks;
  final int emailClicks;
  final int favorites;
  final int contactIntents;
  final double conversionRate;

  const TopEngagedProperty({
    required this.propertyId,
    required this.title,
    required this.neighborhood,
    required this.price,
    required this.views,
    required this.whatsappClicks,
    required this.phoneClicks,
    required this.emailClicks,
    required this.favorites,
    required this.contactIntents,
    required this.conversionRate,
  });

  factory TopEngagedProperty.fromJson(Map<String, dynamic> json) {
    return TopEngagedProperty(
      propertyId: parseString(json['propertyId'], parseString(json['id'])),
      title: parseString(json['title'], 'Imóvel'),
      neighborhood: parseStringOrNull(json['neighborhood']),
      price: parseDoubleOrNull(json['price']),
      views: parseInt(json['views']),
      whatsappClicks: parseInt(json['whatsappClicks']),
      phoneClicks: parseInt(json['phoneClicks']),
      emailClicks: parseInt(json['emailClicks']),
      favorites: parseInt(json['favorites']),
      contactIntents: parseInt(json['contactIntents']),
      conversionRate: parseDouble(json['conversionRate']),
    );
  }
}

/// Resumo de engajamento (`GET /analytics/public-site/engagement/summary`).
class EngagementSummaryData {
  final EngagementTotals totals;
  final EngagementConversion conversion;
  final List<EngagementDailyPoint> timeseries;
  final List<EngagementDevice> deviceBreakdown;
  final List<TopEngagedProperty> topEngagedProperties;
  final String city;
  final String state;

  const EngagementSummaryData({
    required this.totals,
    required this.conversion,
    required this.timeseries,
    required this.deviceBreakdown,
    required this.topEngagedProperties,
    required this.city,
    required this.state,
  });

  factory EngagementSummaryData.fromJson(Map<String, dynamic> json) {
    final body = unwrapData(json);
    return EngagementSummaryData(
      totals: parseMap(body['totals']) != null
          ? EngagementTotals.fromJson(parseMap(body['totals'])!)
          : EngagementTotals.empty,
      conversion: parseMap(body['conversion']) != null
          ? EngagementConversion.fromJson(parseMap(body['conversion'])!)
          : EngagementConversion.empty,
      timeseries: parseMapList(body['timeseries'])
          .map(EngagementDailyPoint.fromJson)
          .toList(growable: false),
      deviceBreakdown: parseMapList(body['deviceBreakdown'])
          .map(EngagementDevice.fromJson)
          .toList(growable: false),
      topEngagedProperties: parseMapList(body['topEngagedProperties'])
          .map(TopEngagedProperty.fromJson)
          .toList(growable: false),
      city: parseString(body['city']),
      state: parseString(body['state']),
    );
  }
}

/// Lead recente com sinal de atribuição (drill-down multicanal).
class RecentLead {
  final String id;
  final String title;
  final DateTime? createdAt;
  final String? channel;
  final String channelLabel;
  final String? assignedToName;
  final double? dealValue;
  final String captureMethod; // whatsapp_marker | site_session | manual | unknown

  const RecentLead({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.channel,
    required this.channelLabel,
    required this.assignedToName,
    required this.dealValue,
    required this.captureMethod,
  });

  factory RecentLead.fromJson(Map<String, dynamic> json) {
    return RecentLead(
      id: parseString(json['id']),
      title: parseString(json['title'], 'Lead'),
      createdAt: parseDate(json['createdAt']),
      channel: parseStringOrNull(json['attributionChannel']),
      channelLabel: parseString(json['channelLabel'], 'Sem origem'),
      assignedToName: parseStringOrNull(json['assignedToName']),
      dealValue: parseDoubleOrNull(json['dealValue']),
      captureMethod: parseString(json['captureMethod'], 'unknown'),
    );
  }

  String get captureMethodLabel {
    switch (captureMethod) {
      case 'whatsapp_marker':
        return 'Marcador WhatsApp';
      case 'site_session':
        return 'Sessão do site';
      case 'manual':
        return 'Manual';
      default:
        return 'Origem desconhecida';
    }
  }
}

/// Página de atribuições recentes
/// (`GET /analytics/public-site/sources/recent-attributions`).
class RecentAttributionsData {
  final int total;
  final int limit;
  final int offset;
  final List<RecentLead> items;

  const RecentAttributionsData({
    required this.total,
    required this.limit,
    required this.offset,
    required this.items,
  });

  factory RecentAttributionsData.fromJson(Map<String, dynamic> json) {
    final body = unwrapData(json);
    return RecentAttributionsData(
      total: parseInt(body['total']),
      limit: parseInt(body['limit'], 20),
      offset: parseInt(body['offset']),
      items: parseMapList(body['items'])
          .map(RecentLead.fromJson)
          .toList(growable: false),
    );
  }

  bool get hasMore => offset + items.length < total;
}
