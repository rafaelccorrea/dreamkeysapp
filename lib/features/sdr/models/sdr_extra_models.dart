/// Modelos das abas extras e do drill-down do Dash SDR (29/09/2026, sdr-04 e
/// sdr-05). Paridade com `kanbanMetricsApi.ts` do imobx-front:
///   - listas de leads do `sdr/metrics?lists=full` (drill-down);
///   - `sdr/daily-productivity` (aba Produtividade diária);
///   - `sdr/brokers-stagnation` (aba Por corretor);
///   - `sdr/subtask-activity` (aba Atividades).
/// Parsing defensivo: aceita null / string / number em todo campo numérico.
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

String _s(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final s = v.toString().trim();
  return s.isEmpty ? fallback : s;
}

String? _sOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

DateTime? _dt(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString())?.toLocal();
}

List<Map<String, dynamic>> _maps(dynamic v) {
  if (v is! List) return const [];
  return v
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
}

Map<String, int> _intMap(dynamic v) {
  if (v is! Map) return const {};
  final out = <String, int>{};
  v.forEach((k, val) => out[k.toString()] = _i(val));
  return out;
}

/// Recorte do drill-down — qual lista de leads abrir.
enum SdrDrillKind {
  period('Leads do período'),
  qualification('Em qualificação'),
  lost('Perdidos'),
  transferred('Transferidos');

  const SdrDrillKind(this.label);
  final String label;
}

/// Uma linha de lead do drill-down (qualquer uma das quatro listas).
class SdrLeadRow {
  const SdrLeadRow({
    required this.taskId,
    required this.title,
    this.contactName,
    this.contactPhone,
    this.source,
    this.campaign,
    this.agentName,
    this.columnTitle,
    this.funnel,
    this.detail,
    this.date,
    this.stateLabel,
    this.qualification,
    this.createdAt,
    this.dueDate,
    this.lossReason,
    this.transferId,
    this.originalTaskId,
    this.duplicatedTaskId,
    this.fromTeam,
    this.toTeam,
    this.assignedTo,
    this.transferredBy,
  });

  /// Card que o toque abre no Kanban do app.
  final String taskId;
  final String title;
  final String? contactName;
  final String? contactPhone;
  final String? source;
  final String? campaign;
  final String? agentName;
  final String? columnTitle;
  final String? funnel;

  /// Motivo da perda, destino da transferência ou prazo — depende da lista.
  final String? detail;
  final DateTime? date;

  /// Estado derivado do `result` (lista do período).
  final String? stateLabel;

  /// 30/09/2026 (paridade do detalhe com o web): os campos que os cartões do
  /// web mostram e o app descartava.

  /// Qualificação do lead ("Qualific.:").
  final String? qualification;

  /// Entrada do card ("Entrada:").
  final DateTime? createdAt;

  /// Prazo (lista "Em qualificação": "Prazo:"; ordena do mais cedo ao sem
  /// prazo).
  final DateTime? dueDate;

  /// Motivo da perda como veio (código; o rótulo sai do `KanbanLossReason`).
  final String? lossReason;

  /// Transferência: id, card do SDR (original) e card do corretor (cópia).
  final String? transferId;
  final String? originalTaskId;
  final String? duplicatedTaskId;

  /// Transferência: funil/equipe de origem e de destino, corretor que recebeu
  /// e quem executou.
  final String? fromTeam;
  final String? toTeam;
  final String? assignedTo;
  final String? transferredBy;

  bool matches(String term) {
    if (term.isEmpty) return true;
    final hay = [
      title,
      contactName,
      contactPhone,
      source,
      campaign,
      agentName,
      columnTitle,
      funnel,
      detail,
    ].whereType<String>().join(' ').toLowerCase();
    return hay.contains(term);
  }
}

/// Estado na lista do período — a regra do web (`partitionLeadsForDrill`): a
/// lista é a coorte de entrada que segue no funil SDR, então cada lead é
/// «Perdido» (result = lost) ou «Em qualificação». Os transferidos saíram do
/// funil e não entram nesta base.
String _resultLabel(String? result) =>
    (result ?? '').toLowerCase() == 'lost' ? 'Perdido' : 'Em qualificação';

/// As quatro listas do `sdr/metrics?lists=full`.
class SdrLeadLists {
  const SdrLeadLists({
    required this.period,
    required this.qualification,
    required this.lost,
    required this.transferred,
  });

  final List<SdrLeadRow> period;
  final List<SdrLeadRow> qualification;
  final List<SdrLeadRow> lost;
  final List<SdrLeadRow> transferred;

  static const SdrLeadLists empty = SdrLeadLists(
    period: [],
    qualification: [],
    lost: [],
    transferred: [],
  );

  List<SdrLeadRow> of(SdrDrillKind kind) => switch (kind) {
        SdrDrillKind.period => period,
        SdrDrillKind.qualification => qualification,
        SdrDrillKind.lost => lost,
        SdrDrillKind.transferred => transferred,
      };

  factory SdrLeadLists.fromJson(Map<String, dynamic> json) {
    String? funnelOf(Map<String, dynamic> m) =>
        _sOrNull(m['projectName']) ?? _sOrNull(m['teamName']);

    return SdrLeadLists(
      period: _maps(json['periodLeadsList'])
          .map((m) => SdrLeadRow(
                taskId: _s(m['taskId']),
                title: _s(m['leadTitle'], 'Lead sem título'),
                contactName: _sOrNull(m['contactName']),
                contactPhone: _sOrNull(m['contactPhone']),
                source: _sOrNull(m['source']),
                campaign: _sOrNull(m['campaign']),
                agentName: _sOrNull(m['agentName']),
                columnTitle: _sOrNull(m['columnTitle']),
                funnel: funnelOf(m),
                date: _dt(m['createdAt']),
                stateLabel: _resultLabel(_sOrNull(m['result'])),
                qualification: _sOrNull(m['qualification']),
                createdAt: _dt(m['createdAt']),
              ))
          .where((r) => r.taskId.isNotEmpty)
          .toList(growable: false),
      qualification: _maps(json['qualificationLeadsList'])
          .map((m) => SdrLeadRow(
                taskId: _s(m['taskId']),
                title: _s(m['leadTitle'], 'Lead sem título'),
                contactName: _sOrNull(m['contactName']),
                contactPhone: _sOrNull(m['contactPhone']),
                source: _sOrNull(m['source']),
                campaign: _sOrNull(m['campaign']),
                agentName: _sOrNull(m['agentName']),
                columnTitle: _sOrNull(m['columnTitle']),
                funnel: funnelOf(m),
                date: _dt(m['createdAt']),
                stateLabel: 'Em qualificação',
                qualification: _sOrNull(m['qualification']),
                createdAt: _dt(m['createdAt']),
                dueDate: _dt(m['dueDate']),
              ))
          .where((r) => r.taskId.isNotEmpty)
          .toList(growable: false),
      lost: _maps(json['lostLeadsList'])
          .map((m) => SdrLeadRow(
                taskId: _s(m['taskId']),
                title: _s(m['leadTitle'], 'Lead sem título'),
                contactName: _sOrNull(m['contactName']),
                contactPhone: _sOrNull(m['contactPhone']),
                source: _sOrNull(m['source']),
                campaign: _sOrNull(m['campaign']),
                agentName: _sOrNull(m['agentName']),
                columnTitle: _sOrNull(m['columnTitle']),
                funnel: funnelOf(m),
                detail: _sOrNull(m['lossReason']),
                date: _dt(m['resultDate']) ?? _dt(m['createdAt']),
                stateLabel: 'Perdido',
                qualification: _sOrNull(m['qualification']),
                createdAt: _dt(m['createdAt']),
                lossReason: _sOrNull(m['lossReason']),
              ))
          .where((r) => r.taskId.isNotEmpty)
          .toList(growable: false),
      transferred: _maps(json['transferList'])
          .map((m) {
            // O card que o corretor trabalha é o duplicado; sem ele, o
            // original do SDR (mesma escolha do "Abrir tarefa" do web).
            final dup = _s(m['duplicatedTaskId']);
            final orig = _s(m['originalTaskId']);
            final dest = [
              _sOrNull(m['toTeam']),
              _sOrNull(m['assignedTo']),
            ].whereType<String>().join(' · ');
            return SdrLeadRow(
              taskId: dup.isNotEmpty ? dup : orig,
              title: _s(m['leadTitle'], 'Lead sem título'),
              contactName: _sOrNull(m['contactName']),
              contactPhone: _sOrNull(m['contactPhone']),
              source: _sOrNull(m['source']),
              campaign: _sOrNull(m['campaign']),
              agentName: _sOrNull(m['sdrAgentName']),
              columnTitle: _sOrNull(m['columnTitle']),
              funnel: _sOrNull(m['fromTeam']),
              detail: dest.isEmpty ? null : dest,
              date: _dt(m['transferredAt']),
              stateLabel: 'Transferido',
              qualification: _sOrNull(m['qualification']),
              transferId: _sOrNull(m['transferId']),
              originalTaskId: orig.isEmpty ? null : orig,
              duplicatedTaskId: dup.isEmpty ? null : dup,
              fromTeam: _sOrNull(m['fromTeam']),
              toTeam: _sOrNull(m['toTeam']),
              assignedTo: _sOrNull(m['assignedTo']),
              transferredBy: _sOrNull(m['transferredBy']),
            );
          })
          .where((r) => r.taskId.isNotEmpty)
          .toList(growable: false),
    );
  }
}

/// Linha da produtividade diária (agente × dia).
class SdrDailyRow {
  const SdrDailyRow({
    required this.date,
    required this.agentId,
    required this.agentName,
    required this.created,
    required this.createdWhatsapp,
    required this.createdCrm,
    required this.whatsappAssigned,
    required this.lost,
    required this.transferred,
    required this.inQualification,
    required this.calls,
    required this.overdueTasks,
    required this.conversionRate,
  });

  /// `yyyy-MM-dd` (fuso Brasília, como vem do back).
  final String date;
  final String agentId;
  final String agentName;
  final int created;
  final int createdWhatsapp;
  final int createdCrm;
  final int whatsappAssigned;
  final int lost;
  final int transferred;
  final int inQualification;
  final int calls;
  final int overdueTasks;
  final double conversionRate;

  factory SdrDailyRow.fromJson(Map<String, dynamic> m) {
    final iq = _intMap(m['inQualificationByTeam']);
    return SdrDailyRow(
      date: _s(m['date']),
      agentId: _s(m['agentId']),
      agentName: _s(m['agentName'], 'Sem responsável'),
      created: _i(m['created']),
      createdWhatsapp: _i(m['tasksCreatedWhatsapp']),
      createdCrm: _i(m['tasksCreatedCrm']),
      whatsappAssigned: _i(m['whatsappAssigned']),
      lost: _i(m['lost']),
      transferred: _i(m['transferred']),
      inQualification: m['inQualificationTotal'] != null
          ? _i(m['inQualificationTotal'])
          : iq.values.fold<int>(0, (a, b) => a + b),
      calls: _i(m['calls']),
      overdueTasks: _i(m['overdueTasks']),
      conversionRate: _d(m['conversionRate']),
    );
  }

  /// Aceita `{agents: [...]}` ou a lista crua (os dois formatos do back).
  static List<SdrDailyRow> listFrom(dynamic raw) {
    final list = raw is List
        ? raw
        : raw is Map
            ? (raw['agents'] ?? raw['data'] ?? const [])
            : const [];
    return _maps(list).map(SdrDailyRow.fromJson).toList(growable: false);
  }
}

/// Totais de um agente somando os dias do período.
class SdrDailyAgentTotal {
  SdrDailyAgentTotal(this.agentId, this.agentName);

  final String agentId;
  final String agentName;
  int created = 0;
  int createdWhatsapp = 0;
  int createdCrm = 0;
  int lost = 0;
  int transferred = 0;
  int inQualification = 0;
  int calls = 0;
  int overdueTasks = 0;

  double get conversionRate =>
      created > 0 ? transferred / created * 100 : 0;
}

/// Corretor da aba "Por corretor" (estagnação dos leads recebidos do SDR).
class SdrBrokerStagnationRow {
  const SdrBrokerStagnationRow({
    required this.brokerId,
    required this.brokerName,
    required this.cardsTotal,
    required this.cardsActive,
    required this.stuck7,
    required this.stuck14,
    required this.stuck30,
    required this.avgStuckHours,
    required this.avgNoUpdateHours,
    this.lastTransferAt,
  });

  final String brokerId;
  final String brokerName;
  final int cardsTotal;
  final int cardsActive;
  final int stuck7;
  final int stuck14;
  final int stuck30;
  final double avgStuckHours;
  final double avgNoUpdateHours;
  final DateTime? lastTransferAt;

  factory SdrBrokerStagnationRow.fromJson(Map<String, dynamic> m) =>
      SdrBrokerStagnationRow(
        brokerId: _s(m['brokerId']),
        brokerName: _s(m['brokerName'], 'Sem nome'),
        cardsTotal: _i(m['cardsTotal']),
        cardsActive: _i(m['cardsAtivos']),
        stuck7: _i(m['cardsParadosMais7d']),
        stuck14: _i(m['cardsParadosMais14d']),
        stuck30: _i(m['cardsParadosMais30d']),
        avgStuckHours: _d(m['tempoMedioParadoHoras']),
        avgNoUpdateHours: _d(m['tempoMedioSemAtualizacaoHoras']),
        lastTransferAt: _dt(m['ultimaTransferenciaAt']),
      );
}

/// Card de um corretor (drill da aba "Por corretor").
class SdrBrokerCard {
  const SdrBrokerCard({
    required this.taskId,
    required this.title,
    required this.brokerId,
    required this.columnTitle,
    required this.teamName,
    required this.daysInColumn,
    required this.daysSinceUpdate,
    this.source,
    this.result,
  });

  final String taskId;
  final String title;
  final String brokerId;
  final String columnTitle;
  final String teamName;
  final int daysInColumn;
  final int daysSinceUpdate;
  final String? source;
  final String? result;

  factory SdrBrokerCard.fromJson(Map<String, dynamic> m) => SdrBrokerCard(
        taskId: _s(m['taskId']),
        title: _s(m['leadTitle'], 'Lead sem título'),
        brokerId: _s(m['brokerId']),
        columnTitle: _s(m['columnTitle'], 'Coluna'),
        teamName: _s(m['teamName']),
        daysInColumn: _i(m['daysInColumn']),
        daysSinceUpdate: _i(m['daysSinceUpdate']),
        source: _sOrNull(m['source']),
        result: _sOrNull(m['result']),
      );
}

class SdrBrokerStagnation {
  const SdrBrokerStagnation({required this.brokers, required this.cards});

  final List<SdrBrokerStagnationRow> brokers;
  final List<SdrBrokerCard> cards;

  static const SdrBrokerStagnation empty =
      SdrBrokerStagnation(brokers: [], cards: []);

  factory SdrBrokerStagnation.fromJson(Map<String, dynamic> json) =>
      SdrBrokerStagnation(
        brokers: _maps(json['brokers'])
            .map(SdrBrokerStagnationRow.fromJson)
            .toList(growable: false),
        cards: _maps(json['cards'])
            .map(SdrBrokerCard.fromJson)
            .where((c) => c.taskId.isNotEmpty)
            .toList(growable: false),
      );
}

/// Sub-tarefas por tipo (ligar, email, reunião, visita, whatsapp...).
class SdrSubtaskTypeRow {
  const SdrSubtaskTypeRow({
    required this.type,
    required this.created,
    required this.completed,
    required this.pending,
    required this.overdue,
  });

  final String type;
  final int created;
  final int completed;
  final int pending;
  final int overdue;

  factory SdrSubtaskTypeRow.fromJson(Map<String, dynamic> m) =>
      SdrSubtaskTypeRow(
        type: _s(m['type'], 'tarefa'),
        created: _i(m['created']),
        completed: _i(m['completed']),
        pending: _i(m['pending']),
        overdue: _i(m['overdue']),
      );
}

class SdrSubtaskAgentRow {
  const SdrSubtaskAgentRow({
    required this.agentId,
    required this.agentName,
    required this.total,
    required this.completed,
    required this.byType,
  });

  final String agentId;
  final String agentName;
  final int total;
  final int completed;
  final Map<String, int> byType;

  factory SdrSubtaskAgentRow.fromJson(Map<String, dynamic> m) =>
      SdrSubtaskAgentRow(
        agentId: _s(m['agentId']),
        agentName: _s(m['agentName'], 'Sem responsável'),
        total: _i(m['total']),
        completed: _i(m['completed']),
        byType: _intMap(m['byType']),
      );
}

class SdrSubtaskActivity {
  const SdrSubtaskActivity({
    required this.byType,
    required this.byAgent,
    required this.totalCreated,
    required this.totalCompleted,
    required this.totalPending,
    required this.totalOverdue,
    required this.averagePerDay,
  });

  final List<SdrSubtaskTypeRow> byType;
  final List<SdrSubtaskAgentRow> byAgent;
  final int totalCreated;
  final int totalCompleted;
  final int totalPending;
  final int totalOverdue;
  final double averagePerDay;

  static const SdrSubtaskActivity empty = SdrSubtaskActivity(
    byType: [],
    byAgent: [],
    totalCreated: 0,
    totalCompleted: 0,
    totalPending: 0,
    totalOverdue: 0,
    averagePerDay: 0,
  );

  factory SdrSubtaskActivity.fromJson(Map<String, dynamic> json) {
    final s = json['summary'] is Map
        ? Map<String, dynamic>.from(json['summary'] as Map)
        : const <String, dynamic>{};
    return SdrSubtaskActivity(
      byType: _maps(json['byType'])
          .map(SdrSubtaskTypeRow.fromJson)
          .toList(growable: false),
      byAgent: _maps(json['byAgent'])
          .map(SdrSubtaskAgentRow.fromJson)
          .toList(growable: false),
      totalCreated: _i(s['totalCreated']),
      totalCompleted: _i(s['totalCompleted']),
      totalPending: _i(s['totalPending']),
      totalOverdue: _i(s['totalOverdue']),
      averagePerDay: _d(s['averagePerDay']),
    );
  }
}

/// Rótulo humano do tipo de sub-tarefa (valores do back).
String sdrSubtaskTypeLabel(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'ligar':
      return 'Ligação';
    case 'email':
      return 'E-mail';
    case 'reuniao':
      return 'Reunião';
    case 'tarefa':
      return 'Tarefa';
    case 'almoco':
      return 'Almoço';
    case 'visita':
      return 'Visita';
    case 'whatsapp':
      return 'WhatsApp';
    default:
      return raw.isEmpty ? 'Outro' : raw[0].toUpperCase() + raw.substring(1);
  }
}
