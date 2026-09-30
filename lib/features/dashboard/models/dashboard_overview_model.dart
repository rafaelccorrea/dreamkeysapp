/// Modelos do `GET /dashboard/overview` — a Home executiva de admin/master.
///
/// 29/09/2026 (dash-01): paridade com o `DashboardOverview` do
/// `useDashboard.ts` do imobx-front. No web, admin e master abrem o
/// `DashboardPage` (visão da empresa) e o app mostrava a eles o painel
/// pessoal do `/dashboard/user` — o dono via os números DELE como se fossem
/// os da empresa. Aqui entram só os campos que a tela lê (abertura, KPIs,
/// funil, ranking, panorama, atividades e o detalhe de cada KPI).
///
/// Parsing defensivo: número pode vir como string, lista ou objeto podem
/// faltar (o back devolve um fallback zerado por card quando uma consulta
/// falha), e nada disso pode derrubar a tela.
library;

int _i(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(v.toString()) ??
      (double.tryParse(v.toString())?.round() ?? 0);
}

double _d(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
}

double? _dn(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '.'));
}

String _s(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final s = v.toString().trim();
  return s.isEmpty ? fallback : s;
}

String? _sn(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

DateTime? _dt(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v.toLocal();
  return DateTime.tryParse(v.toString())?.toLocal();
}

Map<String, dynamic> _m(dynamic v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _ml(dynamic v) {
  if (v is! List) return const [];
  return v
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
}

/// Nome aninhado (`{ id, name }`) ou nulo.
String? _nestedName(dynamic v, [String key = 'name']) {
  if (v is Map) return _sn(v[key]);
  return null;
}

// ─── Estatísticas ────────────────────────────────────────────────────────────

class OverviewStatistics {
  const OverviewStatistics({
    required this.totalLeads,
    required this.leadsGrowth,
    required this.appointments,
    required this.appointmentsGrowth,
    required this.totalSales,
    required this.salesGrowth,
    required this.salesCount,
    required this.realConversionRate,
    required this.conversionRate,
    required this.conversionGrowth,
    required this.totalRevenue,
    required this.pendingDocuments,
    this.previousLeads,
    this.previousAppointments,
    this.previousSalesCount,
  });

  final int totalLeads;
  final double? leadsGrowth;
  final int appointments;
  final double? appointmentsGrowth;

  /// VGV do período: soma das fichas de venda finalizadas.
  final double totalSales;
  final double? salesGrowth;

  /// Quantidade de fichas finalizadas no período.
  final int salesCount;

  /// Conversão real (%): fichas finalizadas ÷ leads do período.
  final double realConversionRate;

  /// Conversão do funil (%): cards ganhos ÷ leads (fallback do web).
  final double conversionRate;
  final double? conversionGrowth;

  /// Receita = soma das comissões das fichas.
  final double totalRevenue;
  final int pendingDocuments;

  /// Números do período de comparação (`comparison.data`) — só vêm com a
  /// comparação ligada. O back grava os leads em `leads`; `totalLeads` fica
  /// como segunda leitura.
  final int? previousLeads;
  final int? previousAppointments;
  final int? previousSalesCount;

  static const OverviewStatistics zero = OverviewStatistics(
    totalLeads: 0,
    leadsGrowth: null,
    appointments: 0,
    appointmentsGrowth: null,
    totalSales: 0,
    salesGrowth: null,
    salesCount: 0,
    realConversionRate: 0,
    conversionRate: 0,
    conversionGrowth: null,
    totalRevenue: 0,
    pendingDocuments: 0,
  );

  factory OverviewStatistics.fromJson(Map<String, dynamic> j) {
    final cmp = _m(_m(j['comparison'])['data']);
    int? prev(List<String> keys) {
      for (final k in keys) {
        if (cmp.containsKey(k) && cmp[k] != null) return _i(cmp[k]);
      }
      return null;
    }

    return OverviewStatistics(
      totalLeads: _i(j['totalLeads']),
      leadsGrowth: _dn(j['leadsGrowth']),
      appointments: _i(j['appointments']),
      appointmentsGrowth: _dn(j['appointmentsGrowth']),
      totalSales: _d(j['totalSales']),
      salesGrowth: _dn(j['salesGrowth']),
      salesCount: _i(j['salesCount']),
      realConversionRate:
          _dn(j['realConversionRate']) ?? _d(j['conversionRate']),
      conversionRate: _d(j['conversionRate']),
      conversionGrowth: _dn(j['conversionGrowth']),
      totalRevenue: _d(j['totalRevenue']),
      pendingDocuments: _i(j['pendingDocuments']),
      previousLeads: prev(const ['leads', 'totalLeads']),
      previousAppointments: prev(const ['appointments']),
      previousSalesCount: prev(const ['salesCount']),
    );
  }
}

// ─── Curva de 6 meses ────────────────────────────────────────────────────────

class OverviewSalesChart {
  const OverviewSalesChart({
    required this.labels,
    required this.values,
    this.comparisonValues = const [],
  });

  /// Chaves `YYYY-MM` (ou rótulos já curtos).
  final List<String> labels;
  final List<double> values;
  final List<double> comparisonValues;

  static const OverviewSalesChart empty =
      OverviewSalesChart(labels: [], values: []);

  factory OverviewSalesChart.fromJson(Map<String, dynamic> j) {
    List<double> nums(dynamic v) => v is List
        ? v.map(_d).toList(growable: false)
        : const <double>[];
    final cmp = _m(j['comparison']);
    return OverviewSalesChart(
      labels: j['labels'] is List
          ? (j['labels'] as List).map((e) => _s(e)).toList(growable: false)
          : const [],
      values: nums(j['values']),
      comparisonValues: nums(cmp['values']),
    );
  }
}

// ─── Meta do mês ─────────────────────────────────────────────────────────────

class OverviewMonthlyGoal {
  const OverviewMonthlyGoal({
    required this.target,
    required this.current,
    required this.progress,
    required this.remaining,
    required this.daysLeft,
    required this.dailyTarget,
    required this.onTrack,
  });

  final double target;
  final double current;
  final double progress;
  final double remaining;
  final int daysLeft;
  final double dailyTarget;
  final bool onTrack;

  bool get hasTarget => target > 0;

  static const OverviewMonthlyGoal empty = OverviewMonthlyGoal(
    target: 0,
    current: 0,
    progress: 0,
    remaining: 0,
    daysLeft: 0,
    dailyTarget: 0,
    onTrack: false,
  );

  factory OverviewMonthlyGoal.fromJson(Map<String, dynamic> j) {
    final target = _d(j['target']);
    final current = _d(j['current']);
    final double progress = _dn(j['progress']) ??
        (target > 0 ? current / target * 100 : 0.0);
    return OverviewMonthlyGoal(
      target: target,
      current: current,
      progress: progress,
      remaining: _dn(j['remaining']) ?? (target - current),
      daysLeft: _i(j['daysLeft']),
      dailyTarget: _d(j['dailyTarget']),
      onTrack: j['onTrack'] == true,
    );
  }
}

// ─── Ranking ─────────────────────────────────────────────────────────────────

class OverviewPerformer {
  const OverviewPerformer({
    required this.userId,
    required this.name,
    this.avatar,
    required this.sales,
    required this.revenue,
    required this.rank,
  });

  final String userId;
  final String name;
  final String? avatar;
  final int sales;
  final double revenue;
  final int rank;

  factory OverviewPerformer.fromJson(Map<String, dynamic> j) =>
      OverviewPerformer(
        userId: _s(j['userId']),
        name: _s(j['name'], 'Sem nome'),
        avatar: _sn(j['avatar']),
        sales: _i(j['sales']),
        revenue: _d(j['revenue']),
        rank: _i(j['rank']),
      );
}

/// Membro da equipe por tarefas — o ranking cai para esta leitura quando
/// ninguém vendeu no recorte (mesma regra do `HomeRankingCard`).
class OverviewTeamMember {
  const OverviewTeamMember({
    required this.userId,
    required this.name,
    required this.completedTasks,
    required this.performance,
  });

  final String userId;
  final String name;
  final int completedTasks;
  final double performance;

  factory OverviewTeamMember.fromJson(Map<String, dynamic> j) =>
      OverviewTeamMember(
        userId: _s(j['userId']),
        name: _s(j['name'], 'Sem nome'),
        completedTasks: _i(j['completedTasks']),
        performance: _d(j['performance']),
      );
}

// ─── Tarefas urgentes ────────────────────────────────────────────────────────

class OverviewTask {
  const OverviewTask({
    required this.id,
    required this.title,
    this.dueDate,
    required this.priority,
    this.assigneeName,
    this.relatedName,
  });

  final String id;
  final String title;
  final DateTime? dueDate;
  final String priority;
  final String? assigneeName;
  final String? relatedName;

  factory OverviewTask.fromJson(Map<String, dynamic> j) => OverviewTask(
        id: _s(j['id']),
        title: _s(j['title'], 'Tarefa sem título'),
        dueDate: _dt(j['dueDate']),
        priority: _s(j['priority']),
        assigneeName: _nestedName(j['assignee']),
        relatedName: _nestedName(j['relatedEntity']),
      );
}

class OverviewTasks {
  const OverviewTasks({
    required this.tasks,
    required this.total,
    required this.overdue,
    required this.dueToday,
    required this.dueTomorrow,
  });

  final List<OverviewTask> tasks;
  final int total;
  final int overdue;
  final int dueToday;
  final int dueTomorrow;

  static const OverviewTasks empty = OverviewTasks(
    tasks: [],
    total: 0,
    overdue: 0,
    dueToday: 0,
    dueTomorrow: 0,
  );

  factory OverviewTasks.fromJson(Map<String, dynamic> j) => OverviewTasks(
        tasks: _ml(j['tasks']).map(OverviewTask.fromJson).toList(
              growable: false,
            ),
        total: _i(j['total']),
        overdue: _i(j['overdue']),
        dueToday: _i(j['dueToday']),
        dueTomorrow: _i(j['dueTomorrow']),
      );
}

// ─── Leads recentes ──────────────────────────────────────────────────────────

class OverviewLead {
  const OverviewLead({
    required this.id,
    required this.name,
    this.phone,
    this.location,
    this.source,
    this.status,
    this.assignedToName,
  });

  final String id;
  final String name;
  final String? phone;
  final String? location;
  final String? source;
  final String? status;
  final String? assignedToName;

  factory OverviewLead.fromJson(Map<String, dynamic> j) => OverviewLead(
        id: _s(j['id']),
        name: _s(j['name'], 'Lead sem nome'),
        phone: _sn(j['phone']),
        location: _sn(j['location']),
        source: _sn(j['source']),
        status: _sn(j['status']),
        assignedToName: _nestedName(j['assignedTo']),
      );
}

class OverviewLeads {
  const OverviewLeads({
    required this.leads,
    required this.newToday,
    required this.avgScore,
  });

  final List<OverviewLead> leads;
  final int newToday;
  final double avgScore;

  static const OverviewLeads empty =
      OverviewLeads(leads: [], newToday: 0, avgScore: 0);

  factory OverviewLeads.fromJson(Map<String, dynamic> j) => OverviewLeads(
        leads: _ml(j['leads']).map(OverviewLead.fromJson).toList(
              growable: false,
            ),
        newToday: _i(j['newToday']),
        avgScore: _d(j['avgScore']),
      );
}

// ─── Atividades ──────────────────────────────────────────────────────────────

class OverviewActivity {
  const OverviewActivity({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    this.createdAt,
    this.userName,
  });

  final String id;
  final String type;
  final String title;
  final String description;
  final DateTime? createdAt;
  final String? userName;

  factory OverviewActivity.fromJson(Map<String, dynamic> j) =>
      OverviewActivity(
        id: _s(j['id']),
        type: _s(j['type']).toLowerCase(),
        title: _s(j['title'], 'Atividade'),
        description: _s(j['description']),
        createdAt: _dt(j['createdAt']),
        userName: _nestedName(j['user']),
      );
}

class OverviewActivities {
  const OverviewActivities({required this.activities, required this.total});

  final List<OverviewActivity> activities;
  final int total;

  static const OverviewActivities empty =
      OverviewActivities(activities: [], total: 0);

  factory OverviewActivities.fromJson(Map<String, dynamic> j) {
    final list = _ml(j['activities'])
        .map(OverviewActivity.fromJson)
        .toList(growable: false);
    return OverviewActivities(
      activities: list,
      total: j['total'] != null ? _i(j['total']) : list.length,
    );
  }
}

// ─── Documentos pendentes ────────────────────────────────────────────────────

class OverviewDocument {
  const OverviewDocument({
    required this.id,
    required this.title,
    required this.type,
    this.uploadedAt,
    this.uploadedByName,
    this.relatedName,
  });

  final String id;
  final String title;
  final String type;
  final DateTime? uploadedAt;
  final String? uploadedByName;
  final String? relatedName;

  factory OverviewDocument.fromJson(Map<String, dynamic> j) =>
      OverviewDocument(
        id: _s(j['id']),
        title: _s(j['title'], 'Documento'),
        type: _s(j['type']),
        uploadedAt: _dt(j['uploadedAt']),
        uploadedByName: _nestedName(j['uploadedBy']),
        relatedName: _nestedName(j['relatedTo']),
      );
}

class OverviewDocuments {
  const OverviewDocuments({
    required this.documents,
    required this.personal,
    required this.property,
    required this.contract,
    required this.other,
  });

  final List<OverviewDocument> documents;
  final int personal;
  final int property;
  final int contract;
  final int other;

  static const OverviewDocuments empty = OverviewDocuments(
    documents: [],
    personal: 0,
    property: 0,
    contract: 0,
    other: 0,
  );

  factory OverviewDocuments.fromJson(Map<String, dynamic> j) {
    final byType = _m(j['byType']);
    return OverviewDocuments(
      documents: _ml(j['documents'])
          .map(OverviewDocument.fromJson)
          .toList(growable: false),
      personal: _i(byType['personal_document']),
      property: _i(byType['property_document']),
      contract: _i(byType['contract']),
      other: _i(byType['other']),
    );
  }
}

// ─── Agenda ──────────────────────────────────────────────────────────────────

class OverviewAppointment {
  const OverviewAppointment({
    required this.id,
    required this.title,
    this.dateTime,
    this.clientName,
    this.propertyTitle,
    this.assignedToName,
    required this.type,
  });

  final String id;
  final String title;
  final DateTime? dateTime;
  final String? clientName;
  final String? propertyTitle;
  final String? assignedToName;
  final String type;

  factory OverviewAppointment.fromJson(Map<String, dynamic> j) =>
      OverviewAppointment(
        id: _s(j['id']),
        title: _s(j['title'], 'Compromisso'),
        dateTime: _dt(j['dateTime']),
        clientName: _nestedName(j['client']),
        propertyTitle: _nestedName(j['property'], 'title'),
        assignedToName: _nestedName(j['assignedTo']),
        type: _s(j['type']).toLowerCase(),
      );
}

class OverviewAppointments {
  const OverviewAppointments({
    required this.total,
    required this.scheduled,
    required this.completed,
    required this.cancelled,
    required this.upcoming,
    required this.visits,
    required this.meetings,
  });

  final int total;
  final int scheduled;
  final int completed;
  final int cancelled;
  final List<OverviewAppointment> upcoming;
  final int visits;
  final int meetings;

  static const OverviewAppointments empty = OverviewAppointments(
    total: 0,
    scheduled: 0,
    completed: 0,
    cancelled: 0,
    upcoming: [],
    visits: 0,
    meetings: 0,
  );

  factory OverviewAppointments.fromJson(Map<String, dynamic> j) {
    final byType = _m(j['byType']);
    return OverviewAppointments(
      total: _i(j['total']),
      scheduled: _i(j['scheduled']),
      completed: _i(j['completed']),
      cancelled: _i(j['cancelled']),
      upcoming: _ml(j['upcoming'])
          .map(OverviewAppointment.fromJson)
          .toList(growable: false),
      visits: _i(byType['visit']),
      meetings: _i(byType['meeting']),
    );
  }
}

// ─── Origem dos leads ────────────────────────────────────────────────────────

class OverviewLeadSource {
  const OverviewLeadSource({
    required this.source,
    required this.label,
    required this.count,
    required this.percentage,
  });

  final String source;
  final String label;
  final int count;
  final double percentage;

  factory OverviewLeadSource.fromJson(Map<String, dynamic> j) {
    final source = _s(j['source'], 'other');
    return OverviewLeadSource(
      source: source,
      label: _s(j['label'], source),
      count: _i(j['count']),
      percentage: _d(j['percentage']),
    );
  }
}

class OverviewLeadSources {
  const OverviewLeadSources({
    required this.sources,
    required this.total,
    required this.withoutSource,
  });

  final List<OverviewLeadSource> sources;
  final int total;
  final int withoutSource;

  static const OverviewLeadSources empty =
      OverviewLeadSources(sources: [], total: 0, withoutSource: 0);

  factory OverviewLeadSources.fromJson(Map<String, dynamic> j) =>
      OverviewLeadSources(
        sources: _ml(j['sources'])
            .map(OverviewLeadSource.fromJson)
            .toList(growable: false),
        total: _i(j['total']),
        withoutSource: _i(j['withoutSource']),
      );
}

/// Pessoa do filtro "Corretor" (`filters.availableUsers`).
class OverviewUserOption {
  const OverviewUserOption({required this.id, required this.name});

  final String id;
  final String name;
}

// ─── Raiz ────────────────────────────────────────────────────────────────────

class DashboardOverview {
  const DashboardOverview({
    required this.statistics,
    required this.salesChart,
    required this.monthlyGoal,
    required this.projectedTotal,
    required this.performers,
    required this.teamMembers,
    required this.tasks,
    required this.leads,
    required this.activities,
    required this.documents,
    required this.appointments,
    required this.leadSources,
    required this.availableUsers,
    this.generatedAt,
  });

  final OverviewStatistics statistics;
  final OverviewSalesChart salesChart;
  final OverviewMonthlyGoal monthlyGoal;

  /// Projeção do mês (`goals.salesTarget.projectedTotal`).
  final double projectedTotal;
  final List<OverviewPerformer> performers;
  final List<OverviewTeamMember> teamMembers;
  final OverviewTasks tasks;
  final OverviewLeads leads;
  final OverviewActivities activities;
  final OverviewDocuments documents;
  final OverviewAppointments appointments;
  final OverviewLeadSources leadSources;
  final List<OverviewUserOption> availableUsers;
  final DateTime? generatedAt;

  factory DashboardOverview.fromJson(Map<String, dynamic> j) {
    final goals = _m(j['goals']);
    final performance = _m(j['performance']);
    final team = _m(performance['team']);
    final top = _m(j['topPerformers']);
    final filters = _m(j['filters']);
    final charts = _m(j['charts']);

    // Nome vazio vira "Sem nome" e o mesmo id não entra duas vezes (o back
    // lista por vínculo de empresa — com várias empresas o mesmo usuário
    // pode vir repetido).
    final seen = <String>{};
    final users = <OverviewUserOption>[];
    for (final u in _ml(filters['availableUsers'])) {
      final id = _s(u['id']);
      if (id.isEmpty || !seen.add(id)) continue;
      users.add(OverviewUserOption(id: id, name: _s(u['name'], 'Sem nome')));
    }
    users.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return DashboardOverview(
      statistics: j['statistics'] is Map
          ? OverviewStatistics.fromJson(_m(j['statistics']))
          : OverviewStatistics.zero,
      salesChart: charts['sales'] is Map
          ? OverviewSalesChart.fromJson(_m(charts['sales']))
          : OverviewSalesChart.empty,
      monthlyGoal: goals['monthly'] is Map
          ? OverviewMonthlyGoal.fromJson(_m(goals['monthly']))
          : OverviewMonthlyGoal.empty,
      projectedTotal: _d(_m(goals['salesTarget'])['projectedTotal']),
      performers: _ml(top['performers'])
          .map(OverviewPerformer.fromJson)
          .where((p) => p.userId.isNotEmpty)
          .toList(growable: false),
      teamMembers: _ml(team['members'])
          .map(OverviewTeamMember.fromJson)
          .where((m) => m.userId.isNotEmpty)
          .toList(growable: false),
      tasks: j['tasks'] is Map
          ? OverviewTasks.fromJson(_m(j['tasks']))
          : OverviewTasks.empty,
      leads: j['leads'] is Map
          ? OverviewLeads.fromJson(_m(j['leads']))
          : OverviewLeads.empty,
      activities: j['activities'] is Map
          ? OverviewActivities.fromJson(_m(j['activities']))
          : OverviewActivities.empty,
      documents: j['documents'] is Map
          ? OverviewDocuments.fromJson(_m(j['documents']))
          : OverviewDocuments.empty,
      appointments: j['appointments'] is Map
          ? OverviewAppointments.fromJson(_m(j['appointments']))
          : OverviewAppointments.empty,
      leadSources: j['leadSources'] is Map
          ? OverviewLeadSources.fromJson(_m(j['leadSources']))
          : OverviewLeadSources.empty,
      availableUsers: users,
      generatedAt: _dt(j['generatedAt']),
    );
  }
}
